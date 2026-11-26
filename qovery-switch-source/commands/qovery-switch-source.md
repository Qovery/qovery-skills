---
description: Switch a Qovery container between a registry image and a Git build, in place
---

Switch an existing Qovery container service between a registry image and a Git repository
that Qovery builds, in either direction, without recreating the service.

If arguments are provided, use them as context:
- `$ARGUMENTS` — container name, Qovery Console URL, and optionally the target repository or image

Follow the qovery-switch-source skill: read the container, build the update from its current
configuration, confirm the plan and apply the switch. Then, to Git: deploy a commit and set up deploy on
push, with Qovery auto-deploy or a CI job. To an image: deploy the image and restore the CI that pushed it, if any.

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Git remote: !`git remote get-url origin 2>/dev/null || echo "unknown"`
