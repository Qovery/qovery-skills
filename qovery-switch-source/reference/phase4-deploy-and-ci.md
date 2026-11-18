# Phase 4 — Deploy, verify, and deploy on push

Goal: the container runs an image Qovery built from the chosen commit, its data is intact, and CI deploys new commits.

## 1. Deploy a commit (confirm first)

A Git container deploys the stored commit (`source.git_repository.deployed_commit_id`) unless the request names one. Ask which commit to deploy: usually the head of the branch, or the commit currently running in production when the image was built from it.

```bash
echo '{"git_commit_id": "<full 40-character sha>"}' | qovery api container/<containerId>/deploy --method POST --input -
```

Sending `image_tag` to a Git container is refused: the image comes from the build.

## 2. Follow the deployment

```bash
qovery api container/<containerId>/status
```

The steps of a first Git deployment are: build queueing, creation of the image repository in the cluster's registry, Git clone, build, push, then deployment. Poll every 20 to 30 seconds and report the step. If the build fails, the deployment stops before anything changes in the cluster and the previous image keeps running; read the build logs (`qovery log` or the Console) and see [errors.md](errors.md).

## 3. Verify

```bash
qovery api container/<containerId> > deployed.json
```

- `source.git_repository.deployed_commit_id` is the commit you deployed.
- `registry`, `image_name`, `tag` now point at the build in the cluster's registry (the tag contains the commit sha).
- `bash '__QOVERY_SKILL_DIR__/scripts/check-kept-fields.sh' before.json deployed.json` prints `kept: …`.
- The application answers as before (health check, a request on its URL), and data on its volumes is still there. Suggest the user check a known file or record.

## 4. Deploy on push from CI

A Git container does not deploy by itself on a push: `auto_deploy` stays off on a Git source. Replace the CI step that built and pushed the image, and then deployed a tag, with one call that deploys the pushed commit.

Copy the matching template into the user's repository, then adapt the copy:

- set the container id;
- set the branch filter to the container's branch (`source.git_repository.branch`), not always `main`;
- run the deploy after the tests pass: add `needs: <test job>` in GitHub Actions, or `requires: [<test job>]` in the CircleCI workflow;
- in the `User-Agent` header, replace the text between `version:` and `;` with the content of `__QOVERY_SKILL_DIR__/_version.txt` (the installer stamps only Markdown and shell files, so the YAML still holds a placeholder);
- CircleCI: the template reads `QOVERY_API_TOKEN` from a context named `qovery`; create that context with the token, or point the job at the context the user already has.

| CI | Template | Destination |
|---|---|---|
| GitHub Actions | `__QOVERY_SKILL_DIR__/templates/ci/github-actions-deploy-commit.yml` | `.github/workflows/qovery-deploy.yml` |
| CircleCI | `__QOVERY_SKILL_DIR__/templates/ci/circleci-deploy-commit.yml` | merge the job and workflow into `.circleci/config.yml` |
| Other | the `curl` call below | a step after tests pass |

```bash
curl -sS --fail-with-body -X POST "https://api.qovery.com/container/$QOVERY_CONTAINER_ID/deploy" \
  -H "Authorization: Token $QOVERY_API_TOKEN" \
  -H "User-Agent: QoverySkill/qovery-switch-source (version:__QOVERY_SKILLS_VERSION__; https://github.com/Qovery/qovery-skills)" \
  -H "Content-Type: application/json" \
  -d "{\"git_commit_id\": \"$COMMIT_SHA\"}"
```

The CI needs a Qovery API token stored as a CI secret (`QOVERY_API_TOKEN`). The user creates it in the Console (organization settings, API tokens), or with `qovery-policy-token` for a token limited to deploying this service. Never create or print the token in the conversation.

Remove the old steps that pushed the image to the registry and deployed by `image_tag`: they now fail on this container.
