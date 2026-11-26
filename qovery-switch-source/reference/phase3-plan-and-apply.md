# Phase 3 — Plan and apply

Goal: the user approves an exact plan, the switch is applied, and nothing else changed.

## 1. Plan summary (confirmation gate)

Show this, filled from `before.json` and `body.json`, and wait for an explicit yes:

```
Switch source — <container name> (<environment name>)

From:  <image: registry / image:tag>   or   <Git: repository @ branch, root path, Dockerfile>
To:    <Git: repository @ branch, root path, Dockerfile, token name>   or   <image: registry / image:tag>

Kept:  service id, name, volumes (<n>: id, size, mount path), ports (<list>), resources,
       instances, health checks, autoscaling: compared after the switch. Volume data is not
       compared: the volumes are kept, and the user checks the data after the deploy.
       Variables and secrets, custom domains, deployment stage: not in the request, not compared.
Auto:  auto-deploy <on|off> -> <on|off>, previews <on|off> -> <on|off>. On Git, auto-deploy
       deploys every push to <branch>; on an image, it deploys a new tag of the image.
Not deployed: the switch only saves the new source. The container keeps running its current
       image until the next deployment<, or until the next push to <branch> when auto-deploy is
       on: that push deploys without another confirmation>.

Next:  deploy a commit (Phase 4), then <check the auto-deploy webhook | set up the CI job that
       deploys the commit | deploy each new commit by hand (no CI)>.
```

## 2. Apply

```bash
qovery api container/<containerId> --method PUT --input - < body.json > put-response.json \
  && qovery api container/<containerId> > after.json
```

If the PUT fails, `qovery api` exits non-zero and `put-response.json` holds the API error: nothing was saved, find the message in [errors.md](errors.md). On success, `after.json` is a fresh GET, the same shape as `before.json`.

With `curl`, send the body from the file (`-d @body.json`): pasting a long JSON body into a terminal can wrap it with line breaks, which the API rejects as invalid JSON.

## 3. Check the result

1. The `source` in `after.json` matches the plan (`git_repository` or `image`).
2. `auto_deploy` and `auto_preview` match the plan. On a Git source, `build_settings` is present.
3. Run the kept-fields check:

```bash
AUTO_DEPLOY=<true|false> AUTO_PREVIEW=<true|false> \
  bash '__QOVERY_SKILL_DIR__/scripts/check-kept-fields.sh' before.json after.json
```

Pass the same `AUTO_DEPLOY` and `AUTO_PREVIEW` as the body (leave them unset if the body did). It must print `kept: …`. If it prints changed fields, stop, show them to the user, and do not deploy. Don't retry from a fresh GET: it already reflects the change. A field that changed can be set back from `before.json` with a new plan and a yes; a removed port comes back as a new port without its old id, and a removed volume cannot be restored with its data.

On an API error, nothing was saved: find the message in [errors.md](errors.md), fix the input, rebuild the body, and show the plan again if it changed.

Move on to Phase 4.
