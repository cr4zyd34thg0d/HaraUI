#!/usr/bin/env python3
"""Generate categorized release notes from commit subjects on stdin."""
import os
import re
import sys
from collections import OrderedDict


def normalize_subject(raw: str) -> str:
    cleaned = raw.strip()
    cleaned = re.sub(r"^[A-Za-z]+(\([^)]+\))?!?:\s*", "", cleaned)
    if not cleaned:
        cleaned = raw.strip()
    cleaned = re.sub(r"\s+", " ", cleaned)
    if cleaned:
        cleaned = cleaned[0].upper() + cleaned[1:]
    return cleaned


def classify(lower_subject: str) -> str:
    if any(k in lower_subject for k in ("readme", "docs", "changelog", "agents.md")):
        return "Documentation"
    if any(k in lower_subject for k in ("ci:", "release", "tag", "artifact", "packager", "curseforge", "workflow")):
        return "Release Pipeline"
    if any(k in lower_subject for k in ("currency", "transfer", "taint", "tokenui")):
        return "Currency Transfer"
    if any(k in lower_subject for k in ("friendly", "nameplate", "platynator")):
        return "Friendly Nameplates"
    if any(k in lower_subject for k in ("rotation helper", "rotation")):
        return "Rotation Helper"
    if any(k in lower_subject for k in ("xp", "cast", "loot", "summon", "minimap", "tracked bars", "game menu", "tooltip")):
        return "Core UI Modules"
    if any(
        k in lower_subject
        for k in (
            "charsheet",
            "character sheet",
            "mythic",
            "vault",
            "gear cluster",
            "stat cluster",
            "equipment",
            "title row",
            "title click",
            "pane",
            "portal",
            "spec highlight",
            "layout",
        )
    ):
        return "Character Sheet"
    return "Maintenance"


order = [
    "Character Sheet",
    "Currency Transfer",
    "Friendly Nameplates",
    "Rotation Helper",
    "Core UI Modules",
    "Documentation",
    "Release Pipeline",
    "Maintenance",
]

summaries = {
    "Character Sheet": "Refined Character Sheet layout, panel presentation, and interaction polish for smoother day-to-day navigation.",
    "Currency Transfer": "Hardened account-currency transfer behavior to reduce taint risk and keep native Character/Reputation/Currency flows stable.",
    "Friendly Nameplates": "Improved friendly nameplate reliability and option sync behavior in combat and restricted UI states.",
    "Rotation Helper": "Adjusted Rotation Helper behavior and layering so it stays visible when useful without obstructing core UI.",
    "Core UI Modules": "Polished core module behavior across XP/Cast/Loot/Minimap/Game Menu and related utility controls.",
    "Documentation": "Updated player-facing documentation to match the current addon scope, setup path, and feature list.",
    "Release Pipeline": "Improved release automation and publishing consistency across tags, artifacts, and store metadata.",
    "Maintenance": "Applied internal refactors and cleanup work to keep systems stable and easier to evolve.",
}

buckets = OrderedDict((key, []) for key in order)
subjects = [line.strip() for line in sys.stdin if line.strip()]
for subject in subjects:
    clean = normalize_subject(subject)
    feature = classify(subject.lower())
    buckets[feature].append(clean)

lines = ["## Release notes", "", f"Range: {os.environ.get('RANGE_LABEL', 'unknown')}", ""]

if not subjects:
    lines.append("### Feature: Maintenance")
    lines.append("- No user-facing changes recorded in this tag range.")
else:
    for feature in order:
        count = len(buckets[feature])
        if count == 0:
            continue
        noun = "commit" if count == 1 else "commits"
        lines.append(f"### Feature: {feature}")
        lines.append(f"- {summaries[feature]} ({count} {noun} in this release range.)")
        lines.append("")

print("\n".join(lines).rstrip())
