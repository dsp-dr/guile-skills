# Domain naming (proposed, not provisioned)

No Cloudflare account or API key is connected yet, so nothing below has
been created — this is a naming proposal for when that credential exists,
for the future MCP server this plugin's `.mcp.json` would reference.

Standard pattern: environment as the leftmost label, production bare.

| Environment | Hostname |
|---|---|
| production | `guile-skills.changeflow.us` |
| staging | `staging.guile-skills.changeflow.us` |
| PR preview (optional) | `pr-<n>.guile-skills.changeflow.us` |

If `changeflow.us` isn't delegated for wildcard/multi-level subdomains in
Cloudflare (only flat one-label subdomains configured), the fallback is the
flattened form the naming should degrade to:

| Environment | Hostname (flattened) |
|---|---|
| production | `guile-skills.changeflow.us` |
| staging | `staging-guile-skills.changeflow.us` |

Both point at the same target either way — a Cloudflare Worker (or a tunnel
to wherever the MCP server actually runs) — via a CNAME/Worker route, not an
A record. Next steps once the Cloudflare API key exists: create the DNS
record(s) above, then reference the resulting URL in this plugin's
`.mcp.json` (`{"mcpServers": {"guile-skills": {"type": "http", "url": "https://guile-skills.changeflow.us/mcp"}}}`).
