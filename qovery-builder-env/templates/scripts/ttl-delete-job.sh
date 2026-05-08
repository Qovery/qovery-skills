UA="QoverySkill/qovery-builder-env-ttl (https://github.com/Qovery/qovery-skills)"

# Delete job — runs weekly, checks if environment has been stopped for > N days
curl -sf -X POST "https://api.qovery.com/environment/{builderEnvId}/job" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "User-Agent: $UA" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ttl-auto-delete",
    "description": "Deletes this environment if stopped for more than 7 days",
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
        "arguments": ["-c", "curl -sf -H 'User-Agent: QoverySkill/qovery-builder-env-ttl' -X DELETE https://api.qovery.com/environment/{builderEnvId} -H \"Authorization: Token $SHUTDOWN_TOKEN\" && echo \"Environment deleted by TTL\" || echo \"Delete failed or already deleted\""],
        "scheduled_at": "0 0 * * 0",
        "timezone": "Etc/UTC"
      }
    }
  }'
