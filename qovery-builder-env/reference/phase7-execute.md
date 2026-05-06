## PHASE 7: Execute & Verify

Execute the plan in order:

### 7.1 Create the Builder Project
```bash
curl -s -X POST "https://api.qovery.com/organization/{orgId}/project" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "builder-workspaces"}'
```

### 7.2 Create the "Builder" Custom Role
(Phase 2.3 commands)

### 7.3 Set AI API Keys as Project Secrets
(Phase 3.3 commands)

### 7.4 Create the Template Environment + IDE Container + Database
(Phase 3.4 commands)

### 7.5 Deploy and Validate the Template
(Phase 3.5 commands — deploy, watch, verify IDE access, stop)

### 7.6 Clone Template for Each Builder
(Phase 4.2 commands — loop over builders list)

### 7.7 Deploy All Builder Environments
(Phase 4.2 deploy commands)

### 7.8 Invite Builders to Qovery
(Phase 4.3 commands — loop over builders list)

### 7.9 Collect and Share Workspace URLs
(Phase 4.5 commands — get URLs, present summary)

Watch each deployment and verify all builder environments are accessible. If any fail, fetch logs and diagnose:
```bash
qovery log --service "workspace" --since 10m --filter "ERROR"
```

---

