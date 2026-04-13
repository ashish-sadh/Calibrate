#!/bin/bash
# Generate releases.json from git log

cd /Users/ashishsadh/workspace/Drift

# Get all build commits (SHA + message + date)
builds=$(git log --format="%H|%aI|%s" --grep="^chore:.*[Bb]uild" --all | sort -t'|' -k2)

# Parse into array
prev_sha=""
first=true
echo "["

while IFS='|' read -r sha date msg; do
  # Extract build number
  num=$(echo "$msg" | grep -oE '[Bb]uild\s+[0-9]+' | grep -oE '[0-9]+')
  [ -z "$num" ] && continue
  
  # Get fixes and features between prev_sha and this sha
  if [ -n "$prev_sha" ]; then
    fixes=$(git log --oneline "$prev_sha".."$sha" --grep="^fix:" --format="%s" | sed 's/^fix[:(][^)]*)\?[: ]*//' | sed 's/^fix: //')
    feats=$(git log --oneline "$prev_sha".."$sha" --grep="^feat:" --format="%s" | sed 's/^feat[:(][^)]*)\?[: ]*//' | sed 's/^feat: //')
  else
    fixes=""
    feats=""
  fi
  
  # Also parse the build commit message for inline description
  desc=$(echo "$msg" | sed -E 's/^chore:\s*(TestFlight\s+)?[Bb]uild\s+[0-9]+\s*//' | sed 's/^[—–: -]*//')
  
  if [ "$first" = true ]; then first=false; else echo ","; fi
  
  # Build JSON
  printf '{"build":%d,"date":"%s","description":"%s"' "$num" "$date" "$(echo "$desc" | sed 's/"/\\"/g')"
  
  # Fixes array
  printf ',"fixes":['
  fix_first=true
  if [ -n "$fixes" ]; then
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      if [ "$fix_first" = true ]; then fix_first=false; else printf ','; fi
      printf '"%s"' "$(echo "$f" | sed 's/"/\\"/g')"
    done <<< "$fixes"
  fi
  printf ']'
  
  # Features array
  printf ',"features":['
  feat_first=true
  if [ -n "$feats" ]; then
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      if [ "$feat_first" = true ]; then feat_first=false; else printf ','; fi
      printf '"%s"' "$(echo "$f" | sed 's/"/\\"/g')"
    done <<< "$feats"
  fi
  printf ']}'
  
  prev_sha="$sha"
done <<< "$builds"

echo ""
echo "]"
