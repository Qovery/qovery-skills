# Phase 4 — Deploy, verify, and deploy on push

Goal: the container runs an image Qovery built from the chosen commit, its data is intact, and CI deploys new commits.

## 1. Deploy a commit (confirm first)

A Git container deploys the stored commit (`source.git_repository.deployed_commit_id`) unless the request names one. The stored commit is the head of the branch when the source was saved. To deploy the current head, read it with `git ls-remote -- "<url>" "refs/heads/<branch>"` (keep the quotes) (public repository, or with the user's Git credentials), or ask the user for the sha. Ask which commit to deploy: usually the head of the branch, or the commit currently running in production when the image was built from it.

```bash
echo '{"git_commit_id": "<full 40-character sha>"}' | qovery api container/<containerId>/deploy --method POST --input -
```

Sending `image_tag` to a Git container is refused: the image comes from the build.

## 2. Follow the deployment

```bash
qovery api container/<containerId>/status
```

The steps of a first Git deployment are: build queueing, creation of the image repository in the cluster's registry (skipped when it exists), Git clone, build, deployment queueing, then deployment. Poll every 20 to 30 seconds and report the step. If the build fails, the deployment stops before anything changes in the cluster and the previous image keeps running; read the build logs (`qovery log` or the Console) and see [errors.md](errors.md).

## 3. Verify

```bash
qovery api container/<containerId> > deployed.json
```

- `source.git_repository.deployed_commit_id` is the commit you deployed. The status may read `OUT_OF_DATE` right after a successful Git deployment (a known API issue): trust the commit and the running tag.
- `registry`, `image_name`, `tag` now point at the build in the cluster's registry (the tag contains the commit sha).
- `bash '__QOVERY_SKILL_DIR__/scripts/check-kept-fields.sh' before.json deployed.json` prints `kept: …`.
- When the service has a public port or URL, check it answers. A repository that builds a different app than the old image answers differently: compare with what the user expects, not with the old image. Suggest the user check a known file or record on the volumes.

## 4. Deploy on push from CI

A Git container does not deploy by itself on a push: `auto_deploy` stays off on a Git source.

- **A CI deploys this container today**: replace the steps that built and pushed the image, and then deployed a tag, with one call that deploys the pushed commit.
- **No CI** (the image was pushed by hand): say that each new commit needs a deploy (Console, CLI or this API call), and offer a CI job. Add one only if the user wants it.

Show the user the file you will add or change, and wait for a yes before writing into their repository. Copy the matching template, then adapt the copy:

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

For any other CI, adapt the call:

- set `COMMIT_SHA` from the CI's own variable for the pushed commit: `$CI_COMMIT_SHA` in GitLab CI, `$BITBUCKET_COMMIT` in Bitbucket Pipelines, `$GIT_COMMIT` in Jenkins, `$GITHUB_SHA` in GitHub Actions;
- set `QOVERY_CONTAINER_ID` in the job, or write the id in the URL;
- run the job only on the container's branch, and after the test job (a later stage, or `needs:` in GitLab CI);
- store `QOVERY_API_TOKEN` as a masked secret variable, so it never shows in job logs. In GitLab CI, mark it protected only when the container's branch is protected: a protected variable is empty on other branches.

The CI needs a Qovery API token stored as a CI secret (`QOVERY_API_TOKEN`). The user creates it in the Console (organization settings, API tokens), or with `qovery-policy-token` for a token limited to deploying this service. Never create or print the token in the conversation.

Remove the old steps that pushed the image to the registry and deployed by `image_tag`: they now fail on this container.
