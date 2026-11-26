# Phase 5 — Switch back to a registry image

Goal: the container pulls an image from a registry again, with the same service, volumes and variables.

## 1. Pick the image

- **Registry**: list the organization's registries and let the user pick one. The registry must belong to the same organization as the container. When this journey started from an image (Phase 1 `before.json`), offer that registry and image first: an organization often has several registries of the same kind.

```bash
qovery api organization/<organizationId>/containerRegistry
```

- **Image and tag**: the API checks that the tag exists in that registry before saving, so ask for an exact tag (`1.4.2`, a commit sha), not a moving one, when the image is built by CI.
- The image the container runs now (flat `registry`, `image_name`, `tag` in the GET response) is the last Qovery build, stored in the cluster's own registry. Prefer an image from the user's own registry: the cluster's registry is managed by Qovery.

Write the source file. `registry_id` is required: without it, the API refuses a switch from Git back to an image. Use the id of a registry from the list above, not the `registry.id` of the GET response, which is the cluster's build registry.

```json
{"image": {"registry_id": "<registry uuid>", "image_name": "acme/api", "tag": "1.4.2"}}
```

## 2. Build, confirm, apply, check

Same steps as Phases 2.4 and 3, with this source file:

Keep Phase 1's `before.json`: save the Git state under another name.

Ask whether Qovery should deploy each new tag of the image (`auto_deploy`) and run this container in preview environments (`auto_preview`). A switch from Git resets both, and `auto_deploy` now means a new image tag, not a push. When Phase 1's `before.json` comes from an image, offer its values first.

```bash
qovery api container/<containerId> > before-back.json
AUTO_DEPLOY=<true|false> AUTO_PREVIEW=<true|false> \
  bash '__QOVERY_SKILL_DIR__/scripts/build-switch-body.sh' before-back.json source.json > body.json
```

Unset, both are sent as false. With `auto_deploy` on, a new tag pushed after the switch deploys without another confirmation: say so in the plan. Show both in the plan; its last line reads: deploy the image (step 3), and the auto-deploy state.

Show the plan summary and wait for a yes. Then:

```bash
qovery api container/<containerId> --method PUT --input - < body.json > put-response.json \
  && qovery api container/<containerId> > after.json \
  && AUTO_DEPLOY=<true|false> AUTO_PREVIEW=<true|false> \
     bash '__QOVERY_SKILL_DIR__/scripts/check-kept-fields.sh' before-back.json after.json
```

After the switch, `source.image` holds the chosen image, `build_settings` is gone, and the Git link is removed. The flat `registry`, `image_name` and `tag` show the new image at once, while the cluster keeps running the last build until the next deployment.

## 3. Deploy (confirm first)

```bash
echo '{}' | qovery api container/<containerId>/deploy --method POST --input -
```

Follow the deployment with `qovery api container/<containerId>/status` until `state` is `DEPLOYED` with a `last_deployment_date` after the switch: the flat image fields already showed the new image before the deploy, so they prove nothing. Then save a fresh GET as `deployed.json` and run `check-kept-fields.sh before-back.json deployed.json` with the same flags, and suggest the user check the data on the volumes. If a CI used to build and push the image, remind the user to turn it back to building and pushing the image, then deploying it by `image_tag`.
