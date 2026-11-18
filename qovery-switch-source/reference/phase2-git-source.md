# Phase 2 — Git source

Goal: a `source.json` the API will accept, and a request body that changes nothing but the source.

## 1. Repository, branch and Dockerfile

Collect from the user, or from the repository they point at:

| Field | Example | Notes |
|---|---|---|
| `url` | `https://github.com/acme/api.git` | HTTPS URL of the repository |
| `provider` | `GITHUB` | `GITHUB`, `GITLAB` or `BITBUCKET` |
| `branch` | `main` | The branch the next deployment builds from |
| `root_path` | `/` or `/services/api` | Build context inside the repository |
| `dockerfile_path` | `Dockerfile` | Relative to `root_path` |
| `docker_target_build_stage` | `runtime` | Optional; the last stage is built when absent |

When the image is built in CI today, read the CI configuration (`.circleci/config.yml`, `.github/workflows/*.yml`, `.gitlab-ci.yml`) to find the Dockerfile, the build context and any `--target`. Build arguments passed by CI (`--build-arg`) are not carried over by the switch. List them for the user, suggest declaring them as environment variables on the container, and check the first build's logs (Phase 4) for an `ARG` that came through empty.

## 2. Git access

The organization must be able to read the repository:

- **Git provider connected to the organization** (for example the Qovery GitHub app): nothing else to send.
- **Git token**: list the organization's tokens and let the user pick one; send its id as `git_token_id`.

```bash
qovery api organization/<organizationId>/gitToken
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

```bash
bash '__QOVERY_SKILL_DIR__/scripts/build-switch-body.sh' before.json source.json [build-settings.json] > body.json
```

The body keeps every editable field of `before.json` (name, resources, instances, ports with their ids, volumes with their ids, health checks, autoscaling, label and annotation groups), adds `source`, sets `auto_deploy` and `auto_preview` to false, and leaves out the flat image fields. Do not hand-edit it to remove fields.

Move on to Phase 3.
