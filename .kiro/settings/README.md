# MCP servers

Workspace MCP configuration lives in `mcp.json`. Kiro merges it with `~/.kiro/settings/mcp.json`,
workspace taking precedence ([Kiro MCP configuration](https://kiro.dev/docs/mcp/configuration/)).

| Server     | Package                                     | Default  | Why                                                                             |
| ---------- | ------------------------------------------- | -------- | ------------------------------------------------------------------------------- |
| `aws-docs` | `awslabs.aws-documentation-mcp-server`      | enabled  | Grounding. Every AWS claim in this repo must trace to a docs page.               |
| `aws-api`  | `awslabs.aws-api-mcp-server`                | disabled | Executes AWS CLI calls. Enable deliberately, only for the evidence pass.         |

`uvx` is required on PATH. Both packages are published on PyPI.

## Lab defaults (keep in sync)

These match `.kiro/steering/lab-safety.md` and the Install tooling page:

| Setting | Value |
| ------- | ----- |
| Profile | `sandbox` (`AWS_PROFILE`) |
| Region | `ap-southeast-2` (`AWS_REGION`) |
| AWS CLI minimum | **2.36.35** (`create-channel`) |
| AWS CLI demo pin | **2.36.38** |
| Default producer | EventBridge → Lambda **python3.14** (`demo.sh producer`) |

`mcp.json` pre-seeds `AWS_PROFILE` / `AWS_REGION` on the disabled `aws-api` server so enabling it
does not silently target the wrong account.

## Enabling `aws-api`

Leave it disabled while authoring. It can create billable AWS resources.

Before enabling for the evidence pass:

1. Confirm `aws --version` is ≥ 2.36.35 (prefer 2.36.38) — see Install tooling.
2. Confirm `AWS_PROFILE=sandbox` and `AWS_REGION=ap-southeast-2`.
3. Set `"disabled": false` in `mcp.json`, run the lab, then set it back to `true`.
4. Prefer `scripts/demo.sh` with `KDS_LAB_ALLOW_AWS=1` over free-form MCP mutations.

The `guard-aws-mutations` hook still applies to shell tools when this server is enabled.
