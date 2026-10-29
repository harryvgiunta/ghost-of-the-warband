# Agent skills

A skill is a page an agent reads **before** touching the surface it covers. It is
not a tutorial and not a changelog: it is the set of contracts, traps and
verification steps that are expensive to rediscover and easy to get wrong.

| Item | Rule |
| --- | --- |
| Location | `.omp/skills/<name>/SKILL.md` — one directory per skill, nothing beside it |
| Loaded as | `skill://<name>` (the harness matches the `description`, then reads the body) |
| Authority | The body is authoritative for the agent that loads it, and **the code is authoritative for the body** — a skill that contradicts the repository is a bug in the skill |

## Frontmatter

```yaml
---
name: <same as the directory>
description: <one sentence that says when to use it, in the words a task will contain>
allowed-tools: Read, Glob, Grep      # only on skills imported from agent-skills-hub
---
```

- **`name`** must equal the directory name (`check_skills.py` fails otherwise). A
  skill that has drifted from its directory is never matched.
- **`description`** is the whole routing decision: name the nouns a task will
  actually contain ("dagger", "PBR texture", "ENet", "Escape menu"), not the
  craft ("good practices"). A description that could belong to any repository
  will be loaded at the wrong moment or not at all.
- **`allowed-tools`** exists so an upstream skill keeps its published contract.
  A local skill leaves it out: the repository's skills describe work, they do not
  sandbox the harness.

## Adding a skill

1. Pick the surface, not the technology. Two skills that fire on the same files
   are one skill with two sections.
2. `mkdir .omp/skills/<name>` and write `SKILL.md`: frontmatter, then **contracts
   first** — the ownership map, the invariants, the traps that cost a day — then
   a verification section with the exact command.
3. Every path in the body is repository-relative (`scripts/…`, `tests/…`,
   `docs/…`), because the skill is not loaded from its own directory.
4. Long reference material belongs in `docs/<topic>.md`; the skill says what to
   do and links to it. Duplicating both is how they drift apart.
5. Name the test that covers the surface. A skill that asserts a contract without
   naming anything that checks it is a claim, not a contract.
6. Add the row to the index below, then run `python tools/check_skills.py`.

## Modifying a skill

- **Edit in place.** Never fork a second skill for a subject an existing one
  covers; a new file is a new routing decision and the two will disagree.
- When a change supersedes a contract the skill records, change the skill in the
  **same commit** as the code. The repository's own rule: a skill that documents
  the old input path or the old signal name is worse than no skill.
- Delete, do not accumulate. Obsolete rows, dead symbols and old keybindings go
  when the code that needed them goes.
- An imported skill from `agent-skills-hub` keeps its body **verbatim**; the
  repository's own deviations and notes go in the local skill that pairs with
  it, never inside the imported text.

## Index

| Skill | Load it when |
| --- | --- |
| `ironwood-archer` | modifying, debugging, launching or verifying this repository: the title, the town, the warband campaign, combat, animation, HUD, netcode |
| `ironwood-assets` | finding, sourcing, modelling, texturing, baking, exporting or importing 3D assets and PBR materials |
| `ironwood-creatures` | creating, rigging, skinning or animating characters and creatures, retargeting clips, fixing foot contact or size variants |
| `game-audio` | game audio principles: categories, mix hierarchy, music states, spatialisation (imported from `agent-skills-hub`; the repository's own contract is `docs/audio.md`) |

## Verification

    python tools/check_skills.py

It checks what can be checked without an LLM: every skill directory has a
`SKILL.md`, the frontmatter parses, `name` matches the directory, `description`
is present and specific enough to be worth a routing decision, and the index
above lists every skill and nothing that is not one. The rest is verified the
way the repository verifies code — by running what the skill names.
