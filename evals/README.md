# Qovery skills — evaluations

Each `*.json` file is a self-contained evaluation: a user query, optional input
files, and the behavior the skill is expected to produce. Evaluations are the
source of truth for whether a skill change improves or regresses real-world
performance.

## Format

```json
{
  "skills": ["<skill-name>"],
  "query": "Natural-language user request",
  "files": [],
  "expected_behavior": [
    "Concrete observable behavior 1",
    "Concrete observable behavior 2"
  ]
}
```

`expected_behavior` should be **observable** (asserts about the agent's
actions or output) rather than internal (asserts about reasoning). Each item
should be testable independently.

## Running evaluations

There is no built-in runner — these scenarios are designed to be plugged into
whatever harness the maintainer prefers (e.g. an internal eval framework that
spawns the skill against a real or mocked Qovery API).

The minimum manual check: pick a representative fresh agent session, paste the
`query`, and verify each `expected_behavior` item.

## Authoring guidelines

- Aim for at least 3 scenarios per skill.
- Cover the **golden path**, **a common variant**, and **an edge case**.
- Keep queries realistic — copy real user phrasings rather than inventing them.
- When verifying API calls, list the *minimum* required calls — agents may add
  more steps and still be correct.
