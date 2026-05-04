---
description: Create a preview environment for a PR or branch using Qovery
---

Create a Qovery preview environment for the specified PR or current branch.

If arguments are provided, use them as the PR reference:
- `$ARGUMENTS` — PR number (e.g., "123"), branch name (e.g., "feat/my-feature"), PR URL, or Qovery Console URL

If no arguments are provided, detect the current git branch and any open PR for it.

Follow the qovery-preview skill instructions to:
1. Authenticate and detect the PR/branch context
2. Check for an existing blueprint environment (create one if needed)
3. Clone the blueprint for this PR
4. Configure auto-shutdown
5. Present the deployment plan summary and get confirmation
6. Deploy and provide the preview URLs

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Git remote: !`git remote get-url origin 2>/dev/null || echo "unknown"`
PR info: !`gh pr view --json number,title,headRefName,baseRefName 2>/dev/null || echo "no PR found for current branch"`
