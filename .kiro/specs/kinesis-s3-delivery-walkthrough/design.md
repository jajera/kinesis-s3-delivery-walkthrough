# Design Document

## Overview

An Astro Starlight documentation site plus a guided shell script that walk a reader through
Amazon Kinesis Data Streams delivery to a general purpose Amazon S3 bucket. The default producer
is a cheap always-on EventBridge → Lambda heartbeat; an optional NYC TLC taxi replay burst adds
volume.

The design keeps three things separate:

| Concern         | Where it lives                                    |
| --------------- | ------------------------------------------------- |
| What AWS does   | `.kiro/steering/aws-source-lock.md` + page References |
| How to run it   | `scripts/demo.sh` and the CLI pages               |
| How it is shown | Astro Starlight components                        |

## Lab architecture

```text
┌────────────────────────────────┐
│ EventBridge rate(5 minutes)    │  default always-on
│   → Lambda PutRecord (py3.14)  │
└──────────────┬─────────────────┘
               │
┌──────────────┴─────────────────┐
│ amazon-kinesis-replay (JAR)    │  optional burst on the operator's machine
│   -streamArn  -speedup         │
└──────────────┬─────────────────┘
               │ PutRecord(s)
               ▼
┌────────────────────────────────┐
│ Kinesis Data Streams           │  On-Demand capacity mode (required)
│   kds-s3-demo-<suffix>-stream  │
└──────────────┬─────────────────┘
               │ CreateChannel — managed delivery
               │ buffers 300-900s, no read-throughput cost
               ▼
┌────────────────────────────────┐
│ S3 general purpose bucket      │  source format, GZIP, time-prefixed keys
│   kds-s3-demo-<suffix>-…       │
└──────────────┬─────────────────┘
               │
               ▼
        Visualization (reader's choice)
```

Diagram is intentionally ASCII during authoring; the Evidence_Pass replaces it.

### Resource set

| Resource                | Notes                                                             |
| ----------------------- | ----------------------------------------------------------------- |
| Kinesis stream          | On-Demand. Provisioned mode cannot host a delivery channel.       |
| S3 bucket               | Same Region as the stream. Also holds DLQ output by default.      |
| IAM service role        | Trusts `kinesis.amazonaws.com`, scoped by `aws:SourceArn` channel |
| Delivery channel        | `create-channel` with `--s3-destination-configuration`            |
| Producer role + Lambda  | `PutRecord` heartbeat; python3.14, 128 MB                         |
| EventBridge rule        | Default `rate(5 minutes)`; override with `PRODUCER_RATE`          |

No VPC, no Glue Schema Registry — the last of these is a streaming-tables concern,
not a general purpose S3 concern. No always-on EC2/Fargate.

## Site structure

```plaintext
src/content/docs/
  index.mdx                     # splash: story, architecture, time and cost
  prerequisites.mdx             # account, CLI, Lambda runtime, optional Java, Region
  cli/
    index.mdx                   # reading order + demo.sh cheat sheet
    setup/stream.mdx            # On-Demand stream
    setup/bucket.mdx            # destination bucket
    setup/iam-and-delivery.mdx  # role, trust, policy, create-channel, wait for ACTIVE
    produce.mdx                 # always-on heartbeat; optional replay after ACTIVE
    verify-s3.mdx               # objects, one record, CloudWatch metrics
    visualize.mdx               # optional branded HTML report
    teardown.mdx                # reverse order, confirmations
  reference/
    commands.mdx                # every command in one place
    costs-and-limits.mdx        # pricing links, quotas, constraints
    troubleshooting.mdx         # symptom, diagnosis, fix
    cleanup-checklist.mdx       # resource-by-resource sweep
```

Sidebar order lives in `astro.config.mjs`. Filenames are never numbered.

### Page template

1. `<Checklist>` — outcomes
2. `## Overview` — one paragraph
3. `## Steps` — AWS CLI first, `demo.sh` equivalent second
4. `## Verify`
5. `## References` — AWS documentation links

## Demo script

```bash
demo.sh up         # bucket, stream, role, channel; prints ARNs
demo.sh status     # stream status, channel state, object count (read-only)
demo.sh producer   # EventBridge → Lambda PutRecord heartbeat (after ACTIVE)
demo.sh replay     # optional high-volume JAR burst
demo.sh viz        # branded HTML report (.lab/viz/report.html) + console deep links
demo.sh down       # producer first, then reverse-order stack teardown
```

Design rules:

- Echo each AWS CLI command before running it. The script is a convenience, not an abstraction.
- `set -euo pipefail`; fail fast when Region or profile is unset.
- Every resource gets the lab prefix and `Project=kinesis-s3-delivery-walkthrough`.
- `down` refuses to touch a name lacking the prefix.

### Teardown order

Stop the producer first so puts cease, then delete the channel (an active channel keeps processing
and billing). Then bucket contents, bucket, stream, delivery role.

```text
producer (rule → Lambda → role)
  → delete-channel → (wait) → empty bucket → delete bucket
  → delete-stream → detach/delete policies → delete delivery role
```

## Timing model

| Phase                     | Expectation                                          |
| ------------------------- | ----------------------------------------------------- |
| Channel CREATING → ACTIVE | ~15 s observed in evidence; poll `describe-channel` |
| Producer to first S3 object | ~5 minutes with default `DataFreshnessInSeconds=300` (lab evidence) |
| Whole lab                 | target 15–20 minutes (measured in the Evidence_Pass)  |

Verification pages must frame the wait as expected behaviour, not a failure.

## Visualization

Presented as three tiers so the story survives whichever the reader picks:

| Tier | Option                          | Effort |
| ---- | ------------------------------- | ------ |
| A    | S3 console plus one record read | none   |
| B    | Query engine over the prefix    | small  |
| C    | Custom app or dashboard         | later  |

Lab completion is defined by tier A, so the walkthrough never blocks on tooling choice.

## Guard rails

| Mechanism                      | Enforces                                                    |
| ------------------------------ | ------------------------------------------------------------ |
| `aws-source-lock.md` steering  | Citations, verified facts, TBD discipline                    |
| `guard-aws-mutations` hook     | No accidental AWS mutations from shell tools                 |
| `cite-aws-claims` hook         | Re-check sources after each page edit                        |
| `aws-api` MCP disabled         | Agent cannot call AWS APIs unless deliberately enabled       |
| `lab-safety.md` steering       | Naming, tagging, teardown order, cost callouts               |
| `npm run validate`             | Placeholders, aside vocabulary, citations — see below        |

Steering states the intent; the validators make it a build failure. Anything a script can catch
should be a script, so review effort goes to whether the walkthrough is *correct* rather than
whether it is *formatted*.

| Script                   | Fails on                                                                  |
| ------------------------ | -------------------------------------------------------------------------- |
| `check-placeholders.mjs` | Account ids, ARNs, access keys, or non-example emails inside code blocks   |
| `check-asides.mjs`       | Aside types outside `tip`, `note`, `caution`, `danger`                     |
| `check-references.mjs`   | AWS links absent from the Source_Lock, missing References, dead AWS links  |

`check-references.mjs` closes the loop on Requirement 8: the Source_Lock stops being a document
people are asked to respect and becomes the allowlist the build reads. Citing a new AWS page
requires editing the steering file first, which is exactly the deliberate act that keeps invented
claims out. `SKIP_LINK_CHECK=1` skips only the HTTP pass, so the gate still works offline and in
the save-time hook.

All three run standalone on Node with no dependencies, so they work before `npm install` and
print `no content yet, skipping` until `src/content/docs/` exists. Unit tests live in `tests/`.

## Build phases

1. Kiro configuration and guard rails — done.
2. Astro Starlight scaffold, sidebar, stub pages.
3. `demo.sh` with echoed commands.
4. Page content, grounded in the Source_Lock.
5. Reference and troubleshooting pages.
6. Evidence_Pass — run, fix, capture, replace diagrams, resolve TBDs.
7. Publish and add the hub entry on guides.johna.kiwi.

## Non-goals

Terraform, CDK, or CloudFormation as the primary path; Managed Service for Apache Flink;
OpenSearch; always-on EC2/Fargate producers; streaming tables on Apache Iceberg; a bespoke
dashboard. (A scheduled Lambda heartbeat is in scope as the default cheap producer.)
