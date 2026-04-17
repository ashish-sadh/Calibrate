#!/usr/bin/env python3
"""
Add YouTube search URLs for top exercises.
Opens via SFSafariViewController — no API key, always fresh results.
"""
import json, os, urllib.parse

EXERCISES_JSON = os.path.join(os.path.dirname(__file__), "../Drift/Resources/exercises.json")

# Map exercise name → search query (keeps results high-quality and fresh)
YOUTUBE_QUERIES = {
    "Barbell Squat": "barbell squat form tutorial",
    "Barbell Bench Press": "barbell bench press form tutorial",
    "Deadlift": "deadlift form tutorial",
    "Pull-Up": "pull up form tutorial",
    "Overhead Press": "overhead press form tutorial",
    "Barbell Row": "barbell row form tutorial",
    "Romanian Deadlift": "romanian deadlift form tutorial",
    "Incline Barbell Bench Press": "incline bench press form tutorial",
    "Lat Pulldown": "lat pulldown form tutorial",
    "Seated Cable Row": "seated cable row form tutorial",
    "Hip Thrust": "hip thrust form tutorial",
    "Barbell Lunge": "barbell lunge form tutorial",
    "Leg Press": "leg press form tutorial",
    "Leg Extension": "leg extension form tutorial",
    "Leg Curl": "leg curl form tutorial",
    "Calf Raise": "calf raise form tutorial",
    "Goblet Squat": "goblet squat form tutorial",
    "Hack Squat": "hack squat form tutorial",
    "Dumbbell Bicep Curl": "bicep curl form tutorial",
    "Hammer Curl": "hammer curl form tutorial",
    "Barbell Biceps Curl": "barbell bicep curl form tutorial",
    "Triceps Pushdown": "tricep pushdown form tutorial",
    "Skull Crusher": "skull crusher form tutorial",
    "Dumbbell Shoulder Press": "dumbbell shoulder press form tutorial",
    "Lateral Raise": "lateral raise form tutorial",
    "Arnold Press": "arnold press form tutorial",
    "Face Pull": "face pull form tutorial",
    "Rear Delt Fly": "rear delt fly form tutorial",
    "Cable Crossover": "cable crossover form tutorial",
    "Incline Dumbbell Bench Press": "incline dumbbell press form tutorial",
    "Dumbbell Fly": "dumbbell fly form tutorial",
    "Dips": "dips form tutorial",
    "Plank": "plank form tutorial core",
    "Crunch": "crunch ab exercise form",
    "Russian Twist": "russian twist ab exercise form",
    "Hanging Leg Raise": "hanging leg raise form tutorial",
    "Ab Wheel Rollout": "ab wheel rollout form tutorial",
    "Power Clean": "power clean form tutorial",
    "Front Squat": "front squat form tutorial",
    "Push-Up": "push up form tutorial",
}

def youtube_url(query: str) -> str:
    return "https://www.youtube.com/results?search_query=" + urllib.parse.quote(query)

with open(EXERCISES_JSON) as f:
    exercises = json.load(f)

added = 0
for ex in exercises:
    name = ex["name"]
    if name in YOUTUBE_QUERIES and "youtubeUrl" not in ex:
        ex["youtubeUrl"] = youtube_url(YOUTUBE_QUERIES[name])
        added += 1

print(f"Added youtubeUrl to {added} exercises")

with open(EXERCISES_JSON, "w") as f:
    json.dump(exercises, f, indent=2, ensure_ascii=False)

print("Done.")
