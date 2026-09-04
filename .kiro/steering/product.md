---
inclusion: always
---

# Product

`kinesis-s3-delivery-walkthrough` publishes a guided CLI walkthrough for **Amazon Kinesis Data
Streams delivery to general purpose Amazon S3 buckets** — the capability
[announced on 29 Aug 2026](https://aws.amazon.com/about-aws/whats-new/2026/08/kinesis/data-delivery-general-purpose-s3-buckets/).

## The story

Feed an On-Demand Kinesis data stream (cheap always-on Lambda heartbeat by default; optional NYC
TLC taxi replay burst), let managed delivery land raw records in S3, visualize what landed, then
tear everything down.

```text
EventBridge → Lambda PutRecord  (default always-on)
amazon-kinesis-replay           (optional burst)
        │
        ▼
Kinesis Data Streams (On-Demand)
        │  managed delivery (channel)
        ▼
S3 general purpose bucket (raw, time-prefixed)
        │
        ▼
Visualization (choice left to the reader)
```

## Audience

Engineers who already know S3 and basic streaming concepts, and who want to see the managed
delivery path without building a consumer application.

## Shape of the lab

- **Guided AWS CLI**, wrapped by `scripts/demo.sh`
  (`up` / `status` / `producer` / `replay` / `viz` / `down`).
- Default producer is an always-on scheduled Lambda; optional replay JAR for volume.
- Target length: 15–20 minutes end to end (plus freshness wait for first S3 objects).

## In scope

- Stream, bucket, service execution role, delivery channel, always-on producer, optional replay,
  verification, teardown.
- Generic visualization page; optional branded HTML report (`demo.sh viz`).

## Out of scope (v1)

- CDK, Terraform, or CloudFormation as the primary path.
- Always-on EC2 / Fargate producers.
- Managed Service for Apache Flink, OpenSearch.
- Streaming tables / Apache Iceberg on S3 Tables — mention as a sibling capability only.
- A polished custom dashboard.

## Visual bias

Prefer diagrams, tables, and short numbered steps over prose. Text diagrams are acceptable now
and get replaced with real diagrams and screenshots during the evidence pass — see
`#evidence-capture`.
