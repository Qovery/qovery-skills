---
name: qovery-switch-source
description: Switches an existing Qovery container service in place between a registry image and a Git repository that Qovery builds, in either direction, keeping the same service id, name, Kubernetes resources, volumes, variables and domains. Builds the update from the live container so nothing else changes, confirms the plan, applies it through the Qovery API, deploys a chosen commit, sets up CI to deploy on push, and verifies what was kept. Use when a user wants Qovery to build a container that was deployed from a registry image, wants to move a container from a CI-built image (CircleCI, GitHub Actions, GitLab CI) to a Qovery build, wants to switch a container back to a registry image, or asks to change a container's source without recreating the service.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: container-source-switch
---

# Qovery Switch Source Skill

This skill switches an existing container service between two sources without recreating it:

- **Image**: Qovery pulls an image from a container registry (the image is built elsewhere, for example in CircleCI).
- **Git repository**: Qovery clones a repository, builds its Dockerfile on the cluster's builder, and pushes the image to the cluster's own registry.

The service keeps its id, name, Kubernetes resource names, volumes and their data, environment variables and secrets, custom domains, ports and deployment stage. Only where the image comes from changes. A switch never deploys by itself: the next deployment uses the new source.

## Usage Tracking

At each new launch, start one anonymous run before authentication or other work,
even when the user is already signed in:

```bash
bash '__QOVERY_SKILL_DIR__/scripts/track-skill-usage.sh' start qovery-switch-source
```

Retain the returned absolute **state-file path** in the journey context across
shell calls, steps and resumptions. The file holds the run/anonymous UUIDs,
original timestamp and private correlation proof; never read it into the prompt,
print its contents, or retain tokens, AI responses or CLI cache contents.
The helper requires macOS, Linux or WSL with Bash and curl. The installer supplies a verified native Rust binary;
neither Rust nor Python needs to be installed. Native Windows is unsupported.
No path is returned for opt-out, development installs, an unavailable tracking binary or an
unsupported skill: continue normally. The root router `qovery` is excluded by the
backend name contract; downstream `qovery-*` skills track their own executions.

For a retry or resumed journey, use `resume STATE_PATH` to retry the anonymous
start only, never `start` again. To retry association, call `associate` again with
the retained state path and the explicitly selected organization UUID.
After login and **explicit organization selection/creation**, run:

```bash
bash '__QOVERY_SKILL_DIR__/scripts/track-skill-usage.sh' associate 'STATE_PATH' --organization 'ORGANIZATION_UUID'
```

Replace those placeholders with the retained path and selected UUID. Already
signed-in users follow the same start → associate order. Do not guess the first
organization returned by an API. The helper obtains a Bearer session internally;
API/policy/machine tokens cannot associate a run with a person. Association means
identity and organization are known, not that deployment succeeded.
One run has one immutable account/organization association. On an account or
organization change, end the old journey and start a **new execution**; never
reattach the old run or change IDs to bypass a conflict.

Requests run in the background with bounded deadlines. Network failures remain
queued with backoff; `resume` retries anonymous starts, while `associate` also
rechecks the current account and selected organization before retrying association.
Keep the path on interruption. At journey completion, use `cleanup STATE_PATH`
only after queued requests are no longer needed; explicit cleanup discards pending
requests too. State is private, limited to 100 runs and pruned after 30 days on
subsequent launches. Set `QOVERY_SKILLS_NO_TRACKING=1` before any command to prevent
helper state creation and sends, including pending retries. It does not remove
User-Agent headers from other API calls or disable server audit logs.
`cleanup` still removes state.
`QOVERY_SKILLS_TRACKING_DEBUG=1` prints safe statuses without request data or secrets.
Never call the legacy tracking endpoint as a fallback.

> **API rule:** send this exact `User-Agent` header on **every** `curl` call to `api.qovery.com`, spelled out in full each time — a shell variable set in one command is gone by the next one:
>
> ```
> -H "User-Agent: QoverySkill/qovery-switch-source (version:__QOVERY_SKILLS_VERSION__; https://github.com/Qovery/qovery-skills)"
> ```

## When to Use This Skill

Trigger phrases:
- "Make Qovery build my container from GitHub instead of pulling the image from ECR"
- "We build images in CircleCI, can Qovery build this service instead?"
- "Switch my container service to a Git build without recreating it"
- "Switch this container back to a Docker Hub image"
- "Change the source of my Qovery container"
- `/qovery-switch-source` (slash command)

Not for creating a new service (use `qovery-deploy`) or for applications, jobs and Helm services, which choose their source at creation.

## Workflow checklist

```
Switch Source Progress:
- [ ] Phase 1 — Context: auth, find the container, read its current source, Terraform check
- [ ] Phase 2 — Git source: pick the repository, branch, Dockerfile and Git access; build the body
- [ ] Phase 3 — Plan summary + USER CONFIRMATION, then apply the switch
- [ ] Phase 4 — Deploy a commit, verify, and set up CI to deploy on push
- [ ] Phase 5 — (when asked) switch back to a registry image
```

Run Phase 5 instead of Phases 2 to 4 when the container already builds from Git and the user wants an image.

## Reference materials (load on demand)

| Phase | File | Purpose |
|---|---|---|
| Console URL | [reference/console-url-detection.md](reference/console-url-detection.md) | Extract IDs from a Qovery Console URL |
| Auth | [reference/auth.md](reference/auth.md) | Authentication and token handling |
| Phase 1 | [reference/phase1-context.md](reference/phase1-context.md) | Find the container, read its source, Terraform and Console checks |
| Phase 2 | [reference/phase2-git-source.md](reference/phase2-git-source.md) | Repository, branch, Dockerfile, Git token, build settings, request body |
| Phase 3 | [reference/phase3-plan-and-apply.md](reference/phase3-plan-and-apply.md) | Plan template, confirmation gate, PUT, checks after the switch |
| Phase 4 | [reference/phase4-deploy-and-ci.md](reference/phase4-deploy-and-ci.md) | Deploy at a commit, verify, CI templates for deploy on push |
| Phase 5 | [reference/phase5-switch-to-image.md](reference/phase5-switch-to-image.md) | Switch back to a registry image and deploy |
| Errors | [reference/errors.md](reference/errors.md) | API errors during a switch or deploy, and the fix for each |

## Rules that protect the service

- **Never send a partial update.** `PUT /container/{containerId}` replaces the whole service: a port or volume missing from the body is removed, and a removed volume loses its data. Always build the body with `scripts/build-switch-body.sh` from a fresh GET of the container.
- **Confirm before writing.** Show the Phase 3 plan and wait for an explicit yes before the PUT, and again before any deployment.
- **Keep the before and after.** Save the GET response before the switch and compare it with the one after, using `scripts/check-kept-fields.sh`. Report any difference instead of retrying.
- **Never send `source` together with the flat `registry_id`, `image_name` and `tag` fields.** The API refuses it. The body builder sends only `source`.
- **Auto-deploy and preview stay off on a Git source.** The API refuses `auto_deploy: true` or `auto_preview: true` for a container that builds from Git. Deploy on push is done by CI calling the deploy endpoint with the commit (Phase 4).

## Quick reference

### Scripts (run in place, from the installed skill directory)

```bash
# Body for the switch: keeps every editable field of the container, adds the new source
bash '__QOVERY_SKILL_DIR__/scripts/build-switch-body.sh' container.json source.json [build-settings.json] > body.json

# After the switch: prints any kept field that changed
bash '__QOVERY_SKILL_DIR__/scripts/check-kept-fields.sh' before.json after.json
```

### API endpoints

```
# Base URL: https://api.qovery.com   Prefer `qovery api <path>`; with curl add the User-Agent header above.
GET    /container/{containerId}                          Current config, `source`, running image
PUT    /container/{containerId}                          Switch: body from build-switch-body.sh
POST   /container/{containerId}/deploy                   {"git_commit_id": "<sha>"} on a Git source
GET    /container/{containerId}/status                   Deployment progress
GET    /organization/{organizationId}/gitToken           Git tokens the organization can use
GET    /organization/{organizationId}/containerRegistry  Registries for a switch back to an image
```

### Request shapes

```json
{"git_repository": {"url": "https://github.com/acme/api.git", "branch": "main", "root_path": "/",
                    "provider": "GITHUB", "git_token_id": "<optional>", "dockerfile_path": "Dockerfile"}}
{"image": {"registry_id": "<registry uuid>", "image_name": "acme/api", "tag": "1.4.2"}}
```

### What the GET response tells you

- `source.image` or `source.git_repository`: the current source. A response without `source` comes from an API that predates source switching: stop, the switch is not available there (Phase 1).
- `registry`, `image_name`, `tag`: the image the container runs. On a Git source they hold the previous image until the first build, then the build in the cluster's registry.
- `source.git_repository.deployed_commit_id`: the commit the next deployment builds when no `git_commit_id` is sent.
- `build_settings`: present only on a Git source.

## Reference links

- Qovery API reference: https://www.qovery.com/docs/api-reference/introduction
- Qovery CLI: https://www.qovery.com/docs/cli/commands/overview
