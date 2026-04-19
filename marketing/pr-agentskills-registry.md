# PR for agentskills/agentskills — Reference Qovery Skill

## Where to submit

Repository: https://github.com/agentskills/agentskills
Target: The agentskills repo is the specification and documentation for the Agent Skills standard. Check if there's a skill directory, registry, or examples section to add Qovery to.

Note: The agentskills.io site lists compatible tools/clients (Claude Code, Cursor, etc.) on its homepage, but does not appear to have a public skill registry yet. The repo contains docs, a reference SDK, and the spec. The best approach may be:

1. Open a Discussion or Issue asking about listing third-party skills
2. If there's a community showcase, submit there
3. If they accept PRs to list example skills, submit one

## Suggested Issue/Discussion Title

Community Skill: Qovery — Deploy any application to Kubernetes

## Suggested Content

### Description

We built an Agent Skill for deploying applications to Kubernetes using [Qovery](https://www.qovery.com). The skill follows the Agent Skills specification and works with all compatible tools (Claude Code, Cursor, OpenCode, VS Code Copilot, Gemini CLI, and 30+ more).

### What it does

The Qovery Agent Skill teaches AI agents how to:
- Analyze codebases and detect language/framework/dependencies
- Create production-ready Dockerfiles for 12+ frameworks
- Provision databases (container mode for dev, managed for production)
- Set up environment variables with proper scoping, aliases, and interpolation
- Deploy via CLI + API or generate complete Terraform manifests
- Watch deployments and auto-fix configuration issues
- Handle Helm charts, Terraform modules, lifecycle jobs, and cron jobs

### Links

- **Repository**: https://github.com/Qovery/qovery-skills
- **Install**: `curl -fsSL https://skill.qovery.com/install.sh | bash`
- **Documentation**: https://www.qovery.com/docs/getting-started/quickstart/ai-agent
- **License**: MIT

### Skill metadata

```yaml
name: qovery-deploy
description: Deploy any application, database, Helm chart, or Terraform module to Kubernetes using Qovery.
license: MIT
compatibility: opencode
```

### Why this is relevant

This is one of the first comprehensive infrastructure/deployment skills built on the Agent Skills standard. It demonstrates:
- A 3,300+ line skill covering complex multi-step workflows
- Forward engineering pattern (code to deployed application)
- Integration with multiple tools (CLI, API, Terraform) from a single skill
- Auto-diagnosis and fix loops for deployment failures
- One-command install script that targets all discovery paths
