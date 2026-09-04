# Hooks

Kiro v1 hooks ([reference](https://kiro.dev/docs/hooks/)). Each file declares `version: "v1"` and
a `hooks` array with a PascalCase `trigger`.

Lab defaults these hooks protect (see `.kiro/steering/lab-safety.md`):

| Setting | Value |
| ------- | ----- |
| Profile | `sandbox` |
| Region | `ap-southeast-2` |
| AWS CLI | minimum **2.36.35**, demo **2.36.38** |
| Default producer | EventBridge → Lambda **python3.14** (`demo.sh producer`) |

| File                          | Trigger       | Blocks | Default  | Purpose                                                          |
| ----------------------------- | ------------- | ------ | -------- | ----------------------------------------------------------------- |
| `guard-aws-mutations.json`    | `PreToolUse`  | yes    | enabled  | Refuses mutating AWS CLI and IaC commands from shell tools.       |
| `cite-aws-claims.json`        | `PostFileSave`| no     | enabled  | Reminds the agent to ground AWS claims after editing a page.      |
| `format-markdown-tables.json` | `PostFileSave`| no     | enabled  | Repairs broken GFM tables in changed Markdown and MDX.            |
| `docs-check.json`             | `PostFileSave`| no     | enabled  | Runs the placeholder, aside, and source-lock validators.          |

## guard-aws-mutations

The blocking guard rail. `PreToolUse` hooks can stop a tool call by exiting with code 2, and the
stderr text is returned to the agent.

- Scoped by `matcher` to shell-style tool names, so writing a documentation page that *contains*
  `aws kinesis create-channel` is never blocked — only running it is.
- Read-only calls pass: `describe-*`, `list-*`, `get-*`, `s3 ls`, `sts get-caller-identity`.
- Also blocks `terraform apply|destroy`, `cdk deploy|destroy`, `sam deploy`, and CloudFormation
  stack operations, because this repository ships no infrastructure as code.
- Strings longer than 2000 characters are ignored as file content rather than command lines.

Opt in for a deliberate lab run:

```bash
export KDS_LAB_ALLOW_AWS=1
```

Test it without Kiro:

```bash
echo '{"command":"aws kinesis create-stream --stream-name x"}' | python3 .kiro/hooks/guard-aws-mutations.py; echo "exit=$?"   # 2
echo '{"command":"aws kinesis describe-stream --stream-name x"}' | python3 .kiro/hooks/guard-aws-mutations.py; echo "exit=$?" # 0
```

## docs-check

Runs `scripts/check-placeholders.mjs`, `scripts/check-asides.mjs`, and
`scripts/check-references.mjs` — the same gates as `npm run validate`. They are dependency-free
Node scripts, so the hook works before `npm install` and prints `no content yet, skipping` until
`src/content/docs/` exists.

Network link resolution is skipped here (`SKIP_LINK_CHECK=1`) to keep saves fast; CI resolves
every AWS link. The hook never fails the save — `PostFileSave` cannot block anyway.

See `.kiro/steering/editor-tooling.md` for what each gate enforces.

## format-markdown-tables

Uses `--dirty` (git-modified and untracked Markdown) because the command receives session JSON on
STDIN rather than a bare file path.
