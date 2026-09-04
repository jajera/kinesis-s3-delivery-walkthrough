# Implementation Plan

Phases 1 to 5 author the complete walkthrough. Phase 6 runs it and captures evidence. Do not mark
any AWS behaviour "verified" before Phase 6.

## Phase 0 — Agent configuration

- [x] 0.1 Add `.kiro/settings/mcp.json` with `aws-docs` enabled and `aws-api` disabled
- [x] 0.2 Add always-on steering: `product`, `tech`, `structure`, `aws-source-lock`
- [x] 0.3 Add conditional steering: `docs-pattern`, `markdown-tables`, `glossary`, `lab-safety`,
      `editor-tooling`
- [x] 0.4 Add manual steering: `evidence-capture`
- [x] 0.5 Add blocking `guard-aws-mutations` hook and verify it blocks and allows correctly
- [x] 0.6 Add `cite-aws-claims`, `format-markdown-tables`, and `docs-check` hooks
- [x] 0.7 Write the spec: requirements, design, tasks
- [x] 0.8 Add root `AGENTS.md` pointing at the steering files
- [x] 0.9 Add the quality gates — `check-placeholders`, `check-asides`, `check-references` — with
      vitest coverage, and verify each one catches its own failure case
- [x] 0.10 Add CI (`deploy`, `markdown-lint`, `commitmsg-conform`, `auto-merge`) and Dependabot
  - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 9.7, 10.1_

## Phase 1 — Site scaffold

- [x] 1.1 Scaffold Astro + Starlight; pin Node 22 in `.nvmrc`
- [x] 1.2 Configure `site` (`*.johna.kiwi`), `base: '/'`, theme, and Open Graph meta
- [x] 1.3 Add `astro-mermaid` and `starlight-image-zoom`
- [x] 1.4 Add `Checklist` and `Tooltip` components and `src/data/glossary.ts`
- [x] 1.5 Wire `npm run validate` to the three gates and `npm run test` to vitest
- [x] 1.6 Add `scripts/generate-og-image.ts` and run it from `npm run build`
- [x] 1.7 Confirm a clean `npm run build` and that `deploy.yml` passes
  - _Requirements: 1.1, 1.2, 9.6_

## Phase 2 — Page stubs

- [x] 2.1 Create every page from the design layout with `draft: true` and a References heading
- [x] 2.2 Add evidence markers where a screenshot or diagram belongs
- [x] 2.3 Seed the glossary: `channel`, `data-freshness`, `dlq`, `kds`, `on-demand-standard`,
      `on-demand-advantage`, `output-key-template`, `service-execution-role`, `streaming-tables`
  - _Requirements: 8.1, 10.2, 10.3_

## Phase 3 — Demo script

- [x] 3.1 `demo.sh` skeleton: usage, `set -euo pipefail`, Region and profile guards, name prefix
- [x] 3.2 `up` — bucket, On-Demand stream, service role, `create-channel`, poll to `ACTIVE`
- [x] 3.3 `status` — read-only stream, channel, and object count
- [x] 3.4 `replay` — invoke the replay JAR with `-streamArn` and `-speedup`
- [x] 3.4b `producer` — EventBridge → Lambda PutRecord heartbeat (Option A, 2026-09-03)
- [x] 3.5 `viz` — build branded HTML report (`.lab/viz/report.html`) and open it
- [x] 3.6 `down` — confirmation, reverse order, prefix check, empty bucket before delete
- [x] 3.7 `bash -n` clean; every AWS command echoed to stderr before it runs
  - _Requirements: 1.3, 7.2, 7.3, 7.4, 7.6_

## Phase 4 — Content

- [x] 4.1 `index.mdx` — story, architecture, time and cost expectations, verification date
- [x] 4.2 `prerequisites.mdx` — account, CLI version, Java, Region, On-Demand requirement
- [x] 4.3 `setup/stream.mdx` — On-Demand stream, tags, prefix
- [x] 4.4 `setup/bucket.mdx` — same-Region bucket, default DLQ behaviour
- [x] 4.5 `setup/iam-and-delivery.mdx` — trust policy, S3 permissions, caller permissions,
      `create-channel`, `describe-channel` until `ACTIVE`
- [x] 4.6 `produce.mdx` — always-on heartbeat default; optional replay burst after `ACTIVE`
- [x] 4.7 `verify-s3.mdx` — freshness wait, `aws s3 ls`, read a record, `DeliveryToS3.*` metrics
- [x] 4.8 `visualize.mdx` — optional HTML report; lab completion still defined at Verify in S3
- [x] 4.9 `teardown.mdx` — producer first, then channel, bucket, stream, roles
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 4.1, 4.2, 4.3, 4.4, 4.5, 5.1, 5.2, 5.3, 5.4, 6.1, 6.2, 6.3, 7.1, 7.2_

## Phase 5 — Reference

- [x] 5.1 `reference/commands.mdx` — every command in order
- [x] 5.2 `reference/costs-and-limits.mdx` — pricing links, quotas, immutable fields, constraints
- [x] 5.3 `reference/troubleshooting.mdx` — symptom, diagnosis, fix for the known failure modes:
      provisioned-mode stream, missing `iam:PassRole`, prefix mismatch between IAM resource and
      output key template, compression without an extension placeholder, expecting backfill,
      checking S3 before the freshness window elapses
- [x] 5.4 `reference/cleanup-checklist.mdx` — resource-by-resource sweep
- [x] 5.5 Confirm every page has a populated References section
  - _Requirements: 7.5, 8.1, 8.2_

## Phase 6 — Evidence pass

Reference `#evidence-capture` before starting. Set `KDS_LAB_ALLOW_AWS=1` deliberately, and unset
it afterwards.

- [ ] 6.1 Run the lab end to end in a clean account; record every deviation
- [ ] 6.2 Resolve the Source_Lock TBDs: CloudShell versus local JDK for the replay JAR,
      observed `ACTIVE`-to-first-object time
      (create-stream ODS/ODA resolved 2026-09-03: CLI uses `StreamMode=ON_DEMAND` only;
      Standard vs Advantage is account-level — see FAQs)
- [ ] 6.3 Capture the shot list from `#evidence-capture`; redact account identifiers
      (setup stream + bucket + IAM/delivery: text looks-like next to steps)
- [ ] 6.4 Build the architecture diagram in draw.io using
      [`jajera/aws-icons`](https://jajera.github.io/aws-icons/), export SVG, and replace the ASCII
      sketch; convert the remaining flow sketches to Mermaid
- [ ] 6.5 Assemble `docs/demo/` — capture stills, `build-demo.py`, and the beat table
- [ ] 6.6 Update timings and mark verified behaviours; set the verification date
- [x] 6.7 Remove every remaining `draft: true` and add the slugs to the sidebar
      (done early so navigation works while authoring)
- [x] 6.8 Confirm teardown left nothing behind
  - _Requirements: 8.2, 8.3, 10.1, 10.2, 10.3, 10.4_

## Phase 7 — Publish

- [ ] 7.1 Deploy to GitHub Pages and check the base path and social preview
- [ ] 7.2 Add the entry to `jajera/guides` with type `walkthrough`
  - _Requirements: 8.2_
