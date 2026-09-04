#!/usr/bin/env bash
# Guided lab orchestrator for Kinesis → general purpose S3 delivery.
#
# Echoes every AWS CLI command before running it. Creates nothing unless the
# operator runs a mutating subcommand. See .kiro/steering/lab-safety.md.
#
# Usage:
#   ./scripts/demo.sh up|status|producer|replay|viz|down
#
# Required env:
#   AWS_REGION   — lab Region (documented default: ap-southeast-2)
#   AWS_PROFILE  — named profile (documented: sandbox); never fall back to an implicit account
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${ROOT}/.lab-state.json"
# Gitignored working dir: policy JSON, channel config, producer zip, replay sample clone.
WORK_DIR="${ROOT}/.lab"
TAG_KEY="Project"
TAG_VALUE="kinesis-s3-delivery-walkthrough"
NAME_PREFIX="kds-s3-demo"
DEFAULT_REGION="ap-southeast-2"
# create-channel first shipped in AWS CLI 2.36.35; demo pin is 2.36.38.
AWS_CLI_MIN_VERSION="2.36.35"
AWS_CLI_DEMO_VERSION="2.36.38"
FRESHNESS_SECONDS=300
DEFAULT_PRODUCER_RATE="rate(5 minutes)"
REPLAY_REPO="https://github.com/aws-samples/amazon-kinesis-replay.git"
REPLAY_DIR="${WORK_DIR}/amazon-kinesis-replay"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./scripts/demo.sh <command>

Commands:
  up         Create bucket, On-Demand stream, service role, and delivery channel
  status     Show stream, channel, and object count (read-only)
  producer   Always-on EventBridge → Lambda PutRecord heartbeat (after channel ACTIVE)
  replay     Optional burst: amazon-kinesis-replay against the stream ARN
  viz        Build HTML delivery report and open it (read-only)
  down       Tear down lab resources (including producer) after confirmation

Required environment:
  AWS_REGION   Lab Region (documented default: ap-southeast-2)
  AWS_PROFILE  Named AWS CLI profile (documented: sandbox)

AWS CLI:
  Minimum  2.36.35  (create-channel)
  Demo pin 2.36.38  (latest stable at authoring)

Optional:
  LAB_SUFFIX              Short unique token in every resource name
                          (default on up: $(date +%Y%m%d%H%M%S); stored in .lab-state.json)
  PRODUCER_RATE           EventBridge schedule expression (default: rate(5 minutes))
  REPLAY_SPEEDUP          Replay speed multiplier (default: 60)
  REPLAY_BUCKET           Optional alternate S3 bucket for replay input
  REPLAY_BUCKET_REGION    Region of REPLAY_BUCKET
  REPLAY_OBJECT_PREFIX    Prefix of objects to replay from REPLAY_BUCKET
  KDS_LAB_ALLOW_AWS=1     Required for mutating subcommands when the Kiro guard is active
EOF
}

version_ge() {
  # Return 0 if $1 >= $2 (dotted numeric versions).
  printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1 | grep -qx "$2"
}

require_aws_cli_version() {
  command -v aws >/dev/null 2>&1 || die "aws CLI not found. See Install tooling — minimum ${AWS_CLI_MIN_VERSION}, demo ${AWS_CLI_DEMO_VERSION}."
  local reported
  reported="$(aws --version 2>&1 | head -n1)"
  local ver
  ver="$(printf '%s' "$reported" | sed -n 's/^aws-cli\/\([0-9.]*\).*/\1/p')"
  [[ -n "$ver" ]] || die "Could not parse aws --version output: ${reported}"
  version_ge "$ver" "$AWS_CLI_MIN_VERSION" || die \
    "AWS CLI ${ver} is too old. Minimum is ${AWS_CLI_MIN_VERSION} (create-channel). Demo pin is ${AWS_CLI_DEMO_VERSION}. See Install tooling."
  if ! version_ge "$ver" "$AWS_CLI_DEMO_VERSION"; then
    printf 'warning: AWS CLI %s is below the demo pin %s — commands may still work if >= %s\n' \
      "$ver" "$AWS_CLI_DEMO_VERSION" "$AWS_CLI_MIN_VERSION" >&2
  fi
  printf 'aws cli: %s\n' "$reported" >&2
}

require_env() {
  [[ -n "${AWS_REGION:-}" ]] || die "AWS_REGION is unset. Example: export AWS_REGION=${DEFAULT_REGION}"
  [[ -n "${AWS_PROFILE:-}" ]] || die "AWS_PROFILE is unset. Example: export AWS_PROFILE=sandbox"
  require_aws_cli_version
}

# Echo then run. Every AWS call goes through here so the script teaches.
# Echo goes to stderr so command substitutions stay clean.
run() {
  printf '+ %s\n' "$*" >&2
  "$@"
}

aws_cli() {
  run aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"
}

need_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required to read ${STATE_FILE}"
}

write_state() {
  need_jq
  local tmp
  tmp="$(mktemp)"
  jq -n \
    --arg region "$AWS_REGION" \
    --arg profile "$AWS_PROFILE" \
    --arg suffix "$LAB_SUFFIX" \
    --arg account "$ACCOUNT_ID" \
    --arg stream_name "$STREAM_NAME" \
    --arg stream_arn "$STREAM_ARN" \
    --arg bucket "$BUCKET_NAME" \
    --arg bucket_arn "$BUCKET_ARN" \
    --arg role_name "$ROLE_NAME" \
    --arg role_arn "$ROLE_ARN" \
    --arg channel_name "$CHANNEL_NAME" \
    --arg channel_arn "${CHANNEL_ARN:-}" \
    --arg channel_id "${CHANNEL_ID:-}" \
    '{
      region: $region,
      profile: $profile,
      suffix: $suffix,
      accountId: $account,
      streamName: $stream_name,
      streamArn: $stream_arn,
      bucketName: $bucket,
      bucketArn: $bucket_arn,
      roleName: $role_name,
      roleArn: $role_arn,
      channelName: $channel_name,
      channelArn: $channel_arn,
      channelId: $channel_id
    }' >"$tmp"
  mv "$tmp" "$STATE_FILE"
  printf 'Wrote %s\n' "$STATE_FILE"
}

load_state() {
  need_jq
  [[ -f "$STATE_FILE" ]] || die "No lab state at ${STATE_FILE}. Run: ./scripts/demo.sh up"
  AWS_REGION="$(jq -r '.region' "$STATE_FILE")"
  AWS_PROFILE="$(jq -r '.profile' "$STATE_FILE")"
  LAB_SUFFIX="$(jq -r '.suffix' "$STATE_FILE")"
  ACCOUNT_ID="$(jq -r '.accountId' "$STATE_FILE")"
  STREAM_NAME="$(jq -r '.streamName' "$STATE_FILE")"
  STREAM_ARN="$(jq -r '.streamArn' "$STATE_FILE")"
  BUCKET_NAME="$(jq -r '.bucketName' "$STATE_FILE")"
  BUCKET_ARN="$(jq -r '.bucketArn' "$STATE_FILE")"
  ROLE_NAME="$(jq -r '.roleName' "$STATE_FILE")"
  ROLE_ARN="$(jq -r '.roleArn' "$STATE_FILE")"
  CHANNEL_NAME="$(jq -r '.channelName' "$STATE_FILE")"
  CHANNEL_ARN="$(jq -r '.channelArn' "$STATE_FILE")"
  CHANNEL_ID="$(jq -r '.channelId // empty' "$STATE_FILE")"
  [[ "$STREAM_NAME" == ${NAME_PREFIX}-* ]] || die "Refusing state whose stream name lacks prefix ${NAME_PREFIX}-"
  PRODUCER_ROLE="${NAME_PREFIX}-${LAB_SUFFIX}-producer-role"
  PRODUCER_FN="${NAME_PREFIX}-${LAB_SUFFIX}-producer"
  PRODUCER_RULE="${NAME_PREFIX}-${LAB_SUFFIX}-producer-schedule"
  PRODUCER_DIR="${WORK_DIR}/producer"
}

derive_names() {
  STREAM_NAME="${NAME_PREFIX}-${LAB_SUFFIX}-stream"
  CHANNEL_NAME="${NAME_PREFIX}-${LAB_SUFFIX}-channel"
  ROLE_NAME="${NAME_PREFIX}-${LAB_SUFFIX}-role"
  # Bucket names are global; include account id so they stay unique and greppable.
  BUCKET_NAME="${NAME_PREFIX}-${LAB_SUFFIX}-${ACCOUNT_ID}"
  BUCKET_ARN="arn:aws:s3:::${BUCKET_NAME}"
  PRODUCER_ROLE="${NAME_PREFIX}-${LAB_SUFFIX}-producer-role"
  PRODUCER_FN="${NAME_PREFIX}-${LAB_SUFFIX}-producer"
  PRODUCER_RULE="${NAME_PREFIX}-${LAB_SUFFIX}-producer-schedule"
  PRODUCER_DIR="${WORK_DIR}/producer"
}

assert_prefix() {
  local name="$1"
  [[ "$name" == ${NAME_PREFIX}-* ]] || die "Refusing to touch '${name}' — name must start with ${NAME_PREFIX}-"
}

wait_stream_active() {
  local status=""
  for _ in $(seq 1 60); do
    status="$(aws_cli kinesis describe-stream-summary \
      --stream-name "$STREAM_NAME" \
      --query 'StreamDescriptionSummary.StreamStatus' \
      --output text)"
    printf 'stream status: %s\n' "$status"
    [[ "$status" == "ACTIVE" ]] && return 0
    sleep 2
  done
  die "Timed out waiting for stream ${STREAM_NAME} to become ACTIVE"
}

wait_channel_active() {
  local status=""
  for _ in $(seq 1 90); do
    status="$(aws_cli kinesis describe-channel \
      --channel-arn "$CHANNEL_ARN" \
      --query 'ChannelDescription.ChannelStatus' \
      --output text)"
    printf 'channel status: %s\n' "$status"
    [[ "$status" == "ACTIVE" ]] && return 0
    [[ "$status" == "FAILED" ]] && {
      aws_cli kinesis describe-channel --channel-arn "$CHANNEL_ARN"
      die "Channel entered FAILED — fix IAM/bucket, delete, and recreate"
    }
    sleep 5
  done
  die "Timed out waiting for channel ${CHANNEL_ARN} to become ACTIVE"
}

cmd_up() {
  require_env
  command -v jq >/dev/null 2>&1 || die "jq is required"
  mkdir -p "$WORK_DIR"

  if [[ -f "$STATE_FILE" ]]; then
    die "Lab state already exists at ${STATE_FILE}. Run status, or down first."
  fi

  ACCOUNT_ID="$(aws_cli sts get-caller-identity --query Account --output text)"
  LAB_SUFFIX="${LAB_SUFFIX:-$(date +%Y%m%d%H%M%S)}"
  derive_names
  assert_prefix "$STREAM_NAME"
  assert_prefix "$BUCKET_NAME"
  assert_prefix "$ROLE_NAME"
  assert_prefix "$CHANNEL_NAME"

  printf 'Creating lab resources in %s (account %s, suffix %s)\n' \
    "$AWS_REGION" "$ACCOUNT_ID" "$LAB_SUFFIX"

  # --- destination bucket ---
  if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws_cli s3api create-bucket --bucket "$BUCKET_NAME"
  else
    aws_cli s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}"
  fi
  aws_cli s3api put-bucket-tagging \
    --bucket "$BUCKET_NAME" \
    --tagging "TagSet=[{Key=${TAG_KEY},Value=${TAG_VALUE}}]"

  # --- On-Demand stream ---
  # Capacity mode is TBD-verified for ODS vs ODA on the pinned CLI; ON_DEMAND is required.
  aws_cli kinesis create-stream \
    --stream-name "$STREAM_NAME" \
    --stream-mode-details StreamMode=ON_DEMAND \
    --tags "${TAG_KEY}=${TAG_VALUE}"
  wait_stream_active
  STREAM_ARN="$(aws_cli kinesis describe-stream-summary \
    --stream-name "$STREAM_NAME" \
    --query 'StreamDescriptionSummary.StreamARN' \
    --output text)"

  # --- service execution role ---
  cat >"${WORK_DIR}/trust-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "kinesis.amazonaws.com" },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": { "aws:SourceAccount": "${ACCOUNT_ID}" },
        "ArnLike": {
          "aws:SourceArn": "arn:aws:kinesis:${AWS_REGION}:${ACCOUNT_ID}:channel/*"
        }
      }
    }
  ]
}
EOF

  # Permission policy matches the general-purpose S3 section of
  # https://docs.aws.amazon.com/streams/latest/dev/data-delivery-iam.html
  # KMS statements omitted: lab bucket uses default SSE-S3.
  cat >"${WORK_DIR}/permissions-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DeliveryBucketList",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:ListBucketMultipartUploads"],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
    },
    {
      "Sid": "DeliveryBucketWrite",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:CreateMultipartUpload",
        "s3:UploadPart",
        "s3:CompleteMultipartUpload",
        "s3:ListMultipartUploads",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": ["arn:aws:s3:::${BUCKET_NAME}/*"]
    },
    {
      "Sid": "DLQBucketAccess",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:ListBucket", "s3:ListBucketMultipartUploads"],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ],
      "Condition": {
        "StringEquals": { "aws:ResourceAccount": "${ACCOUNT_ID}" }
      }
    }
  ]
}
EOF

  aws_cli iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "file://${WORK_DIR}/trust-policy.json" \
    --tags "Key=${TAG_KEY},Value=${TAG_VALUE}"
  aws_cli iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "${ROLE_NAME}-s3" \
    --policy-document "file://${WORK_DIR}/permissions-policy.json"
  ROLE_ARN="$(aws_cli iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)"

  # IAM is eventually consistent; a short pause avoids PassRole races.
  sleep 10

  # Output key template uses !{...} — must go through a file, not shell quoting.
  # Compression GZIP requires !{extension}. See data-delivery-s3-key-template.html.
  cat >"${WORK_DIR}/s3-destination.json" <<EOF
{
  "DataFreshnessInSeconds": ${FRESHNESS_SECONDS},
  "StorageConfiguration": {
    "BucketARN": "${BUCKET_ARN}",
    "ExpectedBucketOwner": "${ACCOUNT_ID}",
    "StorageClass": "STANDARD",
    "CompressionType": "GZIP",
    "OutputKeyTemplate": "data/!{channel-name}/!{yyyy}/!{MM}/!{dd}/!{HH}/!{channel-id}-!{mm}!{extension}"
  }
}
EOF

  cat >"${WORK_DIR}/stream-config.json" <<EOF
[
  {
    "StreamARN": "${STREAM_ARN}",
    "RecordConfiguration": { "RecordFormatType": "BYTE_ARRAY" }
  }
]
EOF

  CHANNEL_ARN="$(aws_cli kinesis create-channel \
    --channel-name "$CHANNEL_NAME" \
    --service-execution-role-arn "$ROLE_ARN" \
    --stream-configuration-list "file://${WORK_DIR}/stream-config.json" \
    --s3-destination-configuration "file://${WORK_DIR}/s3-destination.json" \
    --tags "Key=${TAG_KEY},Value=${TAG_VALUE}" \
    --query 'ChannelDescription.ChannelARN' \
    --output text)"
  CHANNEL_ID="$(aws_cli kinesis describe-channel \
    --channel-arn "$CHANNEL_ARN" \
    --query 'ChannelDescription.ChannelId' \
    --output text)"

  write_state
  wait_channel_active
  write_state

  cat <<EOF

Lab is up.
  Stream ARN:  ${STREAM_ARN}
  Bucket:      s3://${BUCKET_NAME}
  Role ARN:    ${ROLE_ARN}
  Channel ARN: ${CHANNEL_ARN}
  Channel ID:  ${CHANNEL_ID}

Next:
  ./scripts/demo.sh producer   # always-on heartbeat (default path)
  ./scripts/demo.sh replay     # optional high-volume burst
  ./scripts/demo.sh status
EOF
}

cmd_status() {
  require_env
  load_state

  aws_cli kinesis describe-stream-summary \
    --stream-name "$STREAM_NAME" \
    --query 'StreamDescriptionSummary.{Name:StreamName,Status:StreamStatus,Mode:StreamModeDetails.StreamMode,Arn:StreamARN}'

  if [[ -n "$CHANNEL_ARN" && "$CHANNEL_ARN" != "null" ]]; then
    aws_cli kinesis describe-channel \
      --channel-arn "$CHANNEL_ARN" \
      --query 'ChannelDescription.{Name:ChannelName,Status:ChannelStatus,Arn:ChannelARN,Id:ChannelId}'
  else
    printf 'No channel ARN in state yet.\n'
  fi

  aws_cli s3 ls "s3://${BUCKET_NAME}/data/" --recursive || true
  local count
  count="$(aws_cli s3api list-objects-v2 \
    --bucket "$BUCKET_NAME" \
    --prefix "data/" \
    --query 'length(Contents || `[]`)' \
    --output text 2>/dev/null || echo 0)"
  printf 'Delivered object count under data/: %s\n' "$count"
  printf 'Freshness window is %ss — objects appear only after that buffer.\n' "$FRESHNESS_SECONDS"
}

ensure_replay_jar() {
  mkdir -p "$WORK_DIR"
  if [[ -f "${REPLAY_DIR}/target/amazon-kinesis-replay.jar" ]]; then
    REPLAY_JAR="${REPLAY_DIR}/target/amazon-kinesis-replay.jar"
    return 0
  fi
  command -v git >/dev/null 2>&1 || die "git is required to fetch amazon-kinesis-replay"
  command -v mvn >/dev/null 2>&1 || die "mvn (Maven) is required to build amazon-kinesis-replay"
  if [[ ! -d "$REPLAY_DIR/.git" ]]; then
    run git clone --depth 1 "$REPLAY_REPO" "$REPLAY_DIR"
  fi
  (
    cd "$REPLAY_DIR"
    run mvn -q -DskipTests package
  )
  REPLAY_JAR="$(find "$REPLAY_DIR/target" -name 'amazon-kinesis-replay*.jar' ! -name '*-sources.jar' | head -n1)"
  [[ -n "$REPLAY_JAR" ]] || die "Build finished but no replay JAR found under ${REPLAY_DIR}/target"
}

cmd_producer() {
  require_env
  load_state
  command -v zip >/dev/null 2>&1 || die "zip is required to package the producer Lambda"
  mkdir -p "$PRODUCER_DIR"
  assert_prefix "$PRODUCER_ROLE"
  assert_prefix "$PRODUCER_FN"
  assert_prefix "$PRODUCER_RULE"

  local status
  status="$(aws_cli kinesis describe-channel \
    --channel-arn "$CHANNEL_ARN" \
    --query 'ChannelDescription.ChannelStatus' \
    --output text)"
  [[ "$status" == "ACTIVE" ]] || die "Channel is ${status}; start producer only after ACTIVE (no backfill)"

  local rate="${PRODUCER_RATE:-$DEFAULT_PRODUCER_RATE}"
  local producer_role_arn="arn:aws:iam::${ACCOUNT_ID}:role/${PRODUCER_ROLE}"

  cat >"${PRODUCER_DIR}/trust.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "lambda.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

  cat >"${PRODUCER_DIR}/permissions.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["kinesis:PutRecord"],
      "Resource": "${STREAM_ARN}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:*"
    }
  ]
}
EOF

  cat >"${PRODUCER_DIR}/handler.py" <<'PY'
import json
import os
import time

import boto3

kinesis = boto3.client("kinesis")
STREAM_NAME = os.environ["STREAM_NAME"]


def handler(event, context):
    body = {"source": "kds-s3-demo-heartbeat", "ts": int(time.time())}
    kinesis.put_record(
        StreamName=STREAM_NAME,
        Data=json.dumps(body).encode("utf-8"),
        PartitionKey="heartbeat",
    )
    return {"ok": True}
PY

  if ! aws_cli iam get-role --role-name "$PRODUCER_ROLE" >/dev/null 2>&1; then
    aws_cli iam create-role \
      --role-name "$PRODUCER_ROLE" \
      --assume-role-policy-document "file://${PRODUCER_DIR}/trust.json" \
      --tags "Key=${TAG_KEY},Value=${TAG_VALUE}"
  fi
  aws_cli iam put-role-policy \
    --role-name "$PRODUCER_ROLE" \
    --policy-name "${PRODUCER_ROLE}-kinesis" \
    --policy-document "file://${PRODUCER_DIR}/permissions.json"

  printf 'Waiting 10s for IAM role propagation…\n'
  sleep 10

  ( cd "$PRODUCER_DIR" && zip -q -j function.zip handler.py )

  if ! aws_cli lambda get-function --function-name "$PRODUCER_FN" >/dev/null 2>&1; then
    aws_cli lambda create-function \
      --function-name "$PRODUCER_FN" \
      --runtime python3.14 \
      --role "$producer_role_arn" \
      --handler handler.handler \
      --timeout 10 \
      --memory-size 128 \
      --zip-file "fileb://${PRODUCER_DIR}/function.zip" \
      --environment "Variables={STREAM_NAME=${STREAM_NAME}}" \
      --tags "${TAG_KEY}=${TAG_VALUE}"
  else
    aws_cli lambda update-function-code \
      --function-name "$PRODUCER_FN" \
      --zip-file "fileb://${PRODUCER_DIR}/function.zip" >/dev/null
    aws_cli lambda update-function-configuration \
      --function-name "$PRODUCER_FN" \
      --environment "Variables={STREAM_NAME=${STREAM_NAME}}" >/dev/null
  fi

  # create-function can return while State is still Pending.
  local lambda_state=""
  for _ in $(seq 1 30); do
    lambda_state="$(aws_cli lambda get-function-configuration \
      --function-name "$PRODUCER_FN" \
      --query 'State' \
      --output text)"
    [[ "$lambda_state" == "Active" ]] && break
    sleep 1
  done
  [[ "$lambda_state" == "Active" ]] || die "Lambda ${PRODUCER_FN} did not become Active (state=${lambda_state})"

  local fn_arn
  fn_arn="$(aws_cli lambda get-function \
    --function-name "$PRODUCER_FN" \
    --query 'Configuration.FunctionArn' \
    --output text)"

  aws_cli events put-rule \
    --name "$PRODUCER_RULE" \
    --schedule-expression "$rate" \
    --state ENABLED \
    --tags "Key=${TAG_KEY},Value=${TAG_VALUE}"

  local rule_arn
  rule_arn="$(aws_cli events describe-rule --name "$PRODUCER_RULE" --query Arn --output text)"

  aws_cli lambda add-permission \
    --function-name "$PRODUCER_FN" \
    --statement-id "${PRODUCER_RULE}-invoke" \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn "$rule_arn" 2>/dev/null || true

  cat >"${PRODUCER_DIR}/targets.json" <<EOF
[{"Id": "1", "Arn": "${fn_arn}"}]
EOF

  aws_cli events put-targets \
    --rule "$PRODUCER_RULE" \
    --targets "file://${PRODUCER_DIR}/targets.json"

  # Fire once immediately so the reader need not wait for the first schedule tick.
  aws_cli lambda invoke \
    --function-name "$PRODUCER_FN" \
    --payload '{}' \
    "${PRODUCER_DIR}/invoke-out.json" >/dev/null
  printf 'Immediate invoke result: %s\n' "$(cat "${PRODUCER_DIR}/invoke-out.json")"

  cat <<EOF

Always-on producer is running.
  Function:  ${PRODUCER_FN}
  Rule:      ${PRODUCER_RULE} (${rate})
  Stream:    ${STREAM_ARN}

Objects appear in S3 only after DataFreshnessInSeconds (${FRESHNESS_SECONDS}s default).
Optional burst: ./scripts/demo.sh replay
Tear down removes the producer with ./scripts/demo.sh down
EOF
}

cmd_replay() {
  require_env
  load_state
  command -v java >/dev/null 2>&1 || die "java is required for amazon-kinesis-replay"

  local status
  status="$(aws_cli kinesis describe-channel \
    --channel-arn "$CHANNEL_ARN" \
    --query 'ChannelDescription.ChannelStatus' \
    --output text)"
  [[ "$status" == "ACTIVE" ]] || die "Channel is ${status}; start replay only after ACTIVE (no backfill)"

  ensure_replay_jar

  local speedup="${REPLAY_SPEEDUP:-60}"
  # Default sample is baked into amazon-kinesis-replay; override with bucket/prefix env vars.
  local extra=()
  if [[ -n "${REPLAY_BUCKET:-}" ]]; then
    [[ -n "${REPLAY_BUCKET_REGION:-}" && -n "${REPLAY_OBJECT_PREFIX:-}" ]] \
      || die "REPLAY_BUCKET requires REPLAY_BUCKET_REGION and REPLAY_OBJECT_PREFIX"
    extra+=(-bucketName "$REPLAY_BUCKET" -bucketRegion "$REPLAY_BUCKET_REGION" -objectPrefix "$REPLAY_OBJECT_PREFIX")
  fi

  cat <<EOF
Starting optional replay burst.
  JAR:      ${REPLAY_JAR}
  Stream:   ${STREAM_ARN}
  Speedup:  ${speedup}
  Dataset:  ${REPLAY_BUCKET:-default NYC TLC sample baked into amazon-kinesis-replay}

The sample takes -streamArn (not -streamName). Stop with Ctrl+C.
The always-on heartbeat (if started) keeps running independently.
Records written before the channel was ACTIVE are never delivered.
EOF

  # Flags from https://github.com/aws-samples/amazon-kinesis-replay README.
  run java -jar "$REPLAY_JAR" \
    -streamArn "$STREAM_ARN" \
    -speedup "$speedup" \
    "${extra[@]}"
}

cmd_viz() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      -h | --help)
        cat <<'EOF'
Usage: ./scripts/demo.sh viz

Builds a professional HTML lab report (read-only) under .lab/viz/report.html:
  pipeline status, DeliveryToS3 charts, latest record, recent objects,
  plus deep links to the S3 prefix and CloudWatch graph.

Requires: python3, AWS_PROFILE, AWS_REGION, .lab-state.json
Opens the report when a desktop opener is available.
EOF
        return 0
        ;;
      *)
        die "viz: unknown argument '${arg}'"
        ;;
    esac
  done

  if [[ ! -f "$STATE_FILE" ]]; then
    cat <<'EOF'
No .lab-state.json — run ./scripts/demo.sh up, produce records, wait for freshness, then:

  ./scripts/demo.sh viz
EOF
    return 0
  fi

  require_env
  load_state
  need_jq
  command -v python3 >/dev/null 2>&1 || die "python3 is required to build the viz report"

  mkdir -p "${WORK_DIR}/viz"
  export KDS_LAB_STATE="$STATE_FILE"
  export KDS_VIZ_DIR="${WORK_DIR}/viz"
  export AWS_PROFILE AWS_REGION

  printf 'Building delivery report…\n'
  local report
  report="$(python3 "${ROOT}/scripts/viz/build_report.py")"

  cat <<EOF

Report    ${report}
Lab       ${LAB_SUFFIX}
Bucket    s3://${BUCKET_NAME}
Channel   ${CHANNEL_NAME} (${CHANNEL_ID:-?})

Re-run viz anytime to refresh. Creates no AWS resources.
EOF

  if command -v xdg-open >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    xdg-open "$report" >/dev/null 2>&1 &
    printf 'Opened in the default browser.\n'
  elif command -v open >/dev/null 2>&1; then
    open "$report" >/dev/null 2>&1 &
    printf 'Opened in the default browser.\n'
  else
    printf 'Open: %s\n' "$report"
  fi
}

empty_bucket() {
  assert_prefix "$BUCKET_NAME"
  # Empty via aws s3 rm -- only under this exact bucket name.
  aws_cli s3 rm "s3://${BUCKET_NAME}" --recursive || true
}

cmd_down() {
  require_env
  load_state
  assert_prefix "$STREAM_NAME"
  assert_prefix "$BUCKET_NAME"
  assert_prefix "$ROLE_NAME"
  assert_prefix "$CHANNEL_NAME"
  assert_prefix "$PRODUCER_ROLE"
  assert_prefix "$PRODUCER_FN"
  assert_prefix "$PRODUCER_RULE"

  cat <<EOF
This will delete lab resources with prefix ${NAME_PREFIX}-${LAB_SUFFIX}-:
  producer rule      ${PRODUCER_RULE}
  producer function  ${PRODUCER_FN}
  producer role      ${PRODUCER_ROLE}
  channel            ${CHANNEL_ARN}
  bucket             s3://${BUCKET_NAME}
  stream             ${STREAM_NAME}
  role               ${ROLE_NAME}
EOF
  read -r -p "Type the lab suffix '${LAB_SUFFIX}' to confirm: " confirm
  [[ "$confirm" == "$LAB_SUFFIX" ]] || die "Confirmation did not match; aborting"

  # Stop putting records before deleting the channel.
  aws_cli events remove-targets --rule "$PRODUCER_RULE" --ids 1 2>/dev/null || true
  aws_cli events delete-rule --name "$PRODUCER_RULE" 2>/dev/null || true
  aws_cli lambda delete-function --function-name "$PRODUCER_FN" 2>/dev/null || true
  aws_cli iam delete-role-policy \
    --role-name "$PRODUCER_ROLE" \
    --policy-name "${PRODUCER_ROLE}-kinesis" 2>/dev/null || true
  aws_cli iam delete-role --role-name "$PRODUCER_ROLE" 2>/dev/null || true
  # Lambda keeps a log group after the function is gone — remove the lab-prefixed one.
  aws_cli logs delete-log-group \
    --log-group-name "/aws/lambda/${PRODUCER_FN}" 2>/dev/null || true

  if [[ -n "$CHANNEL_ARN" && "$CHANNEL_ARN" != "null" ]]; then
    aws_cli kinesis delete-channel --channel-arn "$CHANNEL_ARN" || true
    # Channel delete is asynchronous; wait briefly before removing the stream.
    for _ in $(seq 1 30); do
      if ! aws_cli kinesis describe-channel --channel-arn "$CHANNEL_ARN" >/dev/null 2>&1; then
        break
      fi
      sleep 2
    done
  fi

  empty_bucket
  aws_cli s3api delete-bucket --bucket "$BUCKET_NAME" || true

  aws_cli kinesis delete-stream --stream-name "$STREAM_NAME" --enforce-consumer-deletion || true

  aws_cli iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "${ROLE_NAME}-s3" || true
  aws_cli iam delete-role --role-name "$ROLE_NAME" || true

  rm -f "$STATE_FILE"
  printf 'Teardown requested. State file removed. Confirm with the cleanup checklist.\n'
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    up) shift; cmd_up "$@" ;;
    status) shift; cmd_status "$@" ;;
    producer) shift; cmd_producer "$@" ;;
    replay) shift; cmd_replay "$@" ;;
    viz) shift; cmd_viz "$@" ;;
    down) shift; cmd_down "$@" ;;
    -h | --help | help | "")
      usage
      exit 0
      ;;
    *)
      usage
      die "Unknown command: ${cmd}"
      ;;
  esac
}

main "$@"
