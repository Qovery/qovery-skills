---
description: Switch a Qovery container between a registry image and a Git build, in place
---

Switch an existing Qovery container service between a registry image and a Git repository
that Qovery builds, in either direction, without recreating the service.

If arguments are provided, use them as context:
- `$ARGUMENTS` — container name, Qovery Console URL, and optionally the target repository or image

Follow the qovery-switch-source skill: read the container, build the update from its current
configuration, confirm the plan, apply the switch, deploy a commit, and set up CI to deploy on push.

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Git remote: !`git remote get-url origin 2>/dev/null || echo "unknown"`
