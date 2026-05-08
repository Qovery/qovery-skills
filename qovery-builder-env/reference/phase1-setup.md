## Phase 1: Setup

### 1.1 Authenticate

Use the same authentication flow as all Qovery skills — see [auth.md](auth.md) for the full flow and security rules.

1. Check if `QOVERY_CLI_ACCESS_TOKEN` or `QOVERY_API_TOKEN` is set in the environment
2. If not, try `qovery auth token --print` — if the CLI is authenticated, this outputs a valid token (auto-refreshed). Use it **inline** in curl commands: `curl -s -H "Authorization: Bearer $(qovery auth token --print)" ...`
3. If the CLI is not authenticated, run `qovery auth` for interactive login, then use step 2.

### 1.2 Resolve Organization & Cluster

**Shortcut:** If the user provided a Qovery Console URL, extract the IDs using [console-url-detection.md](console-url-detection.md).

List organizations:
```bash
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/organization" | jq '.results[] | {id, name}'
```

- If 1 organization: confirm and move on.
- If multiple: present the list and ask which one to use.

List clusters:
```bash
curl -s -H "Authorization: Bearer $(qovery auth token --print)" \
  "https://api.qovery.com/organization/{orgId}/cluster" | jq '.results[] | {id, name, cloud_provider, region, status}'
```

- If 1 cluster: confirm.
- If multiple: ask. Recommend a non-production cluster for builder environments.
- Verify cluster status is `DEPLOYED` or `READY`.
- If no cluster exists: tell the user to run `qovery-onboard` first.

### 1.3 Anthropic API Key (optional)

Ask:
> "Do you have an Anthropic API key for the AI coding tools (Claude Code, OpenCode)?
> Paste it here, or press Enter to skip — you can add it later in the Qovery Console."

- If provided: store it — it will be set as a project-level secret in Phase 2.
- If skipped: set `ANTHROPIC_API_KEY=sk-placeholder-add-your-key-here` as the project secret. Tell the user:
  > "I've set a placeholder. To enable AI tools later, update the ANTHROPIC_API_KEY secret in the Qovery Console under the builder-workspaces project."

That's it for Phase 1. No more questions. Proceed to Phase 2.
