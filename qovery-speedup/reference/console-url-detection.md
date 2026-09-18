# Qovery Console URL Detection

When the user provides a Qovery Console URL (from `console.qovery.com` or
`new-console.qovery.com`), extract the resource IDs directly from the URL path.
This saves significant back-and-forth — no need to ask which organization,
project, environment, or service the user means.

## Generating Console links

Never invent a shortened Console route. Resource-scoped routes require their
parent IDs, including organization settings pages. Resolve every required ID
from a user-provided Console URL or the API before presenting a deep link. If a
required ID is unknown, link only to <https://console.qovery.com> and describe
the navigation path; do not emit a guessed URL or a URL containing a
placeholder.

Canonical routes:

```text
Organization Git access  /organization/{orgId}/settings/git-repository-access
Clusters list            /organization/{orgId}/clusters
Cluster                  /organization/{orgId}/cluster/{clusterId}
Project                  /organization/{orgId}/project/{projectId}
Environment              /organization/{orgId}/project/{projectId}/environment/{envId}
Service                  /organization/{orgId}/project/{projectId}/environment/{envId}/service/{serviceId}
```

Replace every placeholder with the verified ID before turning a route into a
user-facing `https://console.qovery.com/...` link. In particular,
`/organization/settings/...`, `/clusters/{id}`, `/projects/{id}`, and
`/environments/{id}` are not valid Console routes.

## URL format

```
https://{console.qovery.com|new-console.qovery.com}/organization/{orgId}/project/{projectId}/environment/{envId}/service/{serviceId}[/{page}]
```

## Extraction rules

- `orgId` — UUID after `/organization/`
- `projectId` — UUID after `/project/`
- `envId` — UUID after `/environment/`
- `serviceId` — UUID after `/service/`
- `page` — optional suffix (`service-logs`, `deployment-logs`, `general`, `variables`, `settings`, etc.) gives context about what the user is viewing

Not every URL contains all segments. Use whatever IDs are present:

- URL with only `orgId` → organization is known, still ask about project/environment/service
- URL with `orgId` + `projectId` + `envId` → environment is known, may still need service selection
- URL with all four IDs → fully resolved, proceed directly

## Resolving names from IDs

After extracting IDs, resolve names via the API to confirm with the user:

```bash
# Organization name
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization" | jq '.results[] | select(.id == "{orgId}") | {id, name}'

# Project name
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/project/{projectId}" | jq '{id, name}'

# Environment name + all service names/statuses in one call
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{envId}/statuses" | jq '{
    environment: .environment.state,
    applications: [.applications[] | {id, name: .name, state}],
    containers: [.containers[] | {id, name: .name, state}],
    databases: [.databases[] | {id, name: .name, state}],
    jobs: [.jobs[] | {id, name: .name, state}],
    helms: [.helms[] | {id, name: .name, state}]
  }'

# Cluster ID from the environment (the environment knows its cluster)
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/environment/{envId}" | jq '{cluster_id: .cluster_id}'
```

Use the extracted IDs directly in all subsequent API calls and skip any
discovery questions for resources already identified by the URL.
