#!/usr/bin/env python3
"""
Enrich exercises.json with imageUrl from free-exercise-db (MIT license).
Source: https://github.com/yuhonas/free-exercise-db
Image base URL: https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/

Match tiers (stop at first hit, shortest wins within a tier):
  1. Exact case-insensitive name match.
  2. Substring match — our name sits inside a free-DB name
     ("bench press" → "barbell bench press - medium grip"). Shortest
     candidate wins so plain base variants beat oddly-qualified ones.
  3. Stripped-qualifier match — drop a leading equipment word from our
     name ("Machine Chest Press" → "Chest Press") and retry tier 1/2.
"""
from __future__ import annotations
import json
import urllib.request
import os

EXERCISES_JSON = os.path.join(os.path.dirname(__file__), "../Drift/Resources/exercises.json")
FREE_DB_URL = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"
IMAGE_BASE = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"

# Leading qualifiers stripped in tier 3. Keep narrow — we only want to
# handle equipment prefixes ("Machine X") or shared modifiers ("Bodyweight X"),
# not semantic variants ("Single Leg", "Walking") that would collapse distinct
# exercises into the same image.
LEADING_QUALIFIERS = {"machine", "cable", "bodyweight", "dumbbell", "barbell", "ez bar"}

print("Downloading free-exercise-db...")
req = urllib.request.urlopen(FREE_DB_URL, timeout=30)
source = json.loads(req.read())
print(f"Downloaded {len(source)} source exercises")

# Build name → imageUrl map and a list of (lowercased name, imageUrl) for
# substring scans. Skip sources with no images up front so tier 2 never
# returns a match with no URL.
name_to_image: dict[str, str] = {}
source_pairs: list[tuple[str, str]] = []
for ex in source:
    name = ex.get("name", "")
    images = ex.get("images", [])
    if name and images:
        lc = name.lower()
        url = IMAGE_BASE + images[0]
        name_to_image[lc] = url
        source_pairs.append((lc, url))

print(f"Built map with {len(name_to_image)} entries")


def strip_leading_qualifier(name: str) -> str | None:
    """Return the name with its leading qualifier word removed, or None if
    the first token isn't in our allow-list. Two-word qualifiers ("ez bar")
    are handled before single words."""
    lc = name.lower()
    for q in sorted(LEADING_QUALIFIERS, key=len, reverse=True):
        prefix = q + " "
        if lc.startswith(prefix):
            return name[len(prefix):]
    return None


def best_substring_match(needle: str) -> str | None:
    """Shortest free-DB name that contains `needle` as a whole phrase.
    Shortest wins because 'bench press' should beat 'barbell bench press -
    medium grip' when both are candidates — the plain variant is usually
    the canonical image."""
    candidates = [(n, u) for n, u in source_pairs if needle in n]
    if not candidates:
        return None
    candidates.sort(key=lambda p: len(p[0]))
    return candidates[0][1]


def resolve_image(our_name: str) -> str | None:
    key = our_name.lower()
    # Tier 1
    if key in name_to_image:
        return name_to_image[key]
    # Tier 2 — substring scan on the original name
    hit = best_substring_match(key)
    if hit:
        return hit
    # Tier 3 — strip a leading qualifier, retry tier 1/2
    stripped = strip_leading_qualifier(our_name)
    if stripped:
        skey = stripped.lower()
        if skey in name_to_image:
            return name_to_image[skey]
        return best_substring_match(skey)
    return None


with open(EXERCISES_JSON) as f:
    our_exercises = json.load(f)

matched_before = sum(1 for e in our_exercises if e.get("imageUrl"))
added = 0
by_tier = {"substring": 0, "stripped": 0}

for ex in our_exercises:
    if ex.get("imageUrl"):
        continue
    our_name = ex["name"]
    key = our_name.lower()
    if key in name_to_image:
        ex["imageUrl"] = name_to_image[key]
        added += 1
        continue
    hit = best_substring_match(key)
    if hit:
        ex["imageUrl"] = hit
        added += 1
        by_tier["substring"] += 1
        continue
    stripped = strip_leading_qualifier(our_name)
    if stripped:
        skey = stripped.lower()
        if skey in name_to_image:
            ex["imageUrl"] = name_to_image[skey]
        else:
            shit = best_substring_match(skey)
            if shit:
                ex["imageUrl"] = shit
        if "imageUrl" in ex and ex["imageUrl"]:
            added += 1
            by_tier["stripped"] += 1

total = len(our_exercises)
covered = sum(1 for e in our_exercises if e.get("imageUrl"))
print(f"Added {added} new imageUrls (substring={by_tier['substring']}, stripped-qualifier={by_tier['stripped']})")
print(f"Coverage: {covered}/{total} ({covered*100//total}%), was {matched_before}/{total} ({matched_before*100//total}%)")

with open(EXERCISES_JSON, "w") as f:
    json.dump(our_exercises, f, indent=2, ensure_ascii=False)

print(f"Written back to {EXERCISES_JSON}")
