UA="QoverySkill/qovery-builder-env-ttl (https://github.com/Qovery/qovery-skills)"

# 1. Generate a shutdown token
SHUTDOWN_TOKEN=$(curl -sf -X POST "https://api.qovery.com/organization/{orgId}/apiToken" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "User-Agent: $UA" \
  -H "Content-Type: application/json" \
  -d '{"name": "builder-ttl-{name}", "description": "Auto-shutdown token for builder-{name}"}' | jq -r '.token')

# 2. Create the TTL cron job
JOB_ID=$(curl -sf -X POST "https://api.qovery.com/environment/{builderEnvId}/job" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "User-Agent: $UA" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ttl-auto-shutdown",
    "description": "Automatically stops this environment after the configured TTL",
    "cpu": 250,
    "memory": 256,
    "max_nb_restart": 0,
    "max_duration_seconds": 60,
    "auto_preview": false,
    "auto_deploy": false,
    "healthchecks": {},
    "source": {
      "docker": {
        "dockerfile_raw": "FROM curlimages/curl:8.11.1\nENTRYPOINT [\"sh\", \"-c\"]"
      }
    },
    "schedule": {
      "cronjob": {
        "entrypoint": "sh",
        "arguments": ["-c", "curl -sf -H 'User-Agent: QoverySkill/qovery-builder-env-ttl' -X POST https://api.qovery.com/environment/{builderEnvId}/stop -H \"Authorization: Token $SHUTDOWN_TOKEN\" && echo \"Environment stopped by TTL\" || echo \"Already stopped or failed\""],
        "scheduled_at": "0 20 * * 1-5",
        "timezone": "Europe/Paris"
      }
    }
  }' | jq -r '.id')

# 3. Set the shutdown token as a secret
curl -sf -X POST "https://api.qovery.com/application/$JOB_ID/secret" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "User-Agent: $UA" \
  -H "Content-Type: application/json" \
  -d "{\"key\": \"SHUTDOWN_TOKEN\", \"value\": \"$SHUTDOWN_TOKEN\"}"
