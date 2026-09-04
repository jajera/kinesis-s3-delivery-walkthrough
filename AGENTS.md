# Agent Context

Guided AWS CLI walkthrough for **Amazon Kinesis Data Streams delivery to general purpose Amazon S3
buckets**, published as an Astro Starlight site.

## Read these first

Kiro loads `.kiro/steering/` automatically; other agents should read them directly.

| File                                  | When it applies              | What it covers                                   |
| ------------------------------------- | ---------------------------- | ------------------------------------------------ |
| `.kiro/steering/product.md`           | always                       | Story, scope, non-goals, visual bias             |
| `.kiro/steering/tech.md`              | always                       | Stack, commands, lab tooling                     |
| `.kiro/steering/structure.md`         | always                       | Layout, page rules, naming                       |
| `.kiro/steering/aws-source-lock.md`   | always                       | **Citation rules, verified facts, open TBDs**    |
| `.kiro/steering/docs-pattern.md`      | `src/content/docs/**`        | Page template, MDX indentation traps             |
| `.kiro/steering/editor-tooling.md`    | `src/content/docs/**`        | **What the automated gates reject**              |
| `.kiro/steering/markdown-tables.md`   | `src/content/docs/**`        | HTML tables when components are imported         |
| `.kiro/steering/glossary.md`          | `src/data/glossary*`         | Alphabetical order, term list                    |
| `.kiro/steering/lab-safety.md`        | `scripts/**`, install/prereq/cli pages | Profile `sandbox`, Region, CLI pins, teardown |
| `.kiro/steering/evidence-capture.md`  | manual (`#evidence-capture`) | Screenshot and diagram pass                      |

Lab CLI pin: AWS CLI **≥ 2.36.35**, demo **2.36.38**; profile **`sandbox`**; Region **`ap-southeast-2`**.
Start readers at **Install tooling**.

## Non-negotiables

1. **Cite AWS behaviour.** This capability shipped in August 2026. Do not answer from recall — use
   the `aws-docs` MCP server and the source list in `aws-source-lock.md`. Unsourced claims do not
   ship.
2. **Never run AWS mutations.** Author the command; the operator runs it. The
   `guard-aws-mutations` hook blocks mutating AWS CLI and IaC commands from shell tools unless
   `KDS_LAB_ALLOW_AWS=1`.
3. **Mark unverified work.** Nothing is "verified" until the evidence pass runs it in an account.
4. **Prefer visuals.** Diagrams, tables, and short numbered steps over paragraphs. Text diagrams
   now; real diagrams during the evidence pass.

## Facts that trip people up

- The API resource is a **channel** (`create-channel`); the console says *S3 general purpose
  delivery*.
- **On-Demand capacity mode only.** Provisioned streams cannot host a delivery.
- **No backfill** — only records written after the channel is `ACTIVE` are delivered.
- Freshness window is **300–900 seconds**, so objects take minutes to appear. CloudWatch
  `get-metric-statistics` for `DeliveryToS3.*` needs **all three** dimensions
  (`StreamName`, `ChannelName`, `ChannelId`).
- The default producer is an EventBridge → Lambda heartbeat (`demo.sh producer`, **python3.14**);
  optional `amazon-kinesis-replay` takes **`-streamArn`**, not `-streamName`.

The complete list, with sources, is in `.kiro/steering/aws-source-lock.md`.

## Plan of record

`.kiro/specs/kinesis-s3-delivery-walkthrough/` holds `requirements.md`, `design.md`, and
`tasks.md`. Work the phases in order; the evidence pass is deliberately last.

## Validation

Three gates, each dependency-free Node, so they run before `npm install`:

```bash
node scripts/check-placeholders.mjs   # no real account identifiers in code blocks
node scripts/check-asides.mjs         # tip / note / caution / danger only
node scripts/check-references.mjs     # AWS links must be in the source lock and must resolve
```

After Phase 1 the same set runs as `npm run validate`, and `npm run build` is the CI gate. Use
`SKIP_LINK_CHECK=1` to skip HTTP resolution offline.

The source lock is an allowlist, not a suggestion: citing a new AWS page means editing
`.kiro/steering/aws-source-lock.md` first, then the page.

## Diagrams and icons

- AWS service icons — <https://jajera.github.io/aws-icons/>
- Generic architecture icons — <https://jajera.github.io/arch-icons/>
- Mermaid scratchpad — <https://jajera.github.io/mermaid-diagram-editor/>

draw.io plus official AWS icons for the architecture view, Mermaid for flow and sequence. Details
in `.kiro/steering/editor-tooling.md`.
