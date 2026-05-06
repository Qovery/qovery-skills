## PHASE 7: Cleanup & Lifecycle Management

### 7.1 Manual Cleanup

When the user wants to delete the preview environment:

**Via CLI:**
```bash
qovery environment delete --environment "preview-pr-{number}"
```

**Via API:**
```bash
curl -s -X DELETE "https://api.qovery.com/environment/{previewEnvId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN"
```

### 7.2 Restart a Stopped Preview (Recycle)

If the preview was auto-stopped and the user wants to resume working on the PR:

```bash
# Via CLI
qovery environment deploy --environment "preview-pr-{number}"

# Via API
curl -s -X POST "https://api.qovery.com/environment/{previewEnvId}/deploy" \
  -H "Authorization: Token $QOVERY_API_TOKEN"
```

The services will restart with the same configuration and branch. This is faster than creating a new preview environment from scratch.

### 7.3 Token Cleanup

If a shutdown token was generated for the auto-shutdown job, clean it up after the environment is deleted:

```bash
# List tokens created for preview environments
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/organization/{orgId}/apiToken" | jq '.results[] | select(.name | startswith("preview-shutdown-")) | {id, name, created_at}'

# Delete the preview token
curl -s -X DELETE "https://api.qovery.com/organization/{orgId}/apiToken/{tokenId}" \
  -H "Authorization: Token $QOVERY_API_TOKEN"
```

Offer to clean up old preview tokens if there are many.

### 7.4 Blueprint Maintenance

Remind the user:
- The **blueprint environment persists** for future PRs — do NOT delete it
- It should stay **stopped** when not in use to avoid resource costs
- If the source environment (production/staging) changes significantly (new services, major config changes), the blueprint should be **re-created** by cloning the updated source
- To update the blueprint: delete the old one, clone the source again, validate, and stop

### 7.5 List All Preview Environments

To see all active preview environments:

```bash
# Via CLI
qovery environment list

# Via API — filter for preview mode
curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/project/{projectId}/environment" | jq '[.results[] | select(.mode == "PREVIEW") | {id, name, mode}]'
```

### 7.6 Bulk Cleanup

To delete all preview environments at once (e.g., sprint cleanup):

```bash
# List all preview environments
PREVIEW_ENVS=$(curl -s -H "Authorization: Token $QOVERY_API_TOKEN" \
  "https://api.qovery.com/project/{projectId}/environment" | jq -r '.results[] | select(.mode == "PREVIEW") | .id')

# Delete each one
for env_id in $PREVIEW_ENVS; do
  curl -s -X DELETE "https://api.qovery.com/environment/$env_id" \
    -H "Authorization: Token $QOVERY_API_TOKEN"
  echo "Deleted environment: $env_id"
done
```

---

