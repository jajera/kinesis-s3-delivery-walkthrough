---
inclusion: always
---

# Structure

## Target layout

```plaintext
.github/
  workflows/             # actionsforge reusable workflows only
  dependabot.yml
.kiro/
  settings/mcp.json      # MCP servers (aws-docs enabled, aws-api disabled)
  steering/              # these files
  hooks/                 # guard rails and save-time checks
  specs/kinesis-s3-delivery-walkthrough/
docs/
  kinesis-s3-delivery-architecture.drawio
  demo/                  # capture scripts and video source, added in the evidence pass
scripts/
  demo.sh                # up | status | producer | replay | viz | down
  viz/                   # build_report.py → .lab/viz/report.html
  check-placeholders.mjs # quality gates, run by npm run validate
  check-asides.mjs
  check-references.mjs
tests/                   # vitest over the validators
src/content/docs/
  index.mdx              # overview + architecture
  install-tooling.mdx    # AWS CLI / jq / optional Java+Maven for replay — before the walkthrough
  prerequisites.mdx
  cli/
    index.mdx            # reading order + demo.sh cheat sheet
    setup/stream.mdx
    setup/bucket.mdx
    setup/iam-and-delivery.mdx
    produce.mdx          # always-on heartbeat; optional replay burst
    verify-s3.mdx
    visualize.mdx        # branded HTML delivery report
    teardown.mdx
  reference/
    commands.mdx
    costs-and-limits.mdx
    troubleshooting.mdx
    cleanup-checklist.mdx
src/data/glossary.ts
astro.config.mjs
```

## Page rules

- One job per page. Short lede, then the commands.
- Every page that makes an AWS behavioural claim ends with a `## References` section linking the
  AWS documentation page that states it.
- Reading order is setup → produce → verify → visualize → teardown. Setup pages are ordered
  stream, bucket, IAM + delivery, because the channel needs the first three to exist.
- Internal links are root-relative (`/cli/produce/`). The site ships on
  `kinesis-s3-delivery-walkthrough.johna.kiwi` with `base: "/"`.

## Naming in the lab

- Resource name prefix comes from one variable so every created resource is greppable.
- Tag everything `Project=kinesis-s3-delivery-walkthrough`.
- See `.kiro/steering/lab-safety.md` for the exact conventions.
