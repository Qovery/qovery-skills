---
description: Deploy the current project to Kubernetes using Qovery
---

Deploy the current project to Kubernetes using Qovery.

If arguments are provided, use them as context:
- `$ARGUMENTS` — application name, Qovery Console URL, or additional instructions

Analyze the codebase to detect the language, framework, and services. Follow the
qovery-deploy skill to gather requirements, create Dockerfiles if needed, and deploy.

Project files detected:
!`ls package.json go.mod requirements.txt pyproject.toml Pipfile pom.xml build.gradle build.gradle.kts Gemfile composer.json *.csproj *.sln Dockerfile docker-compose.yml docker-compose.yaml .env.example Chart.yaml *.tf 2>/dev/null || echo "no known project files found"`
Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Git remote: !`git remote get-url origin 2>/dev/null || echo "unknown"`
