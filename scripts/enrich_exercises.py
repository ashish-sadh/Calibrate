#!/usr/bin/env python3
"""
Enrich exercises.json with imageUrl from free-exercise-db (MIT license).
Source: https://github.com/yuhonas/free-exercise-db
Image base URL: https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/
"""
import json
import urllib.request
import os

EXERCISES_JSON = os.path.join(os.path.dirname(__file__), "../Drift/Resources/exercises.json")
FREE_DB_URL = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"
IMAGE_BASE = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"

print("Downloading free-exercise-db...")
req = urllib.request.urlopen(FREE_DB_URL, timeout=30)
source = json.loads(req.read())
print(f"Downloaded {len(source)} source exercises")

# Build name → imageUrl map (case-insensitive)
name_to_image: dict[str, str] = {}
for ex in source:
    name = ex.get("name", "")
    images = ex.get("images", [])
    if name and images:
        name_to_image[name.lower()] = IMAGE_BASE + images[0]

print(f"Built map with {len(name_to_image)} entries")

with open(EXERCISES_JSON) as f:
    our_exercises = json.load(f)

matched = 0
for ex in our_exercises:
    name_key = ex["name"].lower()
    if "imageUrl" not in ex and name_key in name_to_image:
        ex["imageUrl"] = name_to_image[name_key]
        matched += 1

print(f"Matched {matched}/{len(our_exercises)} exercises ({matched*100//len(our_exercises)}%)")

with open(EXERCISES_JSON, "w") as f:
    json.dump(our_exercises, f, indent=2, ensure_ascii=False)

print(f"Written back to {EXERCISES_JSON}")
