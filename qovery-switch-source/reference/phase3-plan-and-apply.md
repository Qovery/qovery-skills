# Phase 3 — Plan and apply

Goal: the user approves an exact plan, the switch is applied, and nothing else changed.

## 1. Plan summary (confirmation gate)

Show this, filled from `before.json` and `body.json`, and wait for an explicit yes:

```
Switch source — <container name> (<environment name>)

From:  <image: registry / image:tag>   or   <Git: repository @ branch, root path, Dockerfile>
To:    <Git: repository @ branch, root path, Dockerfile, token name>   or   <image: registry / image:tag>

Kept:  service id, name, Kubernetes names, volumes and data (<n> volume(s)), variables and secrets,
       custom domains, ports (<list>), resources, instances, deployment stage
Off:   auto-deploy and preview environments (Git source only)
Not deployed: the switch only saves the new source. The container keeps running its current
       image until the next deployment.

Next:  deploy a commit (Phase 4), and update CI so it deploys by commit instead of image tag.
```

## 2. Apply

```bash
qovery api container/<containerId> --method PUT --input - < body.json > after.json
```

With `curl`, send the body from the file (`-d @body.json`): pasting a long JSON body into a terminal can wrap it with line breaks, which the API rejects as invalid JSON.

## 3. Check the result

1. The response's `source` matches the plan (`git_repository` or `image`).
2. On a Git source: `auto_deploy` and `auto_preview` are false, `build_settings` is present.
3. Run the kept-fields check:

```bash
bash '__QOVERY_SKILL_DIR__/scripts/check-kept-fields.sh' before.json after.json
```

It must print `kept: …`. If it prints changed fields, stop, show them to the user, and do not deploy. Rebuilding the body from a fresh GET and sending it again restores fields that were dropped, but a volume that was removed cannot be restored with its data.

On an API error, nothing was saved: find the message in [errors.md](errors.md), fix the input, rebuild the body, and show the plan again if it changed.

Move on to Phase 4.
