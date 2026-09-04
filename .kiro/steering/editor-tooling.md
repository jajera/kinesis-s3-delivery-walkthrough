---
inclusion: fileMatch
fileMatchPattern: "src/content/docs/**"
---

# Editor tooling

What the automated gates in `npm run validate` expect. Every rule here is enforced by a script,
so treat it as a build error rather than a style preference.

| Gate                          | Script                        | Rejects                                        |
| ----------------------------- | ----------------------------- | ---------------------------------------------- |
| `check-placeholders`          | `scripts/check-placeholders.mjs` | Real account identifiers inside code blocks |
| `check-asides`                | `scripts/check-asides.mjs`    | Callout types outside the allowed four         |
| `check-references`            | `scripts/check-references.mjs` | Uncited AWS links and missing References       |

## Placeholders

Inside fenced code blocks, use these and nothing else:

| Kind       | Use                                                                    |
| ---------- | ---------------------------------------------------------------------- |
| Account    | `ACCOUNT_ID`, or `123456789012` when the shape has to be literal       |
| Region     | `REGION`, or the documented lab default `ap-southeast-2`               |
| ARNs       | Built from an allowed account, resource names suffixed `EXAMPLE`       |
| Buckets    | `kds-lab-EXAMPLE` style — never a name someone could actually own      |
| Email      | `you@example.com`                                                      |
| Credentials| `...` or a `$VARIABLE` reference. Never a key-shaped string            |

A line containing `ACCOUNT_ID`, `REGION`, `EXAMPLE`, `your-`, or `my-` is skipped by the scanner,
so mixed lines are fine. Prose outside code blocks is not scanned.

## Asides

Four types, each with a job:

- `:::tip` — a shortcut or a better way
- `:::note` — context worth knowing, and `Evidence TODO` markers while authoring
- `:::caution` — easy to get wrong, or a wait the reader should not read as a failure
- `:::danger` — cost, data loss, or credential exposure

Do not use `:::warning` or `:::info`.

## Diagrams

Two formats, chosen by what the diagram is for:

| Purpose                            | Format                                                      |
| ---------------------------------- | ----------------------------------------------------------- |
| Architecture, one per page maximum | draw.io using official AWS icons, exported to SVG            |
| Flow, sequence, state, timing      | Mermaid `graph TD` in the page                               |

Icon and diagram sources:

- AWS service icons — <https://jajera.github.io/aws-icons/>
- Generic architecture icons — <https://jajera.github.io/arch-icons/>
- Mermaid scratchpad — <https://jajera.github.io/mermaid-diagram-editor/>

Keep the `.drawio` source next to the export under `docs/` so the diagram stays editable. Include
a legend whenever a line style carries meaning: solid for AWS-internal, dashed for anything
crossing the AWS boundary.

During authoring, the ASCII sketch stands in for the real diagram. Mark it with an
`Evidence TODO` aside so the evidence pass finds it.

## Links

- AWS links must already exist in `.kiro/steering/aws-source-lock.md`. Adding a source is an
  edit to that file first, the page second.
- Every published page under `cli/` or `reference/` needs a `## References` section.
- Internal links are root-relative (`/cli/produce/`). The site uses a johna.kiwi custom domain
  with `base: "/"`.
- Pin GitHub links to `main`.

## Running the gates

```bash
npm run validate                  # all three
SKIP_LINK_CHECK=1 npm run validate  # offline; skips HTTP resolution only
```
