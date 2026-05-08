# CLAUDE.md

Eight Agent Skills for the Qovery platform, distributed via `curl https://skill.qovery.com/install.sh | bash`. Each skill is a self-contained directory consumed at runtime by AI coding agents. The skills follow [Anthropic Agent Skills best practices](https://docs.anthropic.com/en/docs/agents-and-tools/agent-skills/best-practices) — in particular **progressive disclosure**.

## Layout

```
_shared/                   AUTHORING source for boilerplate copied into every skill
scripts/sync-shared.sh     Copy _shared/* into each skill's reference/
evals/qovery-<skill>.json  ≥3 representative scenarios per skill
qovery-<skill>/
  ├── SKILL.md             Navigation/overview, ≤500 lines (Level 1 + 2)
  ├── commands/            Slash commands (Claude Code-specific)
  ├── reference/           Phase files, loaded on demand (Level 3)
  ├── templates/           Files the skill cp's into the user's repo
  └── examples/            Long-form walkthroughs (optional)
```

`qovery-deploy/` is the canonical example — when in doubt, mirror its structure.

## Core invariants

YOU MUST honour these every time. They are what makes the skills usable.

1. **`SKILL.md` ≤ 500 lines.** It loads into context whenever the skill triggers. Everything else loads on demand.
2. **One-level-deep references only.** `SKILL.md` → `reference/foo.md` is fine. `SKILL.md` → `a.md` → `b.md` is not — the agent may stop at level 1.
3. **Code longer than ~30 lines lives in `templates/`**, not in a markdown code block. The agent `cp`s the file instead of regenerating it.
4. **Descriptions are 3rd person** and end with a `Use when …` trailer. No "Deploy your codebase…" or "I can…".
5. **No `You are an expert at …` opener.** That belongs to the agent's system prompt, not skill content.
6. **No time-sensitive content** ("as of 2025", "after Thursday"). Pricing tables include source attribution + verify-the-source warnings.
7. **No `Co-Authored-By: Claude` trailer** in commit messages.

## Quick verification commands

Run these after any change to catch regressions:

```bash
# Every SKILL.md under 500 lines
for f in qovery-*/SKILL.md; do l=$(wc -l < "$f"); [ "$l" -gt 500 ] && echo "❌ $f: $l"; done

# Every internal link in main SKILL.md resolves
for s in qovery-*/SKILL.md; do d=$(dirname "$s"); \
  grep -oE '\((reference|templates|examples)/[^)]+\)' "$s" | tr -d '()' | \
  while read l; do [ -f "$d/$l" ] || echo "❌ $s → $l"; done; done

# No leaked anti-patterns (2nd-person openers, "as of <year>", AI co-author trailers)
out=$(grep -rEn "^You are an expert|as of [0-9]{4}|Co-Authored-By: Claude" qovery-*/SKILL.md _shared/ 2>/dev/null); [ -z "$out" ] && echo "✓ clean" || echo "$out"

# Smoke-test the installer end-to-end (uses local repo as source)
HOME=$(mktemp -d) ./install.sh --global | tail -3
```

## Common changes

### Update boilerplate shared across skills

Common content (Console URL detection, auth flow, pricing) is authored once under `_shared/` and **copied** into each skill's `reference/` — skills are independent dirs at runtime, no cross-references.

```bash
$EDITOR _shared/console-url-detection.md   # 1. edit source
./scripts/sync-shared.sh                   # 2. propagate
git add _shared scripts qovery-*/reference # 3. commit BOTH source + synced copies
```

The sync map is at the top of `scripts/sync-shared.sh`. Add an entry there if a new file needs to ship into more skills.

### Add a phase to an existing skill

1. Write `<skill>/reference/phase<N>-<topic>.md`. Self-contained — no chained links.
2. Add one row to the navigation table in `<skill>/SKILL.md`. Don't paste the content into the main file.
3. If the phase has its own steps, add a checkbox to the workflow checklist in `SKILL.md`.
4. Add a scenario to `evals/<skill>.json` that exercises it.

### Extract embedded code into a template

When a code block in `SKILL.md` or a reference file is > ~30 lines:

1. Move it to `<skill>/templates/<path>` keeping a sensible filename.
2. Replace the block with a one-liner pointer that states **execution intent**:
   - *"Run `templates/scripts/foo.sh`"* (execute)
   - *"Use `templates/Dockerfile.python` as-is, adapt CMD"* (read & copy)

### Add a new skill

1. Create `qovery-<name>/{SKILL.md, commands/qovery-<name>.md, reference/}`.
2. Add `qovery-<name>` to the `SKILLS=(...)` arrays in **both** `install.sh` and `local-install.sh`.
3. Add the skill row to `README.md` and the trigger-prompts list there.
4. Add it to the sync map in `scripts/sync-shared.sh` if it needs shared content, then run the script.
5. Add `evals/qovery-<name>.json` with ≥ 3 scenarios.
6. Frontmatter: `name` lowercase-hyphens (≤ 64 chars, no `anthropic` / `claude`); `description` 3rd person + `Use when …` trailer (≤ 1 024 chars, but stay well under).
7. **User-Agent:** All `curl` commands targeting `api.qovery.com` in templates/scripts MUST include `-H "User-Agent: QoverySkill/<skill-name> (version:$SKILLS_VERSION; https://github.com/Qovery/qovery-skills)"`. The agent applies this rule at runtime for reference-file examples (via `_shared/auth.md` directive) — but templates and scripts that run independently must include it explicitly. For `fetch()`-based code, add the `User-Agent` header to the request options.

### Refactor a SKILL.md that exceeded 500 lines

The fix is always to extract:

1. Slice cohesive sections to `reference/<topic>.md` with `sed -n 'A,Bp'`.
2. Replace each in `SKILL.md` with a one-row entry in the navigation table.
3. Keep workflow checklists, decision trees, quick references **in main** — they are the navigation surface the agent re-reads.

## Commits & PRs

- Conventional Commits (`feat:` / `fix:` / `refactor:` / `docs:` / `test:` / `chore:`).
- IMPORTANT: never add `Co-Authored-By: Claude` (or any AI trailer) to commit messages.
- PR title < 70 chars. Body: summary, before/after numbers when size-relevant, test plan checklist, reviewer notes.
- Branch from `main`, push to a topic branch, open a PR. No direct pushes to `main`.

## Known constraints

- **Skills do not cross-reference at runtime.** Each is installed as an independent directory. Shared content is copied via `scripts/sync-shared.sh`.
- **Slash command files use Claude-Code-specific shell injection (`!\`cmd\``).** Other tools read them as text but won't execute the injection.
- **Markdown headings**: `#` reserved for the skill title, `##` for top-level sections, `###` for sub-sections. `####` in main `SKILL.md` almost always means the content should be in `reference/` instead.
- **Forward slashes in all paths**, even though some users run Windows.
