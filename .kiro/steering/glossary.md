---
inclusion: fileMatch
fileMatchPattern: "src/data/glossary*"
---

# Glossary conventions

- Lives in `src/data/glossary.ts` as `Record<string, GlossaryEntry>`.
  `GlossaryEntry` is a string, or `{ definition, url?, urlLabel? }`.
- Keys are lowercase kebab-case, sorted **alphabetically ascending**. Re-sort after adding.
- Definitions are one or two sentences, starting with the expanded form.
- Use walkthrough-specific context where it helps (for example, that a *channel* is what the
  console labels *S3 general purpose delivery*).

## Terms this walkthrough needs

`channel`, `data-freshness`, `dlq`, `kds`, `on-demand-advantage`, `on-demand-standard`,
`output-key-template`, `service-execution-role`, `shard`, `streaming-tables`.

## Usage

```mdx
import Tooltip from "@/components/Tooltip.astro";

<Tooltip term="channel" />
<Tooltip term="kds" label="Kinesis Data Streams" />
```

Add a term when it appears on more than one page, or when it has a meaning here that a first-time
reader would not guess. Do not inline definitions in page bodies.
