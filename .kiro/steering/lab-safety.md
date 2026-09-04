---
inclusion: fileMatch
fileMatchPattern: ["scripts/**", "**/demo.sh", "src/content/docs/cli/**", "src/content/docs/install-tooling.mdx", "src/content/docs/prerequisites.mdx"]
---

# Lab safety

This lab creates billable AWS resources. These rules apply to `scripts/demo.sh` and to every CLI
page that tells a reader to run something.

## Never run AWS mutations unprompted

The agent does not create, update, or delete AWS resources on its own. Author the command, show
it, and let the operator run it. The `guard-aws-mutations` hook blocks accidental execution.

## Lab conventions

| Convention    | Value                                                                       |
| ------------- | --------------------------------------------------------------------------- |
| Profile       | `sandbox` (`AWS_PROFILE=sandbox`)                                            |
| Region        | `ap-southeast-2` (default; `Kinesis+CreateChannel` confirmed available)      |
| AWS CLI       | Minimum **2.36.35**; demo pin **2.36.38**                                     |
| Lab suffix    | `LAB_SUFFIX` — short unique token in every resource name; `demo.sh up`       |
|               | defaults to `$(date +%Y%m%d%H%M%S)` when unset                               |
| Name prefix   | `kds-s3-demo-${LAB_SUFFIX}-…` (bucket also appends account id)               |
| Tags          | `Project=kinesis-s3-delivery-walkthrough`                                   |
| Capacity mode | On-Demand only — the delivery channel requires it                           |
| Local dir     | `.lab/` (gitignored) — trust/permissions/destination JSON, producer zip, replay clone |
| Lab state     | `.lab-state.json` (gitignored) — ARNs and suffix from `demo.sh`             |

Every created resource carries the prefix and the tag so that a stray resource is greppable and
`down` can be trusted.

## `demo.sh` contract

| Subcommand | Does                                                                                     |
| ---------- | ---------------------------------------------------------------------------------------- |
| `up`       | Bucket, On-Demand stream, service execution role, delivery channel. Prints every ARN.    |
| `status`   | Stream status, channel state, delivered object count. Read-only.                         |
| `producer` | EventBridge schedule + Lambda `PutRecord` heartbeat. Start only after channel `ACTIVE`.  |
| `replay`   | Optional: runs `amazon-kinesis-replay` with `-streamArn` and `-speedup`. Ctrl+C to stop. |
| `viz`      | Builds `.lab/viz/report.html` (pipeline + charts + deep links). Read-only. Opens browser. |
| `down`     | Deletes producer then everything `up` created, after an explicit confirmation.           |

Rules for the script:

- Echo each AWS CLI command before running it — the script teaches, it does not hide.
- `set -euo pipefail`.
- Fail fast if `AWS_REGION` or `AWS_PROFILE` is unset; never fall back to an implicit account.
  Documented values: `AWS_PROFILE=sandbox`, `AWS_REGION=ap-southeast-2`.
- `down` empties the bucket before deleting it, or the delete fails.
- `down` deletes the **Heartbeat_Producer first** (rule → Lambda → role), then the **channel**,
  then bucket, then stream, then delivery IAM role and policies. An active channel keeps billing
  until it is deleted.
- `status` and `viz` must be safe to run at any time.
- Never use `--force`, `rm -rf`, or a wildcard delete that could reach outside the lab prefix.

## Cost callouts in content

Every page that creates a resource states that it is billable, and links the
[pricing page](https://aws.amazon.com/kinesis/data-streams/pricing/) instead of hardcoding a rate.
The teardown page carries a cleanup checklist covering producer, channel, bucket, stream, and IAM.

## Timing expectations

Delivery buffers for `DataFreshnessInSeconds` (300–900). Verification pages must tell the reader
to wait rather than implying objects appear immediately, and must state that records published
before the channel was `ACTIVE` are never delivered.
