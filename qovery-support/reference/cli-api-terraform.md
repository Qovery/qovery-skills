# CLI, API and Terraform provider

Covers the commands and calls users ask about most, the API pitfalls behind real incidents, Terraform provider questions, Terraform services, and deploying from CI.

## Contents

- CLI basics
- Commands people ask for most
- `qovery api`: authenticated REST calls without handling tokens
- Advanced settings via the API: read, edit, write the whole object
- Other "an update removed my setting" cases
- Deploying from CI
- Terraform provider
- Terraform services (Terraform run by Qovery)
- Known limits

## CLI basics

- Install and sign in: `qovery auth` (browser) or `qovery auth --headless`. Keep the CLI current with `qovery upgrade`. Token rules are in `reference/auth.md`.
- Context: `qovery context set` is interactive; agents should pass `--organization`, `--project`, `--environment` (or a Console URL) instead.
- `qovery <command> --help` is the source of truth for flags. Do not guess flags.

Docs: <https://www.qovery.com/docs/cli/commands/overview>.

## Commands people ask for most

```bash
qovery status                                                    # status of the services in the context
qovery service list
qovery log --service "<name>"                                    # live logs; --application/--container/--database/--job also exist
qovery environment deployment list --environment "<env>"
qovery environment deployment explain --environment "<env>"      # which stage, service and step failed
qovery service deploy --service "<name>" [--version "<sha-or-tag>"]
qovery environment cancel --environment "<env>" --watch
qovery shell --service "<name>"                                  # needs the Shell permission
qovery port-forward "<service Console URL>" --port 8080:80       # needs the Port-forward permission
qovery list-pods "<service Console URL>"
qovery env import vars.env                                       # bulk import variables from a .env file
qovery cluster list
qovery cluster kubeconfig --cluster-id "<id>" --read-only
qovery cluster upgrade --cluster "<name>" --watch
qovery cluster analysis deprecated-api --cluster-id "<id>"
qovery audit-log export --organization "<org>" --from-date "<ISO-8601 date>"   # who changed what, as CSV
```

## `qovery api`: authenticated REST calls without handling tokens

`qovery api <path>` calls the Qovery API with the CLI's session, so no token reaches the shell or the conversation:

```bash
qovery api organization                                           # GET
qovery api "application/<id>/advancedSettings"                    # GET
qovery api "application/<id>" --method PUT --input - < body.json  # write, body from stdin
qovery api "organization/<id>/project" --field name=web           # small bodies
```

Prefer it over `curl` with a token. When `curl` is unavoidable, follow `reference/auth.md` and send the skill's `User-Agent` header.

API reference: <https://www.qovery.com/docs/api-reference/introduction>.

## Advanced settings via the API: read, edit, write the whole object

**Symptom.** "I changed one advanced setting with the API (or a script, or an agent) and other settings went back to their defaults", sometimes followed by an outage (for example a service account setting reset to empty, so the app lost its cloud permissions).

**Cause.** `PUT /application/{id}/advancedSettings` (and the equivalents for containers, jobs, Helm services and clusters) **replaces the whole object**. Any key left out of the body takes its default value.

**Fix.** Always read, modify, write:

```bash
qovery api "application/<id>/advancedSettings" > settings.json
# edit only the keys you need in settings.json (with jq or by hand)
qovery api "application/<id>/advancedSettings" --method PUT --input - < settings.json
```

For applications, cron jobs, lifecycle jobs and Terraform services, remove every `build.*` key before the PUT: those keys are deprecated in advanced settings, and build resources are changed through `build_settings` on the service itself. Redeploy the service afterwards for the change to apply.

To recover from a reset: compare the current object with what the service needs (the audit log shows the change: `qovery audit-log export`, or the Console audit logs), restore the missing keys with the same read, modify, write sequence, and redeploy.

## Other "an update removed my setting" cases

The same full-replace behavior applies to other objects updated with `PUT`. For example, a `PUT /application/{id}` body without `healthchecks.startup_probe` removes the startup probe. Always start from a `GET` of the current object.

## Deploying from CI

A pattern that works well:
1. Build one image per commit in CI, tagged with the commit SHA (never reuse a tag such as `latest`).
2. Deploy with an explicit version: `qovery service deploy --service "<name>" --version "<sha>"`, or deploy the environment so deployment stages keep their order (lifecycle jobs for migrations in an earlier stage).
3. Roll back by deploying the previous SHA.
4. Give CI a scoped token, not a personal one. For least privilege, hand off to `qovery-policy-token`.

Guides: <https://www.qovery.com/docs/configuration/integrations/ci-cd/github-actions>, <https://www.qovery.com/docs/configuration/integrations/ci-cd/gitlab-ci>.

## Terraform provider

- Provider `qovery/qovery`, pin it with `version = "~> 1.0"`. It authenticates with an API token (the `token` argument or `QOVERY_API_TOKEN`); this is the one case that needs a long-lived token, which the user creates themselves. Docs: <https://www.qovery.com/docs/terraform-provider/overview>.
- **New managed databases**: use the blueprint resources rather than a `qovery_database` in managed mode, which is the legacy path. See `reference/databases.md`.
- **Plan always shows changes**: usually a value changed outside Terraform (Console edits, aliases Qovery creates for job and blueprint outputs, or route tables), or a field the API normalizes. Find the drifting attribute in the plan, then either move that setting into Terraform or stop editing it outside Terraform. Recent provider versions leave Qovery-created output aliases out of the state; upgrade the provider if `apply` keeps deleting them.
- **Git URL not recognized**: the provider needs a URL from a supported Git provider (GitHub, GitLab, Bitbucket).
- To generate Terraform from an existing setup, hand off to `qovery-terraform`.

## Terraform services (Terraform run by Qovery)

Qovery can run your Terraform code as a service of the environment (to create S3 buckets, queues, IAM roles) and expose its outputs as variables.

- **Files missing during the run** (`.tf` or `.tfvars` not found): the service is built from the repository like an image, and a `.dockerignore` at the build root can exclude the Terraform folder. Check the `.dockerignore`.
- **Outputs**: each output becomes a `QOVERY_OUTPUT_TERRAFORM_...` variable plus an alias with the output's name. See `reference/secrets-env.md`.
- **Preview environments**: a Terraform service cloned into a preview creates or destroys real cloud resources. Make sure each preview gets isolated resources, or exclude the service from previews.

Docs: <https://www.qovery.com/docs/configuration/terraform>.

## Known limits

- The API has no partial update for advanced settings; always send the full object.
- `qovery context set` and `qovery token` are interactive: agents pass explicit flags or Console URLs.
- There is no CLI command that creates a long-lived token for an agent; use `qovery auth` sessions or a policy token.
