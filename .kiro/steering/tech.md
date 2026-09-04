---
inclusion: always
---

# Tech

## Documentation site

Astro + `@astrojs/starlight`.

- Node 22 (pin in `.nvmrc`)
- MDX content under `src/content/docs/`
- Sidebar defined in `astro.config.mjs` — never encode order in filenames
- `astro-mermaid` for flow and sequence diagrams
- `starlight-image-zoom` so screenshots stay readable inline
- GitHub Pages deploy via the `actionsforge` reusable workflows

## Commands

```bash
npm install
npm run dev       # local preview
npm run validate  # placeholder, aside, and source-lock gates
npm run test      # vitest over the validator scripts
npm run build     # og image + validate + astro build; the CI gate
```

The validators run standalone on Node with no dependencies, so they work before `npm install`:

```bash
node scripts/check-placeholders.mjs
node scripts/check-asides.mjs
SKIP_LINK_CHECK=1 node scripts/check-references.mjs
```

They print `no content yet, skipping` until `src/content/docs/` exists. Do not cite the npm
scripts in reader-facing content until the site is scaffolded.

## CI

| Workflow                | Runs                                                        |
| ----------------------- | ----------------------------------------------------------- |
| `deploy.yml`            | `validate` + `test` + Astro build, deploys Pages from `main` |
| `markdown-lint.yml`     | Markdown lint on every PR                                   |
| `commitmsg-conform.yml` | Conventional commit messages                                |
| `auto-merge.yml`        | Dependabot auto-merge once checks pass                      |

All four call `actionsforge/actions` reusable workflows. Do not inline build steps.

## Lab tooling

| Piece         | Choice                                                                                          |
| ------------- | ----------------------------------------------------------------------------------------------- |
| Orchestration | `scripts/demo.sh` wrapping the AWS CLI                                                          |
| Producer (default) | EventBridge → Lambda `PutRecord` heartbeat (`demo.sh producer`) |
| Producer (optional burst) | [`aws-samples/amazon-kinesis-replay`](https://github.com/aws-samples/amazon-kinesis-replay) JAR |
| Dataset       | [NYC TLC trip records](https://registry.opendata.aws/nyc-tlc-trip-records-pds/) (default)       |
| Visualization | Branded HTML report (`scripts/viz/build_report.py`, `demo.sh viz`)                      |
| Verification  | `aws s3 ls`, `aws kinesis describe-channel`, CloudWatch `DeliveryToS3.*`                        |

`demo.sh` must echo the real AWS CLI command before running it. The script is a convenience, not
an abstraction — readers should be able to copy any single command out of it.

## Version pinning

| Tool | Minimum | Demo pin (verified 2026-09-03) |
| ---- | ------- | ------------------------------ |
| AWS CLI v2 | **2.36.35** (`create-channel` first ships here) | **2.36.38** at `~/.local/bin/aws` |
| Lambda runtime (heartbeat) | **python3.14** | **python3.14**, 128 MB |
| Java (optional replay JAR) | 11 | **21** OpenJDK (17/21 LTS OK) |
| Maven (optional replay JAR) | 3.8+ | **3.9.6** |
| jq | 1.6+ | **1.7.1** |
| zip | any | system `zip` for Lambda package |
| python3 (viz report) | 3.10+ | **3.13** / **3.14** (stdlib only; no pip) |

Document these on the Install tooling page with redacted `frame="terminal"` looks-like blocks next
to each confirm step. Do not claim a minimum below 2.36.35. Load `.envrc` (or export
`PATH="$HOME/.local/bin:$PATH"`) so the pin wins over an older system CLI.
