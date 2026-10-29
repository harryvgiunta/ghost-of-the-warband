"""Check the repository's agent skills: shape, frontmatter and the index.

A skill is loaded by its directory name, so a `name:` that disagrees with the
directory, a `description` that cannot route a task, or a skill the index never
mentions are all silent failures - the harness simply stops loading the page the
agent needed. This script makes them loud.

    python tools/check_skills.py

It deliberately checks nothing an LLM is needed for: whether the body is *true*
is verified by the tests the skill names, not by this file.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKILLS = ROOT / ".omp" / "skills"
INDEX = SKILLS / "README.md"

FRONTMATTER = re.compile(r"\A---\r?\n(.*?)\r?\n---\r?\n", re.S)
# A directory name is what the harness matches, so it is the contract.
NAME = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
MIN_DESCRIPTION = 60


def read_frontmatter(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    match = FRONTMATTER.match(text)
    if match is None:
        return {}
    fields: dict[str, str] = {}
    for line in match.group(1).splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if ":" not in line:
            return {}
        key, _, value = line.partition(":")
        fields[key.strip()] = value.strip()
    return fields


def main() -> int:
    problems: list[str] = []
    if not SKILLS.is_dir():
        print(f"missing {SKILLS}")
        return 1

    directories = sorted(p for p in SKILLS.iterdir() if p.is_dir())
    names: list[str] = []
    for directory in directories:
        name = directory.name
        names.append(name)
        if not NAME.match(name):
            problems.append(f"{name}: not a kebab-case skill name")
        page = directory / "SKILL.md"
        if not page.exists():
            problems.append(f"{name}: no SKILL.md")
            continue
        fields = read_frontmatter(page)
        if not fields:
            problems.append(f"{name}: frontmatter missing or unparsable")
            continue
        if fields.get("name") != name:
            problems.append(f"{name}: frontmatter name is {fields.get('name')!r}")
        description = fields.get("description", "")
        if len(description) < MIN_DESCRIPTION:
            problems.append(
                f"{name}: description is {len(description)} chars, too short to route on"
            )
        if not page.read_text(encoding="utf-8").startswith("---\n"):
            problems.append(f"{name}: file does not start with a frontmatter block")

    if not INDEX.exists():
        problems.append("the index (.omp/skills/README.md) is missing")
    else:
        index = INDEX.read_text(encoding="utf-8")
        for name in names:
            if f"`{name}`" not in index:
                problems.append(f"{name}: not listed in the index")
        for mentioned in set(re.findall(r"^\| `([a-z0-9-]+)`", index, re.M)):
            if mentioned not in names:
                problems.append(f"{mentioned}: indexed but there is no such skill")

    for problem in problems:
        print(f"SKILL_PROBLEM  {problem}")
    print(f"skills={len(names)} problems={len(problems)}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
