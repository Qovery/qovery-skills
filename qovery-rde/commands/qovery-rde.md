---
description: Set up Remote Development Environments (RDEs) on Qovery for your team
---

Set up Remote Development Environments (RDEs) on Qovery for team members (developers, non-tech teams, or mixed).

If arguments are provided, use them as context:
- `$ARGUMENTS` — team name (e.g., "sales"), number of builders, builder experience tier (visual/vscode/terminal), or Qovery Console URL

Follow the qovery-rde skill to:
1. Check CLI installed, authenticate, resolve org/cluster, optionally provide Anthropic API key
2. Generate Dockerfile + entrypoint.sh, create project + workspace via API, register blueprint, deploy, validate, stop
3. Provision RDEs with `qovery rde create` (one command per builder), list, share URLs
4. Configure cost controls and lifecycle management
