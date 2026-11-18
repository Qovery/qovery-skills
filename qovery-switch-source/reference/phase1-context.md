# Phase 1 — Context

Goal: know exactly which container to switch, what it runs today, and whether anything outside the API manages it.

## 1. Authenticate

Follow [auth.md](auth.md). Prefer `qovery api <path>`: it uses the CLI session, so no token reaches the shell. With `curl`, send the token inline and the skill's User-Agent header on every call.

## 2. Find the container

- **Console URL given**: extract the organization, project, environment and service IDs as described in [console-url-detection.md](console-url-detection.md).
- **Names given**: list them with the CLI (`qovery service list` in the right context) or walk the API: `organization/{organizationId}/project` → `project/{projectId}/environment` → `environment/{environmentId}/container`.
- Confirm the container's name and environment with the user before going further. Containers in different environments often share a name.

Only a service of type `CONTAINER` can switch source. Applications, jobs and Helm services choose their source at creation; for those, explain that the switch is not available and stop.

## 3. Read and save the current state

```bash
qovery api container/<containerId> > before.json
```

Keep `before.json` for the whole journey: Phase 2 builds the request from it and Phase 3 compares against it. Then report, from the response:

- the current source: `source.image` (registry, image, tag) or `source.git_repository` (repository, branch, root path, Dockerfile);
- whether a response has no `source` key at all: the API predates source switching. Stop and tell the user the switch is not available on their Qovery instance yet;
- the volumes (`storage`): they are kept, with their data, as long as the body keeps their `id`;
- `auto_deploy` and `auto_preview`: a switch to Git turns both off (see Phase 4 for deploy on push).

If the container already has the source the user asked for, say so and stop. A Git container that should only change branch or repository stays a Git-to-Git update: same Phase 2 and 3, with the new `git_repository`.

## 4. Check what else manages the container

Ask the user, and check what you can:

- **Terraform** (`qovery_container` resource): a switch made through the API is overwritten or refused at the next `terraform apply` unless the Terraform configuration declares the same source. Recommend switching in the Terraform configuration instead, with a provider version whose `qovery_container` resource supports a `source` block. If the provider in use has no `source` block, warn that an apply sends the image fields and the API refuses them on a Git container; agree on a plan before switching.
- **CI that deploys new image tags** (for example a CircleCI job calling the deploy endpoint with `image_tag`, or a registry webhook): after a switch to Git these calls are refused, because a Git container builds its own image. Phase 4 replaces them with a deploy by commit.
- **Qovery CLI or Console versions** that do not know about Git containers yet show the container as an image container. Ask the user to update them before editing the container there.

Move on to Phase 2 (to Git) or Phase 5 (back to an image).
