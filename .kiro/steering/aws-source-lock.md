---
inclusion: always
---

# AWS source lock

This capability shipped in August 2026. Model training data about it is thin, so **every AWS
behavioural claim in this repository must trace to a source below**. If a claim is not in a
source and not verified in an account, it does not go in the walkthrough.

## Canonical sources

| Topic                    | Source                                                                                                              |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| Feature overview         | https://docs.aws.amazon.com/streams/latest/dev/data-delivery.html                                                    |
| S3 general purpose       | https://docs.aws.amazon.com/streams/latest/dev/data-delivery-s3.html                                                 |
| Getting started          | https://docs.aws.amazon.com/streams/latest/dev/data-delivery-s3-getting-started.html                                 |
| Create a delivery        | https://docs.aws.amazon.com/streams/latest/dev/data-delivery-s3-create.html                                          |
| CLI reference            | https://docs.aws.amazon.com/cli/latest/reference/kinesis/create-channel.html                                         |
| IAM                      | https://docs.aws.amazon.com/streams/latest/dev/data-delivery-iam.html                                                |
| Output key template      | https://docs.aws.amazon.com/streams/latest/dev/data-delivery-s3-key-template.html                                    |
| Monitoring               | https://docs.aws.amazon.com/streams/latest/dev/data-delivery-monitoring.html                                         |
| Quotas and constraints   | https://docs.aws.amazon.com/streams/latest/dev/data-delivery-quotas.html                                             |
| Pricing                  | https://aws.amazon.com/kinesis/data-streams/pricing/                                                                 |
| FAQs (ODA vs ODS)        | https://aws.amazon.com/kinesis/data-streams/faqs/                                                                    |
| Launch announcement      | https://aws.amazon.com/about-aws/whats-new/2026/08/kinesis/data-delivery-general-purpose-s3-buckets/                 |
| AWS CLI install          | https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html                                        |
| AWS CLI past releases    | https://docs.aws.amazon.com/cli/latest/userguide/getting-started-version.html                                        |
| AWS CLI install script   | https://awscli.amazonaws.com/v2/install.sh                                                                           |
| AWS CLI 2.36.38 linux x86_64 | https://awscli.amazonaws.com/awscli-exe-linux-x86_64-2.36.38.zip                                                  |
| Producer sample          | https://github.com/aws-samples/amazon-kinesis-replay                                                                 |
| Dataset                  | https://registry.opendata.aws/nyc-tlc-trip-records-pds/                                                              |
| PutRecord API            | https://docs.aws.amazon.com/kinesis/latest/APIReference/API_PutRecord.html                                           |
| EventBridge schedules    | https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-scheduled-rule-pattern.html                              |
| Lambda pricing (heartbeat) | https://aws.amazon.com/lambda/pricing/                                                                             |
| EventBridge pricing      | https://aws.amazon.com/eventbridge/pricing/                                                                          |

Use the `aws-docs` MCP server to re-read these pages rather than recalling them.

## Verified facts (safe to state)

1. The API resource is a **channel**: `create-channel`, `describe-channel`, `delete-channel`. The
   console calls it **S3 general purpose delivery**.
2. Supported only on streams in **On-Demand Standard or On-Demand Advantage** capacity mode.
   Provisioned mode is not supported.
3. Delivery **does not consume the stream's read throughput** and does not use enhanced fan-out
   slots, so existing consumers are unaffected.
4. Records are written in **source format with no transformation**. `RecordFormatType` for S3
   general purpose is `JSON`, `STRING`, or `BYTE_ARRAY` (`GSR_JSON` is streaming-tables only).
5. `DataFreshnessInSeconds` accepts **300–900** (5–15 minutes), default **300**.
6. **No backfill.** Only records written to the stream after the channel reaches `ACTIVE` are
   delivered.
7. Stream and destination bucket must be in the **same Region**. For S3 general purpose,
   only the destination bucket may live in a different account; channel and stream share one.
8. Lab evidence (`ap-southeast-2`, CLI **2.36.38**): `create-stream` with
   `--stream-mode-details StreamMode=ON_DEMAND` and `--tags Project=…` succeeds; the stream is
   `ACTIVE` with `StreamModeDetails.StreamMode=ON_DEMAND` within seconds. CLI
   `StreamMode` values are only `ON_DEMAND` | `PROVISIONED`. On-Demand Standard vs Advantage is
   an account-level setting (FAQs), not a create-stream enum.
9. Lab evidence (`ap-southeast-2`, CLI **2.36.38**): service role + `create-channel` with
   `BYTE_ARRAY`, GZIP destination, and no explicit DLQ succeeds. Create returns
   `ChannelStatus=CREATING`; channel ARN is `…:channel/<ChannelId>` (not the name). Omitting DLQ
   defaults to the destination bucket under `kinesis-channel/errors/…`. `describe-channel` reached
   `ACTIVE` within ~15 seconds in this run.
10. Lab evidence (`ap-southeast-2`, CLI **2.36.38**): always-on producer
    (`demo.sh producer`) — IAM role + Lambda python3.14 128 MB + EventBridge
    `rate(5 minutes)` — succeeds; immediate `lambda invoke` returns `{"ok": true}`; function
    reaches `Active`; rule `ENABLED` with the Lambda as target.
11. Lab evidence (`ap-southeast-2`, CLI **2.36.38**): after the heartbeat producer, GZIP objects
    appear under the configured output key template
    (`data/!{channel-name}/!{yyyy}/!{MM}/!{dd}/!{HH}/…`) about **five minutes** after puts
    (matching default `DataFreshnessInSeconds=300`). Decompressed payload is the heartbeat JSON.
    `get-metric-statistics` for `DeliveryToS3.SuccessfulRecordCount` / `DataFreshness` /
    `FailedRecordCount` returns datapoints only when **all three** dimensions
    (`StreamName`, `ChannelName`, `ChannelId`) are supplied — matching the monitoring doc note
    for targeting a specific delivery. Lab `demo.sh viz` builds a local HTML report
    (`.lab/viz/report.html`) from those metrics plus the S3 object list.
12. Lab evidence (`ap-southeast-2`, CLI **2.36.38**): `demo.sh down` deletes producer (rule,
    Lambda, role, **log group** `/aws/lambda/…-producer`), channel, bucket contents + bucket,
    stream, and delivery role after typing `LAB_SUFFIX`. Post-sweep: no `kds-s3-demo-` streams,
    channels (`ChannelSummaries`), buckets, roles, functions, or rules;
    `describe-channel` / `describe-stream-summary` return `ResourceNotFoundException`.
13. **Two deliveries per stream** maximum (one S3 general purpose, one streaming tables). One
    stream per channel.
14. `CreateChannel` is **asynchronous**: `CREATING` → `ACTIVE`. Poll with `describe-channel`.
    Control-plane calls are limited to 5 TPS per account per Region.
15. The calling principal needs `kinesis:CreateChannel` and `kinesis:AssociateStreamsWithChannel`
    on the stream ARN, plus `iam:PassRole` on the service execution role.
16. Service execution role trust is `kinesis.amazonaws.com` with `aws:SourceAccount` and an
    `aws:SourceArn` condition matching `arn:aws:kinesis:<region>:<account-id>:channel/*`.
17. The S3 permission policy needs bucket-level `s3:ListBucket` /
    `s3:ListBucketMultipartUploads` and object-level `s3:PutObject` plus the multipart upload
    actions.
18. A **dead-letter queue is optional** for S3 general purpose delivery. If omitted it defaults
    to the destination bucket with an error prefix.
19. Compression is `GZIP`, `ZSTD`, or none. When compression is enabled the output key template
    **must** end with an extension placeholder.
20. Metrics land in the `AWS/Kinesis` namespace prefixed `DeliveryToS3.` with dimensions
    `ChannelName`, `ChannelId`, and `StreamName`. For `GetMetricStatistics` / alarms, specify
    all three.
21. Only `DataFreshnessInSeconds` and `LoggingConfiguration` are mutable after creation.
    Everything else requires delete and recreate.
22. Billing is **per GB successfully delivered**. Records routed to the DLQ are not billed as
    delivered. An active channel keeps billing until deleted.
23. `amazon-kinesis-replay` takes **`-streamArn`** and optional **`-speedup`**. Older blog posts
    show `-streamName`; follow the current README.
24. Lab default Region is **`ap-southeast-2`**. `Kinesis+CreateChannel` reports `isAvailableIn`
    for `ap-southeast-2`, `ap-southeast-6`, and `us-east-1` (AWS regional availability catalog,
    checked 2026-09-03).
25. AWS CLI **minimum** for this lab is **2.36.35** — first release with `create-channel` and
    related channel APIs ([CHANGELOG 2.36.35](https://github.com/aws/aws-cli/blob/v2/CHANGELOG.rst)).
    The demo pins the **latest stable** at authoring time (**2.36.38**, checked 2026-09-03).
26. `amazon-kinesis-replay` builds with **Java 11** (`pom.xml` `java.version`).

## Known trap: stale guidance

| Stale claim                             | Correct                                                          |
| --------------------------------------- | ---------------------------------------------------------------- |
| "Use Firehose to get Kinesis into S3"   | This walkthrough is the native channel; Firehose is a different product |
| "Any stream capacity mode works"        | On-Demand only                                                   |
| "Delivery is near-instant"              | 5–15 minute freshness window                                     |
| "A DLQ bucket is required"              | Optional for S3 general purpose                                  |
| `-streamName` for the replay JAR        | `-streamArn`                                                     |
| "Existing stream data is delivered"     | No backfill                                                      |
| "One CloudWatch dimension is enough"    | `get-metric-statistics` needs StreamName + ChannelName + ChannelId |

## Unresolved — must not be asserted

Mark these `TBD` in content until confirmed in an account during the evidence pass:

- Whether the replay JAR runs cleanly in CloudShell, or whether a local JDK is required.
- Current per-GB prices — link the pricing page rather than hardcoding numbers that age.

## Rules

- Cite the source page for every behavioural claim; do not paraphrase from memory.
- Copy CLI examples from the AWS pages and change only names, ARNs, and Region.
- Label anything not yet run in an account as unverified. Only the evidence pass may mark a step
  "verified".
- Never invent flags, metric names, IAM actions, or console labels. If a name cannot be found in
  a source, say so instead of guessing.
- When a source contradicts something already written in this repo, fix the repo and note it in
  the spec.
