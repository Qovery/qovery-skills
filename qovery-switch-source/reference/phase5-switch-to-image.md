# Phase 5 — Switch back to a registry image

Goal: the container pulls an image from a registry again, with the same service, volumes and variables.

## 1. Pick the image

- **Registry**: list the organization's registries and let the user pick one. The registry must belong to the same organization as the container.

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

```bash
qovery api container/<containerId> > before.json
bash '__QOVERY_SKILL_DIR__/scripts/build-switch-body.sh' before.json source.json > body.json
```

Show the plan summary and wait for a yes. Then:

```bash
qovery api container/<containerId> --method PUT --input - < body.json > after.json
bash '__QOVERY_SKILL_DIR__/scripts/check-kept-fields.sh' before.json after.json
```

After the switch, `source.image` holds the chosen image, `build_settings` is gone, and the Git link is removed. `auto_deploy` and `auto_preview` stay off until the user turns them on again.

## 3. Deploy (confirm first)

```bash
echo '{}' | qovery api container/<containerId>/deploy --method POST --input -
```

Verify as in Phase 4 step 3: the container runs the chosen image, `check-kept-fields.sh` prints `kept: …`, and data on the volumes is intact. Remind the user to turn CI back to building and pushing the image, then deploying it by `image_tag`.
