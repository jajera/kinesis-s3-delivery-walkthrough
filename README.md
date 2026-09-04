# kinesis-s3-delivery-walkthrough

Guided CLI walkthrough for Kinesis Data Streams S3 delivery with always-on producer, optional taxi replay, visualization, and teardown

Amazon Kinesis Data Streams can now deliver records straight to a general purpose Amazon S3
bucket — no Firehose, no Lambda consumer, no self-managed pipeline. This repository is the
walkthrough: stand up a stream and a delivery channel, feed it with a cheap scheduled producer
(optional NYC taxi replay burst), watch objects land in S3, then tear it all down.

## Status

Phases 0–5 are done. A lab run in `ap-southeast-2` verified setup → heartbeat producer → S3 objects →
CloudWatch `DeliveryToS3.*` (all three dimensions) → HTML report → clean teardown (task 6.8).
Remaining Phase 6/7 work: architecture diagram, demo assembly, Source_Lock TBDs, johna.kiwi DNS
cutover, and the hub entry. Live site (project Pages base path):
https://jajera.github.io/kinesis-s3-delivery-walkthrough/. See
[`.kiro/specs/kinesis-s3-delivery-walkthrough/tasks.md`](.kiro/specs/kinesis-s3-delivery-walkthrough/tasks.md).

```bash
# Prefer the pinned user-local AWS CLI (see .envrc)
export PATH="$HOME/.local/bin:$PATH"

npm install
npm run dev       # local preview
npm run validate  # placeholder, aside, source-lock gates
npm run build     # og image + validate + static site
```

Lab orchestration (operator only — `AWS_PROFILE=sandbox`, `AWS_REGION=ap-southeast-2`, and for
mutations `KDS_LAB_ALLOW_AWS=1`):

```bash
./scripts/demo.sh up|status|producer|replay|viz|down
```

AWS behaviour claims are sourced from
[`.kiro/steering/aws-source-lock.md`](.kiro/steering/aws-source-lock.md).

## Contributing

Read [`AGENTS.md`](AGENTS.md) first.

Authoring never creates AWS resources. A Kiro `PreToolUse` hook blocks mutating AWS CLI and IaC
commands unless `KDS_LAB_ALLOW_AWS=1` is set deliberately for a lab run.

## License

[MIT](LICENSE)
