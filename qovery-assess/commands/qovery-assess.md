---
description: Read-only assessment of a Qovery organization with a shareable gap analysis
---

Run a read-only configuration assessment of a Qovery organization and produce a
customer-shareable gap analysis.

If arguments are provided, use them as context:
- `$ARGUMENTS` — a Qovery Console URL (organization, project, or environment), an
  organization name, or a scope hint such as "production only" or "security focus"

Follow the qovery-assess skill: collect a GET-only snapshot, run every cataloged family
(CP, CL, TP, RL, BP, SC, VS, DL, LG, OP, CE, DR), score each pillar, and write the report
plus findings CSV. Do not stop at a subset — the score is only comparable across
reassessments if the whole catalog was run.

IMPORTANT: this is read-only. Do not create, update, delete, deploy, stop, or restart
anything. Never fetch database master credentials or a cluster kubeconfig. Never print
a secret value. If the user asks for a fix mid-assessment, finish the assessment first,
then offer the appropriate skill as a separate, confirmed step.
