#!/usr/bin/env python3
"""Validate an Xcode project.pbxproj for structural sanity.

Catches the class of bug where a script edit leaves entries outside their
parent list (invalid plist) or references IDs that don't exist.

Usage: python validate_pbxproj.py [path/to/project.pbxproj]
Exit 0 = valid, 1 = problems found.
"""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else \
    "DailyBoxScore.xcodeproj/project.pbxproj"
s = open(path).read()
errors = []

# 1. No merge conflict markers.
for marker in ("<<<<<<<", ">>>>>>>", "======="):
    if marker in s:
        errors.append(f"merge conflict marker {marker!r} present")

# 2. Balanced braces/parens (rough but catches truncation).
for a, b, name in (("{", "}", "braces"), ("(", ")", "parens")):
    if s.count(a) != s.count(b):
        errors.append(f"unbalanced {name}: {s.count(a)} vs {s.count(b)}")

# 3. Every PBXBuildFile's fileRef must have a matching PBXFileReference.
build_refs = set(re.findall(r"fileRef = ([0-9A-F]{24});", s))
defined = set(re.findall(r"^([0-9A-F]{24}) = \{isa = PBXFileReference;", s, re.M))
for r in build_refs - defined:
    errors.append(f"PBXBuildFile references undefined fileRef {r}")

# 4. Every build-file ID in a build phase's files list must be defined.
phase_ids = set()
for m in re.finditer(r"files = \(\n((?:\t\t\t\t[0-9A-F]{24},\n)+)\t\t\t\);", s):
    phase_ids.update(re.findall(r"[0-9A-F]{24}", m.group(1)))
all_build = set(re.findall(r"^([0-9A-F]{24}) = \{isa = PBXBuildFile;", s, re.M))
for pid in phase_ids - all_build:
    errors.append(f"build phase lists undefined PBXBuildFile {pid}")

# 5. No bare 24-hex IDs floating outside a list (the exact bug from 2026-10-07:
#    entries inserted after the closing ");" instead of inside it).
for m in re.finditer(r"\);\n((?:\t\t\t\t[0-9A-F]{24},\n)+)\t\t\t[a-z]", s):
    errors.append("IDs found outside a files/children list (after closing paren)")

# 6. Every PBXFileReference path should exist on disk (relative to project dir).
import os
proj_dir = os.path.dirname(os.path.dirname(os.path.abspath(path)))
for m in re.finditer(r"path = ([^;]+);", s):
    p = m.group(1).strip().strip('"')
    if p.endswith((".swift", ".plist", ".xcassets", ".storekit")):
        # paths are relative to the group; try under DailyBoxScore/
        cand = os.path.join(proj_dir, "DailyBoxScore", p)
        if not os.path.exists(cand):
            errors.append(f"referenced file missing on disk: {p}")

if errors:
    print("INVALID project.pbxproj:")
    for e in errors:
        print(f"  - {e}")
    sys.exit(1)
print("project.pbxproj OK")
