# CLAUDE.md

Guidance for Claude Code (and any other AI coding assistant) when working in this repository.

## What this repo is

Eight Agent Skills for the Qovery platform, distributed via [agentskills.io](https://agentskills.io) and installed by users via `curl https://skill.qovery.com/install.sh | bash`. Each skill is a self-contained directory consumed at runtime by AI coding agents (Claude Code, OpenCode, Cursor, Gemini CLI, etc.).

The skills follow the [Anthropic Agent Skills best practices](https://docs.anthropic.com/en/docs/agents-and-tools/agent-skills/best-practices), in particular **progressive disclosure**: each `SKILL.md` is a short navigation file (target ≤ 500 lines) that points to phase-specific reference files loaded on demand.

## Layout

```
qovery-skills/
├── _shared/                       # AUTHORING source for boilerplate copied into every skill
│   ├── console-url-detection.md   # Extract IDs from a Qovery Console URL
│   ├── auth.md                    # API token + JWT fallback chain
│   └── pricing/{aws,gcp,azure,scaleway}.md
├── scripts/
│   └── sync-shared.sh             # Sync _shared/* → each skill's reference/
├── evals/
│   ├── README.md
│   └── qovery-<skill>.json        # ≥3 representative scenarios per skill
├── install.sh                     # Tarball-based install (used by curl|bash)
├── local-install.sh               # Symlink-based install for development
├── README.md                      # User-facing documentation
└── qovery-<skill>/                # One directory per skill
    ├── SKILL.md                   # Navigation/overview, ≤500 lines
    ├── commands/<skill>.md        # Slash command (Claude Code-specific)
    ├── reference/                 # Phase files loaded on demand
    │   ├── auth.md                # Synced from _shared/auth.md
    │   ├── console-url-detection.md
    │   └── phase<N>-<topic>.md
    ├── templates/                 # Files the skill copies into the user's repo
    │   └── ... (Dockerfiles, scripts, Terraform, .ts, etc.)
    └── examples/                  # Long-form walkthroughs (optional)
```

## Core invariants

These are non-negotiable — break them and the skills regress against the architecture.

1. **`SKILL.md` stays ≤ 500 lines.** It is loaded into the agent's context whenever the skill triggers; everything else only loads when the agent reads it.
2. **Reference files are linked one level deep from `SKILL.md`.** Avoid chained references (`SKILL.md` → `a.md` → `b.md`) — the agent may stop at level 1.
3. **Code longer than ~30 lines goes into `templates/`**, not into a markdown code block. The agent then `cp`s the file instead of regenerating it from prompt context.
4. **Descriptions are written in 3rd person** ("Deploys an application…", not "Deploy your application…" / "I can deploy…"). They include a "Use when …" trailer to disambiguate from sibling skills.
5. **No `You are an expert at …` opener** in the body — that belongs to the agent's system prompt, not skill content.
6. **No time-sensitive content** ("as of 2025", "after Thursday"). Pricing tables include source attribution + "verify before quoting" warnings.
7. **No AI co-author trailers** in commit messages.

If you find yourself wanting to break one of these, push back: the answer is almost always to extract content into `reference/` or `templates/`.

## How to make common changes

### Add a new phase to an existing skill

1. Write the phase content as a self-contained `<skill>/reference/phase<N>-<topic>.md`.
2. Add one row to the navigation table in `<skill>/SKILL.md`. Do not paste the content into `SKILL.md`.
3. If the phase has its own checklist, add a checkbox to the workflow checklist in `SKILL.md`.
4. Add at least one new scenario to `evals/<skill>.json` that exercises the new phase.

### Update content shared across all skills

Common content (Console URL detection, auth flow, pricing tables) is authored once under `_shared/`, then synced into each skill's `reference/`. The skills can't cross-reference at runtime because each is installed as an independent directory.

```bash
# 1. Edit the source
$EDITOR _shared/console-url-detection.md

# 2. Sync into each skill that uses it
./scripts/sync-shared.sh

# 3. Commit BOTH the source change AND the synced copies
git add _shared scripts qovery-*/reference
git commit -m "docs(shared): clarify Console URL extraction for new-console.qovery.com"
```

The sync map is at the top of `scripts/sync-shared.sh`. Add an entry there if a new file needs to ship into more skills.

### Add a new code template

When a skill currently embeds a code block (Dockerfile, shell script, Terraform module, TypeScript source) longer than ~30 lines, extract it:

1. Move the content out of `SKILL.md` (or out of the relevant `reference/*.md`) into `<skill>/templates/<path>`. Preserve the actual filename so the agent's `cp` command writes a sensibly-named file in the user's repo.
2. In the markdown that previously contained the code, replace the block with a short pointer:
   ```md
   Use `templates/scripts/provision-builder.sh` as-is. Adapt the `BUILDER_NAME`
   and `BUILDER_EMAIL` variables at the top.
   ```
3. State **execution intent** clearly: "Run X" vs "See X for the algorithm". Best practices:
   - Execute scripts (don't have the agent regenerate them)
   - Read templates (the agent copies them, then adapts)

### Add a new skill

1. Create the directory `qovery-<name>/` with the canonical layout (`SKILL.md`, `commands/qovery-<name>.md`, `reference/`).
2. Sync shared content into it: edit `scripts/sync-shared.sh` to include the new skill in the sync list, then run it.
3. Add the skill to the `SKILLS=(...)` array in **both** `install.sh` and `local-install.sh`.
4. Add the skill to the table in `README.md`.
5. Add `evals/qovery-<name>.json` with ≥ 3 scenarios.
6. Frontmatter requirements: `name` (lowercase + hyphens, ≤ 64 chars, no "anthropic" / "claude"), `description` (3rd person, "Use when …" trailer, ≤ 1024 chars).

### Refactor a SKILL.md that has grown over 500 lines

Almost always the fix is to extract material into `reference/`:

1. Identify cohesive sections (a phase, a long table, a multi-step workflow).
2. Slice each into `<skill>/reference/<topic>.md` with `sed -n 'A,Bp'`.
3. Replace the section in `SKILL.md` with a one-line pointer in the navigation table.
4. Keep workflow checklists, decision trees, and quick references **in main** — they are the navigation surface the agent re-reads.

A line count check is a useful pre-commit sanity check:
```bash
for f in qovery-*/SKILL.md; do
  lines=$(wc -l < "$f")
  [ "$lines" -gt 500 ] && echo "❌ $f exceeds 500 lines: $lines"
done
```

## Install scripts

### `install.sh` (production)

Used by end users via `curl | bash`. Downloads a tarball of the repo from `https://codeload.github.com/Qovery/qovery-skills/tar.gz/refs/heads/main`, then for each skill copies the entire directory tree (everything except `commands/`, which goes into the agent's `commands/` dir).

If you add a new top-level dir to a skill (e.g. `examples/`, `evals/`), `install.sh` picks it up automatically — no install.sh change needed.

### `local-install.sh` (development)

Symlinks each skill directory from the working repo into the install targets. Edits in the repo are instantly reflected — re-install only needed when adding a *new* skill.

```bash
./local-install.sh --global    # default — symlink for all projects
./local-install.sh --project   # only the current project dir
./local-install.sh --uninstall # remove all symlinks
```

## Evals

`evals/<skill>.json` files document representative scenarios as observable assertions (each item asserts an action or output, not internal reasoning). There is no built-in runner — they're authored for whatever harness the team chooses.

Authoring guidelines:
- ≥ 3 scenarios per skill
- Cover the **golden path**, **a common variant**, and **an edge case**
- Use realistic user phrasings (copy from real conversations when possible)
- List the **minimum** required actions — agents may legitimately add more

When fixing a bug or adding a feature, add the case that exposed the problem to the relevant `evals/<skill>.json` so it doesn't regress.

## Commits & PRs

- **Branch from `main`**, push to a topic branch, open a PR. Direct pushes to `main` are not the workflow.
- **No `Co-Authored-By: Claude` trailers** in commit messages.
- **Commit messages** follow Conventional Commits (`feat:` / `fix:` / `refactor:` / `docs:` / `test:` / `chore:`). Reference issue or PR numbers when applicable.
- **PR titles** are short (< 70 chars). Use the body for detail.
- **PR bodies** include: a one-paragraph summary, before/after numbers if size-relevant, a test plan checklist, and notes for reviewers if the diff is large or mechanical.

## Style

- All file paths use forward slashes (`reference/foo.md`), even though some users will run on Windows.
- Markdown headings: `#` reserved for the skill title, `##` for top-level sections, `###` for sub-sections. Avoid `####` in main `SKILL.md` — it usually signals the section should be in `reference/` instead.
- Use absolute URLs in reference links (`https://www.qovery.com/docs/...`) so they work when the file is read in any tool.
- Tables use the standard pipe syntax. Keep them narrow (< 120 chars per line) so they render in editors and on GitHub.

## Known constraints

- **No automated cross-skill sync at runtime.** Skills are installed as independent directories. Common content lives under `_shared/` and is **copied** into each skill via `scripts/sync-shared.sh` at authoring time.
- **Slash commands use Claude Code-specific shell injection** (`!\`command\``) in their `commands/<name>.md` files. Other agent tools may not execute the injected commands, but should still read the rest of the file as plain text.
- **Skills can include up to 1 024 characters in `description`** (per Anthropic spec). All current descriptions stay well under that — if you push a description close to the limit, the agent's discovery quality drops because too much metadata is loaded upfront.
