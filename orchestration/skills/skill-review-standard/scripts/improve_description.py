#!/usr/bin/env python3
"""Use Claude to improve a skill's YAML description for better trigger precision.

Reads the current SKILL.md, collects descriptions from all sibling skills,
and asks claude -p to produce an improved description with better positive
and negative triggers and less overlap with other installed skills.

Targets Python 3.8+ with no external dependencies beyond stdlib.
"""

import argparse
import json
import os
import re
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)
from utils import find_skill_dirs, parse_skill_md


IMPROVE_PROMPT_TEMPLATE = """\
You are a Claude Code plugin expert. Your task is to improve the description
field of a skill's YAML frontmatter so that it triggers more precisely.

Here is the current skill:
  Name: {name}
  Description: {description}

Here are the descriptions of all OTHER installed skills (the improved
description must not overlap with these):
{other_skills}

Requirements for the improved description:
1. Catches all prompts that genuinely need this skill (good positive triggers).
2. Explicitly rejects prompts that belong to other skills (clear negative triggers
   with "Do NOT use when/for" clauses).
3. Avoids vague phrases like "general coding" that overlap with many skills.
4. Keeps the description to 1-3 sentences plus a "Do NOT use" clause.
5. Uses concrete keywords a user would actually type.

{context_section}

Respond with ONLY the improved description string — no YAML markers, no
field name, no quotes around it, no explanation. Just the raw description text.
"""


def find_plugin_root(skill_dir):
    """Walk up from a skill directory to find the plugin root.

    The plugin root is the directory that contains skills/.
    """
    current = os.path.abspath(skill_dir)
    while current != "/":
        parent = os.path.dirname(current)
        if os.path.basename(current) == "skills":
            return parent
        # Check if current dir contains skills/
        if os.path.isdir(os.path.join(current, "skills")):
            return current
        current = parent
    return None


def collect_other_descriptions(plugin_root, exclude_name):
    """Collect name: description pairs for all skills except the target."""
    lines = []
    for skill_dir in find_skill_dirs(plugin_root):
        skill_md = os.path.join(skill_dir, "SKILL.md")
        parsed = parse_skill_md(skill_md)
        if parsed and parsed["name"] != exclude_name:
            lines.append(f"  - {parsed['name']}: {parsed['description']}")
    return "\n".join(lines) if lines else "  (no other skills found)"


def run_claude(prompt, timeout=120):
    """Invoke claude -p and return stdout."""
    try:
        result = subprocess.run(
            ["claude", "-p", prompt],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.stdout.strip() if result.returncode == 0 else None
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None


def update_skill_md(skill_md_path, new_description):
    """Update the description field in a SKILL.md file's frontmatter.

    Preserves all other frontmatter fields and the body content.
    """
    with open(skill_md_path, encoding="utf-8") as f:
        text = f.read()

    # Match the frontmatter block
    fm_match = re.match(r"^(---\s*\n)(.*?)(\n---\s*\n)(.*)", text, re.DOTALL)
    if not fm_match:
        print("Error: could not find frontmatter in SKILL.md", file=sys.stderr)
        return False

    prefix = fm_match.group(1)
    frontmatter = fm_match.group(2)
    separator = fm_match.group(3)
    body = fm_match.group(4)

    # Replace the description field. Handle both quoted and unquoted values.
    # Match from 'description:' to the next top-level field or end of frontmatter.
    new_desc_escaped = new_description.replace('"', '\\"')
    new_desc_line = 'description: "' + new_desc_escaped + '"'

    # Pattern to match existing description (possibly multi-line quoted)
    desc_pattern = r'description:\s*(?:"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|[^\n]*)'
    updated_fm, count = re.subn(desc_pattern, new_desc_line, frontmatter, count=1)

    if count == 0:
        print(
            "Error: could not find description field in frontmatter",
            file=sys.stderr,
        )
        return False

    new_text = prefix + updated_fm + separator + body
    with open(skill_md_path, "w", encoding="utf-8") as f:
        f.write(new_text)

    return True


def main():
    parser = argparse.ArgumentParser(
        description="Use Claude to improve a skill's description for trigger precision"
    )
    parser.add_argument(
        "--skill-dir",
        required=True,
        help="Path to the skill directory containing SKILL.md",
    )
    parser.add_argument(
        "--context",
        default=None,
        help="Additional context about what the skill should trigger on",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the improved description without modifying the file",
    )
    args = parser.parse_args()

    # Parse target skill
    skill_md_path = os.path.join(args.skill_dir, "SKILL.md")
    parsed = parse_skill_md(skill_md_path)
    if parsed is None:
        print(f"Error: could not parse {skill_md_path}", file=sys.stderr)
        sys.exit(1)

    # Find plugin root and collect other descriptions
    plugin_root = find_plugin_root(args.skill_dir)
    if plugin_root is None:
        print(
            "Warning: could not find plugin root. "
            "Other skill descriptions will not be available.",
            file=sys.stderr,
        )
        other_descriptions = "  (plugin root not found)"
    else:
        other_descriptions = collect_other_descriptions(plugin_root, parsed["name"])

    # Build context section
    context_section = ""
    if args.context:
        context_section = (
            f"Additional context from the user about intended triggers:\n"
            f"  {args.context}\n"
        )

    # Build and send the prompt
    prompt = IMPROVE_PROMPT_TEMPLATE.format(
        name=parsed["name"],
        description=parsed["description"],
        other_skills=other_descriptions,
        context_section=context_section,
    )

    print("Asking Claude for an improved description...", file=sys.stderr)
    improved = run_claude(prompt)

    if not improved:
        print("Error: failed to get response from claude", file=sys.stderr)
        sys.exit(1)

    # Clean up any accidental quoting the model might add
    if improved.startswith('"') and improved.endswith('"'):
        improved = improved[1:-1]

    print(file=sys.stderr)
    print("Current description:", file=sys.stderr)
    print(f"  {parsed['description']}", file=sys.stderr)
    print(file=sys.stderr)
    print("Improved description:", file=sys.stderr)
    print(f"  {improved}", file=sys.stderr)
    print(file=sys.stderr)

    if args.dry_run:
        print("(dry run — no changes written)", file=sys.stderr)
        # Print the improved description to stdout for piping
        print(improved)
    else:
        confirm = input("Apply this description to SKILL.md? [y/N] ").strip().lower()
        if confirm in ("y", "yes"):
            if update_skill_md(skill_md_path, improved):
                print(f"Updated {skill_md_path}", file=sys.stderr)
            else:
                print("Failed to update SKILL.md", file=sys.stderr)
                sys.exit(1)
        else:
            print("No changes made.", file=sys.stderr)


if __name__ == "__main__":
    main()
