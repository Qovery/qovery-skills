# Errors during a switch or deploy

Every check runs before anything is saved: an error means the container is unchanged. Fix the input, rebuild the body from a fresh GET, and try again.

## On `PUT /container/{containerId}`

| Message (or status) | Cause | Fix |
|---|---|---|
| `A container with a Git repository source must have auto_deploy and auto_preview set to false` | The body turns on auto-deploy or previews for a Git source | Rebuild the body with `build-switch-body.sh`; it sends both as false |
| `send \`source\` or \`registry_id\`, \`image_name\` and \`tag\`, not both` | `source` and the flat image fields both ask for a change and do not name the same image. A side that repeats what the container already has is ignored, so a body copied from the GET is accepted | Rebuild with `build-switch-body.sh`, which sends only `source` |
| `send all of \`registry_id\`, \`image_name\` and \`tag\`, or none of them to keep the image` | Only some flat image fields were sent on an image container, often a GET copy with only `tag` changed (GET returns `registry.id`, not `registry_id`) | Rebuild with `build-switch-body.sh`, or send all three flat fields |
| `send \`source.image.registry_id\`` | A switch from Git back to an image without the registry: the API never guesses it from the cluster's own build registry | Add `registry_id` to `source.image` (Phase 5); list registries with `organization/{organizationId}/containerRegistry` |
| `this container builds from git: send \`source.image\` to switch back to an image` | Flat image fields different from the running image were sent to a Git container, often by an older Console, CLI or Terraform provider | Switch back with `source.image` (Phase 5), or update the client that sent the edit |
| `JSON parse error … CTRL-CHAR` | The terminal wrapped a pasted JSON body | Send the body from a file: `--input - < body.json` or `curl -d @body.json` |
| Error on the Git token or the repository | The token is not in the organization, cannot read the repository, or the branch is missing | Pick another token from `organization/{organizationId}/gitToken`, check the branch name and the repository URL |
| Error on the Dockerfile | No Dockerfile at `root_path` + `dockerfile_path` on that branch | `root_path` is relative to the repository root and `dockerfile_path` is relative to `root_path`: with the Dockerfile at `services/api/Dockerfile`, send `root_path: /services/api` and `dockerfile_path: Dockerfile` |
| Error on build settings | Builder CPU, memory or timeout above the cluster's limits | Lower the values, or leave build settings out to use the defaults |
| Not found on the registry, on a switch to an image | The registry id is not one of the organization's registries | List them with `organization/{organizationId}/containerRegistry` |
| Error on the image, on a switch to an image | The tag does not exist in that registry | Check the image name and tag in the registry |
| 403 | The user cannot edit this container | Editing a container needs the admin permission on it; use a token or an account that has it |

## On `POST /container/{containerId}/deploy`

| Message (or status) | Cause | Fix |
|---|---|---|
| Error on `image_tag` | A tag was sent to a Git container, usually by an old CI step | Send `git_commit_id` instead, and update the CI step (Phase 4) |
| Error on `git_commit_id` | A commit was sent to an image container | Send `image_tag`, or switch the container to Git first |
| Build failed | The Dockerfile does not build on the cluster's builder | Read the build logs; check build arguments the CI used to pass, the target stage, and the builder's memory |
| Deployment failed after the build | The new image does not start (port, health check, missing variable) | Use `qovery-troubleshoot`; the switch itself is not the cause. To go back, switch to the previous image (Phase 5), then deploy it: the switch alone changes only the configuration |
