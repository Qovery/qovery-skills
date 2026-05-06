## MCP Server Integration

This skill is designed to work with the **Qovery MCP Server** as the primary diagnostic interface. The MCP Server provides faster, more structured responses than raw CLI/API calls and is optimized for troubleshooting.

**If the Qovery MCP Server is available** (configured in the agent's MCP settings), prefer it for all queries. Use natural language prompts — the MCP Server understands context and returns structured, actionable data.

**If the MCP Server is NOT available**, fall back to the Qovery CLI and REST API. Every diagnostic step in this skill lists all three options: MCP query, CLI command, and API endpoint.

### How to check if MCP Server is available

The MCP Server is available if the agent has it configured at `https://mcp.qovery.com/mcp`. Check by attempting a simple query like "Show me all environments." If it works, prefer MCP for all subsequent queries.

### MCP Server Setup (if not configured)

If the user wants to enable MCP for richer troubleshooting, guide them:

```bash
# Claude Code (OAuth — easiest)
claude mcp add --transport http qovery https://mcp.qovery.com/mcp --callback-port 4242

# Claude Code (API Token)
claude mcp add --transport http qovery https://mcp.qovery.com/mcp --header 'Authorization: Token qov_xxxx'

# OpenAI Codex
# In .codex/config.toml:
# [mcp_servers.qovery]
# url = "https://mcp.qovery.com/mcp"
# http_headers = { "Authorization" = "Token qov_xxxx" }
```

---

