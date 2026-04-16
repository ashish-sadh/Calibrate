# Design: Enrich Exercises with Images and YouTube

> References: Issue #66

## Problem

Exercise presentation is text-only. Boostcamp and Strong both show exercise images/animations and form videos. Our 960-exercise database has name, muscles, equipment, and level — but no visuals. Users can't see proper form, muscle engagement, or exercise alternatives visually. This is a major gap for a fitness app.

## Proposal

Add exercise images and optional YouTube video links to the exercise database. Source images from free-exercise-db (upstream has GIF URLs we stripped) and curate YouTube links for the top 50 most-used exercises. Display images in exercise browser, detail view, and workout cards.

**In scope:**
- Re-import exercise data with image URLs from free-exercise-db
- Image display in ExerciseBrowserView, ExerciseDetailView, workout cards
- Async image loading with caching (no bundled assets — URLs only)
- Optional YouTube link with in-app player for top exercises
- Fallback for exercises without images (muscle group icon)

**Out of scope:**
- Custom exercise images (user-uploaded)
- Generating our own animations (Strong-style)
- Video recording or form checking

## UX Flow

**Exercise Browser:**
1. Each exercise row shows a small thumbnail (60x60) on the left
2. If no image: show SF Symbol for the body part (existing muscle group chips)
3. Tapping a row opens detail view

**Exercise Detail:**
1. Hero image at top (full-width, 200pt tall)
2. If YouTube link exists: play button overlay on hero image
3. Tapping play opens YouTube video in a sheet (WKWebView or SFSafariViewController)
4. Below image: existing info (muscles, equipment, level, PR, history)

**Workout Cards (TemplatePreviewSheet):**
1. Small thumbnail next to exercise name (40x40)
2. No video links in compact card view

## Technical Approach

### Data source

The free-exercise-db project (source of our exercises.json) includes `gifUrl` fields pointing to exercise GIF animations. Our import stripped these. Steps:

1. Re-download full dataset from free-exercise-db
2. Map `gifUrl` and any `images[]` fields into our Exercise model
3. Add `youtubeUrl: String?` field — manually curated for top 50 exercises
4. Update exercises.json with new fields

### Model changes

```swift
// Workout.swift — Exercise struct
struct Exercise {
    let name: String
    let bodyPart: String
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let equipment: String
    let category: String
    let level: String
    let imageUrl: String?     // NEW — GIF or static image URL
    let youtubeUrl: String?   // NEW — curated form video
}
```

### Image loading

Use `AsyncImage` (built-in SwiftUI) with disk caching:
- First load: fetch from URL, cache to `Caches/` directory
- Subsequent: load from disk cache
- Placeholder: SF Symbol for body part
- No third-party dependencies

### Files that change

| File | Change |
|------|--------|
| `Models/Workout.swift` | Add `imageUrl`, `youtubeUrl` to Exercise |
| `Resources/exercises.json` | Re-import with image URLs, add youtube URLs for top 50 |
| `Services/ExerciseDatabase.swift` | Parse new fields from JSON |
| `Views/Workout/ExerciseBrowserView.swift` | Add thumbnail to row |
| `Views/Workout/ExerciseDetailView.swift` | Add hero image + YouTube player |
| `Views/Workout/TemplatePreviewSheet.swift` | Add small thumbnail |
| `Views/Workout/ExercisePickerView.swift` | Add thumbnail to picker rows |

### YouTube integration

- Use `SFSafariViewController` for YouTube links (no API key needed, respects user's YouTube login)
- Present as a sheet from exercise detail
- No autoplay — user taps play button explicitly

## Edge Cases

- **No image URL for exercise:** Show body-part SF Symbol (already used in muscle group chips). ~10% of exercises may lack images.
- **Image URL broken/404:** AsyncImage shows placeholder automatically. Cache miss retries on next view.
- **Large GIF files:** GIFs can be 1-5MB. Lazy loading + cache eviction (LRU, 100MB cap) prevents memory pressure.
- **Offline:** Cached images work offline. Uncached images show placeholder. No crash.
- **Custom exercises:** No image (user-created). Show generic icon.

## Open Questions

1. **GIF vs static image?** GIFs show full range of motion (like Boostcamp) but are larger. Could convert to short video (HEVC) for better compression. Recommend: start with GIFs, optimize later if needed.
2. **How many YouTube links to curate?** Proposal says top 50. Could expand to 100+ over time. Need to pick quality channels (Jeff Nippard, Renaissance Periodization, etc.). Recommend: start with 50, add more based on user exercise frequency data.
3. **Should images be bundled or fetched?** Bundling 960 GIFs would add 500MB+ to app size. URL-based with caching is better. Tradeoff: first-time load requires internet. Recommend: URL-based.

---

*To approve: add `approved` label to the PR. To request changes: comment on the PR.*
