---
inclusion: fileMatch
fileMatchPattern: "src/content/docs/**"
---

# Documentation page pattern

## Frontmatter

```mdx
---
title: <Page Title>
description: <One sentence describing what this page achieves.>
draft: true
sidebar:
  label: <Short sidebar label>
---
```

`draft: true` only while a page is empty scaffolding. Once content is present, leave it published
so the sidebar and Get Started links work. Unverified AWS behaviour still uses Evidence TODO
markers — do not call it verified until the evidence pass.

## Page order

1. `<Checklist>` — outcomes of the page, not sub-steps
2. `## Overview` — one paragraph, glossary terms via `<Tooltip>`
3. `## Steps` — `<Steps>` with the commands
4. `## Verify` — how the reader confirms it worked
5. `## References` — AWS documentation links backing every claim on the page

## Imports

```mdx
import { Steps, Aside, Tabs, TabItem, Badge } from "@astrojs/starlight/components";
import Checklist from "@/components/Checklist.astro";
import Tooltip from "@/components/Tooltip.astro";
```

Import only what the page uses.

## MDX indentation inside `<Steps>`

The most common build failure in these repos. Block-level JSX inside a step must be indented as
list-item content:

| Level                                     | Indent    |
| ----------------------------------------- | --------- |
| Step body (code, text, `<Tabs>`)          | 3 spaces  |
| `<TabItem>` inside `<Tabs>`               | 5 spaces  |
| Content inside `<TabItem>`                | 6 spaces  |

Keep each `<Steps>` block under ten items so Markdown does not start a second `<ol>`.

## Code blocks

- `frame="terminal"` for shell **commands** the reader runs (no mixed stdout in the same fence)
- Put verified output in a following **Looks like** block as `text` or `json` — command and
  result stay separate
- `title="filename.ext"` when showing file contents
- Show the AWS CLI command, then the `demo.sh` equivalent — never only the wrapper

## Checklist ids

Unique site-wide, pattern `<section>-<page>` (for example `setup-stream`, `cli-verify-s3`).

## Links

Internal links are root-relative: `/cli/produce/`.

## Evidence markers

Prefer a redacted **Looks like** result block (`text` or `json`) **next to the step**, after the
command fence — do not mix stdout into the command block. Use an image only for console UI or
diagrams. Where a screenshot or real diagram still belongs later, leave a visible marker:

```mdx
<Aside type="note" title="Evidence TODO">
  Screenshot: Kinesis console showing the channel in ACTIVE state.
</Aside>
```
