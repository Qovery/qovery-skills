# PR for anthropics/skills — Add Qovery as a Partner Skill

## Where to submit

Repository: https://github.com/anthropics/skills
Target: Add Qovery to the "Partner Skills" section in the README.md

The anthropics/skills README has a "Partner Skills" section at the bottom that currently lists Notion. Qovery should be added there.

## PR Title

Add Qovery as a Partner Skill — deploy any app to Kubernetes

## PR Description

### Summary

Adds [Qovery](https://www.qovery.com) to the Partner Skills section. The Qovery Agent Skill teaches Claude how to deploy any application to Kubernetes using Qovery — including codebase analysis, Dockerfile creation, database provisioning, environment variable setup, and deployment via CLI+API or Terraform.

### What the skill does

- Analyzes codebases to detect language, framework, ports, and database needs
- Creates production-ready Dockerfiles for 12+ frameworks (Node.js, Next.js, React, Vite, Python, Go, Java, Ruby, PHP, .NET)
- Provisions databases (container mode for dev, managed for production)
- Sets up environment variables with proper scoping, aliases, and interpolation
- Deploys via Qovery CLI + API or generates complete Terraform manifests
- Watches deployments and auto-fixes configuration issues
- Handles Helm charts, Terraform modules, lifecycle jobs, and cron jobs

### Links

- Skill repository: https://github.com/Qovery/qovery-skills
- Install: `curl -fsSL https://skill.qovery.com/install.sh | bash`
- Documentation: https://www.qovery.com/docs/getting-started/quickstart/ai-agent

## Change to README.md

Add to the "Partner Skills" section:

```markdown
## Partner Skills

Skills are a great way to teach Claude how to get better at using specific pieces of software. As we see awesome example skills from partners, we may highlight some of them here:

- **Notion** - [Notion Skills for Claude](https://www.notion.so/notiondevs/Notion-Skills-for-Claude-28da4445d27180c7af1df7d8615723d0)
- **Qovery** - [Deploy any application to Kubernetes](https://github.com/Qovery/qovery-skills) — Analyzes your codebase, creates Dockerfiles, provisions databases, and deploys via CLI+API or Terraform. Install: `curl -fsSL https://skill.qovery.com/install.sh | bash`
```
