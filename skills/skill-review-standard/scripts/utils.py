#!/usr/bin/env python3
"""Shared utilities for skill eval benchmarking.

Library module — no CLI. Provides SKILL.md parsing, skill directory
discovery, and trigger extraction used by the other eval scripts.

Targets Python 3.8+ with no external dependencies.
"""

import os
import re


def parse_skill_md(path):
    """Read a SKILL.md file and parse its YAML frontmatter.

    Returns a dict with:
        name        — from frontmatter
        description — from frontmatter
        content     — the markdown body after the closing ---
        raw         — the entire file contents

    Returns None if the file doesn't exist or has no valid frontmatter.
    """
    if not os.path.isfile(path):
        return None

    with open(path, encoding="utf-8") as f:
        text = f.read()

    # Frontmatter lives between the first pair of --- markers.
    match = re.match(r"^---\s*\n(.*?)\n---\s*\n(.*)", text, re.DOTALL)
    if not match:
        return None

    frontmatter_text = match.group(1)
    body = match.group(2)

    # Minimal YAML parsing — handles the two fields we care about.
    # Full YAML would require PyYAML which is not in stdlib.
    name = _extract_yaml_field(frontmatter_text, "name")
    description = _extract_yaml_field(frontmatter_text, "description")

    return {
        "name": name or "",
        "description": description or "",
        "content": body,
        "raw": text,
    }


def _extract_yaml_field(frontmatter, field):
    """Extract a single scalar field from simple YAML frontmatter.

    Handles both quoted and unquoted values, including multi-line quoted
    strings that span several lines.
    """
    # Try quoted value first (single or double quotes, possibly multi-line)
    pattern = r'^' + re.escape(field) + r':\s*(["\'])(.*?)\1'
    m = re.search(pattern, frontmatter, re.MULTILINE | re.DOTALL)
    if m:
        return m.group(2).strip()

    # Unquoted value — take everything to end of line
    pattern = r'^' + re.escape(field) + r':\s*(.+)$'
    m = re.search(pattern, frontmatter, re.MULTILINE)
    if m:
        return m.group(1).strip()

    return None


def find_skill_dirs(plugin_root):
    """Find all skill directories under skills/ that contain a SKILL.md.

    Args:
        plugin_root: path to the plugin root (the directory containing skills/)

    Returns:
        List of absolute paths to skill directories, sorted by name.
    """
    skills_dir = os.path.join(plugin_root, "skills")
    if not os.path.isdir(skills_dir):
        return []

    result = []
    for entry in sorted(os.listdir(skills_dir)):
        skill_dir = os.path.join(skills_dir, entry)
        skill_md = os.path.join(skill_dir, "SKILL.md")
        if os.path.isdir(skill_dir) and os.path.isfile(skill_md):
            result.append(skill_dir)

    return result


def extract_triggers(description):
    """Split a skill description into positive and negative trigger phrases.

    Negative triggers are phrases after keywords like "Do NOT use",
    "Don't use when", "Not for", etc. Everything else is positive.

    Returns:
        {
            "positive": [str, ...],
            "negative": [str, ...],
        }
    """
    if not description:
        return {"positive": [], "negative": []}

    # Split on negative-trigger markers
    negative_patterns = [
        r"Do NOT use[^.]*?[.:]",
        r"Don't use[^.]*?[.:]",
        r"do not use[^.]*?[.:]",
        r"Not for[^.]*?[.:]",
        r"not for[^.]*?[.:]",
    ]

    negative_phrases = []
    remaining = description

    for pattern in negative_patterns:
        for m in re.finditer(pattern, description, re.IGNORECASE):
            span = m.group(0)
            # Extract the comma/semicolon separated items after the marker
            after_colon = span.split(":", 1)[-1] if ":" in span else span
            # Also capture anything following the matched sentence that lists
            # specifics (the rest until next sentence boundary)
            start = m.end()
            rest = description[start:]
            # Grab up to the next sentence-ending period or the end
            rest_match = re.match(r"([^.]+\.?)", rest)
            combined = after_colon
            if rest_match:
                combined += " " + rest_match.group(1)
            # Split into individual phrases on commas and semicolons
            items = re.split(r"[,;]", combined)
            for item in items:
                cleaned = item.strip().rstrip(".")
                if cleaned and len(cleaned) > 2:
                    negative_phrases.append(cleaned)

    # For positive triggers, extract meaningful phrases from the description
    # before the negative section.
    neg_start = len(description)
    for pattern in negative_patterns:
        m = re.search(pattern, description, re.IGNORECASE)
        if m and m.start() < neg_start:
            neg_start = m.start()

    positive_text = description[:neg_start]

    # Extract phrases that look like trigger keywords
    # Split on common delimiters and quoted phrases
    positive_phrases = []
    # Look for quoted phrases first
    for m in re.finditer(r"'([^']+)'", positive_text):
        positive_phrases.append(m.group(1).strip())

    # Then split remaining text on commas/semicolons within parenthetical
    # lists or "or" conjunctions
    for m in re.finditer(r"\(([^)]+)\)", positive_text):
        items = re.split(r"[,;]\s*|\s+or\s+", m.group(1))
        for item in items:
            cleaned = item.strip().rstrip(".")
            if cleaned and len(cleaned) > 2:
                positive_phrases.append(cleaned)

    # If we didn't find structured triggers, use sentence fragments
    if not positive_phrases:
        sentences = re.split(r"\.\s+", positive_text)
        for s in sentences:
            cleaned = s.strip().rstrip(".")
            if cleaned and len(cleaned) > 5:
                positive_phrases.append(cleaned)

    return {
        "positive": positive_phrases,
        "negative": negative_phrases,
    }
