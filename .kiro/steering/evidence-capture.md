---
inclusion: manual
---

# Evidence capture

Reference this file (`#evidence-capture`) during the validation pass, after the walkthrough
content is complete.

## Order of work

1. Run the lab end to end from a clean account with `scripts/demo.sh`.
2. Fix whatever breaks, then note corrections in
   `.kiro/specs/kinesis-s3-delivery-walkthrough/tasks.md`.
3. Capture evidence.
4. Replace text diagrams with real diagrams.
5. Resolve every `TBD` in `.kiro/steering/aws-source-lock.md`.

## Shot list

| Page          | Evidence                                                            |
| ------------- | -------------------------------------------------------------------- |
| Overview      | draw.io architecture diagram exported to SVG (replaces the ASCII sketch) |
| Setup stream  | Text looks-like: `describe-stream-summary` with On-Demand `ACTIVE`   |
| IAM/delivery  | Text looks-like: `create-channel` `CREATING` → `describe-channel` `ACTIVE` |
| Produce        | Text looks-like: Lambda invoke `{"ok":true}`; schedule ENABLED; log REPORT |

| Verify S3     | Text looks-like: `aws s3 ls` time-prefixed keys; gzip heartbeat JSON; CW metrics (3 dims) |
| Visualize     | HTML report still + CloudWatch still under `src/assets/cli/`                           |

| Teardown      | Text looks-like: `demo.sh down` confirm + ResourceNotFoundException on describe       |


## Demo artifacts

Keep demo artifacts rebuildable rather than re-recorded:

```text
docs/
  kinesis-s3-delivery-architecture.drawio   # editable source, official AWS icons
  demo/
    README.md              # what each artifact is, and the rebuild commands
    video-slideshow.md     # beat table, smoke checklist
    captures/              # stills, plus the script that assembles them
      build-demo.py
```

Stills that appear in the site live under `src/assets/<section>/` (console UI and diagrams).
CLI evidence belongs in the page as redacted `frame="terminal"` looks-like text next to the step.
Stills that only feed the video stay under `docs/demo/captures/`.

## Capture rules

- Prefer a **Looks like** result fence (`text` or `json`) next to the step when the evidence is
  CLI output — keep it separate from the `frame="terminal"` command the reader copies. Do not
  render that output as a PNG unless a console UI or diagram is the point. Install tooling
  version checks follow the same rule.
- Redact account IDs, ARNs containing the account, and any bucket name that is not obviously
  disposable.
- Prefer terminal text over console screenshots where the text carries the information.
- Store images under `src/assets/<section>/`, lowercase and hyphenated — architecture diagrams and
  console UI stills are the usual cases, not CLI version output.
- Record the observed timings: `ACTIVE` to first object, and total lab duration. These replace
  the estimates in the content.

## Timing to measure

- Channel `CREATING` → `ACTIVE`
- First object in S3 after producer starts
- Whole lab, start to teardown
