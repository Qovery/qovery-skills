# Phase 2 — Git source

Goal: a `source.json` the API will accept, and a request body that changes nothing but the source.

## 1. Repository, branch and Dockerfile

Collect from the user, or from the repository they point at:

| Field | Example | Notes |
|---|---|---|
| `url` | `https://github.com/acme/api.git` | HTTPS URL of the repository |
| `provider` | `GITHUB` | `GITHUB`, `GITLAB` or `BITBUCKET` |
| `branch` | `main` | The branch the next deployment builds from |
| `root_path` | `/` or `/services/api` | Build context inside the repository, starting with `/` |
| `dockerfile_path` | `Dockerfile` | Relative to `root_path`: for an app and its Dockerfile in `services/api`, send `root_path` `/services/api` and `dockerfile_path` `Dockerfile` |
| `docker_target_build_stage` | `runtime` | Optional; the last stage is built when absent |

When the image is built in CI today, read that CI's configuration, whatever the tool (for example `.github/workflows/*.yml`, `.gitlab-ci.yml`, `.circleci/config.yml`, `bitbucket-pipelines.yml`, a `Jenkinsfile`), to find the Dockerfile, the build context and any `--target`. Build arguments passed by CI (`--build-arg`) are not carried over by the switch. List them for the user, suggest declaring them as environment variables on the container, and check the first build's logs (Phase 4) for an `ARG` that came through empty. With no CI configuration in the repository (the image is built by hand, or by a CI the agent cannot read), ask the user for the Dockerfile path, the build context and any build arguments.

## 2. Git access

The organization must be able to read the repository:

- **Git provider connected to the organization** (for example the Qovery GitHub app): nothing else to send. The API does not say whether one is connected: ask the user, and use a token when unsure.
- **Git token**: list the organization's tokens whose `type` matches `provider`, and let the user pick one; send its id as `git_token_id`.

```bash
qovery api organization/<organizationId>/gitToken \
  | jq -r --arg p "<provider>" '.results[] | select(.type == $p) | "\(.name)  \(.id)"'
```

Show only token names and ids, never values. The API checks before saving that the token belongs to the organization, that it can read the repository, and that the Dockerfile exists on the branch. A failed check changes nothing (see [errors.md](errors.md)).

Write the source file:

```json
{"git_repository": {"url": "https://github.com/acme/api.git", "provider": "GITHUB", "branch": "main",
                    "root_path": "/", "dockerfile_path": "Dockerfile", "git_token_id": "<uuid or omit>"}}
```

## 3. Build settings (optional)

A Git container gets build settings with the cluster's defaults. Only send them when the user needs more than the defaults, for example a long build:

```json
{"timeout_max_sec": 3600, "cpu_max_in_milli": 4000, "ram_max_in_gib": 8}
```

The API checks them against the cluster's builder limits.

## 4. Build the request body

First ask how new commits should reach the container, and note both answers:

- **Deploy on push** (`auto_deploy`): Qovery deploys every push to the container's branch, from the moment the switch is saved: a push before the Phase 4 deploy builds and deploys that commit. Suggest it unless a CI must run tests before each deploy: then leave it off, and CI deploys the tested commit (Phase 4.4).
- **Previews** (`auto_preview`): when the environment has preview environments turned on, this container's preview copy builds the pull request's branch; off, the copy stays on the container's branch. A preview copy follows new commits on its pull request only with `auto_deploy` on. Previews build pull-request code with the environment's secrets: leave this off when the repository accepts pull requests from forks or outside contributors.

```bash
AUTO_DEPLOY=<true|false> AUTO_PREVIEW=<true|false> \
  bash '__QOVERY_SKILL_DIR__/scripts/build-switch-body.sh' before.json source.json [build-settings.json] > body.json
```

The body keeps every editable field of `before.json` (name, resources, instances, ports with their ids, volumes with their ids, health checks, autoscaling, label and annotation groups), adds `source`, sets `auto_deploy` and `auto_preview` to the user's answers (false when unset), and leaves out the flat image fields. Do not hand-edit it to remove fields.

Move on to Phase 3.
