# USDA FoodData Central API — Integration Design

## Context

Drift's food database has 1,500 manually curated foods. MyFitnessPal has 20M+. We can't close this gap manually. The USDA FoodData Central API provides free, verified nutrition data for 300,000+ foods. This would be Drift's **first external network call** — architecturally significant.

**Decision required:** Should we integrate, and if so, how do we maintain our privacy-first, offline-first guarantees?

---

## API Overview

- **Endpoint:** `https://api.nal.usda.gov/fdc/v1/`
- **Auth:** Free API key (no user data required)
- **Rate limit:** 1,000 requests/hour per key
- **Key endpoints:**
  - `GET /foods/search?query=chicken&pageSize=10` — search foods
  - `GET /food/{fdcId}` — full nutrition detail for one food
- **Data types:** SR Legacy (USDA standard reference), Foundation, Branded (commercial products)
- **Response:** JSON with nutrients array (energy, protein, fat, carbs, fiber, etc.)

---

## Architecture Proposal

### Principle: Offline-First with On-Demand Enrichment

The local DB remains the primary source. USDA is a fallback when local search returns insufficient results. Once fetched, USDA data is cached locally forever — the device never needs to re-fetch the same food.

```
User types "quinoa salad"
  → Local DB search (1,500 foods)
  → If results < 3 AND network available:
      → USDA API search
      → Cache results to local DB (source: "usda")
      → Show combined results
  → If offline: show local results only, no error
```

### Data Flow

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  FoodSearch   │────▶│  FoodService  │────▶│  Local DB    │
│  (View)       │     │  (Orchestrator)│    │  (GRDB)      │
└──────────────┘     └──────┬───────┘     └──────────────┘
                            │ if local results < 3
                            ▼
                     ┌──────────────┐
                     │  USDAClient   │
                     │  (URLSession) │
                     └──────┬───────┘
                            │ cache to DB
                            ▼
                     ┌──────────────┐
                     │  Local DB    │
                     │  (source:usda)│
                     └──────────────┘
```

### Components

1. **USDAClient** — Thin wrapper around URLSession
   - `searchFoods(query: String, limit: Int) async throws -> [USDAFood]`
   - `fetchNutrition(fdcId: Int) async throws -> USDANutrition`
   - Rate limiting: max 1 request per second, max 50 per session
   - Timeout: 5 seconds per request
   - No retry on failure — graceful degradation

2. **USDACache** — Maps USDA results to local FoodEntry format
   - Store in existing `foods.json` format with `source: "usda"` marker
   - Or: separate `usda_cache` table in GRDB (preferred — no file conflicts)
   - Cache key: USDA fdcId (unique, stable)
   - Cache expiry: never (USDA nutrition data doesn't change)

3. **FoodService extension** — Orchestrates local + USDA search
   - `searchWithFallback(query:) async -> [FoodItem]`
   - Local results shown immediately, USDA results appended asynchronously
   - UI shows "Searching USDA..." indicator while fetching

---

## Privacy Analysis

### What leaves the device
- **Search queries** — The text the user types in food search (e.g., "chicken breast")
- **API key** — Drift's USDA API key (not user-specific)

### What does NOT leave the device
- No user identifiers, no device ID, no health data
- No tracking, no analytics, no telemetry
- Search queries are plain food terms — low sensitivity

### Mitigations
- **Opt-in:** User must enable "Online food search" in Settings. Off by default.
- **Indicator:** Show a small icon (e.g., globe) when results come from USDA
- **No logging:** Don't log search queries or API calls
- **Local-first:** App works 100% without network. USDA is enhancement only.

---

## Database Schema Addition

```sql
CREATE TABLE IF NOT EXISTS usda_cache (
    fdc_id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    calories REAL NOT NULL,
    protein_g REAL NOT NULL,
    carbs_g REAL NOT NULL,
    fat_g REAL NOT NULL,
    fiber_g REAL NOT NULL DEFAULT 0,
    serving_size_g REAL NOT NULL DEFAULT 100,
    serving_unit TEXT NOT NULL DEFAULT 'g',
    brand TEXT,
    cached_at TEXT NOT NULL
);
```

When user logs a USDA food, it's stored as a normal `food_entry` with `source: "usda"` and `food_id` pointing to the usda_cache entry.

---

## UX Design

### Food Search Flow (with USDA enabled)
1. User types query → local results appear instantly
2. If < 3 local results → "Searching online..." spinner below results
3. USDA results appear (marked with globe icon) → appended to list
4. User taps USDA result → logged normally, cached locally
5. Next time user searches same food → served from local cache, no network

### Settings
- `More > Settings > Online Food Search` — Toggle (default: OFF)
- Description: "Search USDA database when local results are limited. Only food search terms are sent — no personal data."

### Offline Behavior
- No error messages, no degradation, no "you're offline" banners
- Simply don't show USDA results — user sees local DB only
- Previously cached USDA foods still appear (they're local now)

---

## Implementation Phases

### Phase 1: Foundation (1-2 cycles)
- USDAClient with search + nutrition endpoints
- Rate limiting + timeout
- Unit tests with mock responses

### Phase 2: Cache Layer (1-2 cycles)
- usda_cache table in GRDB
- FoodService.searchWithFallback()
- Integration with existing FoodSearchView

### Phase 3: UI Integration (1-2 cycles)
- Settings toggle
- Globe icon on USDA results
- "Searching online..." indicator
- Graceful offline handling

### Phase 4: Polish (1 cycle)
- Nutrient mapping verification (USDA uses different nutrient IDs)
- Serving size normalization (USDA often uses 100g basis)
- Search quality tuning (filter branded junk, prefer SR Legacy)

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| API rate limit exceeded | Low | Medium | Local rate limiting (1/sec, 50/session) |
| API goes down | Low | Low | Graceful degradation — local DB only |
| Bad nutrition data | Medium | High | Prefer SR Legacy data type; show source |
| Privacy concern from users | Medium | High | Opt-in, clear description, no PII sent |
| Network dependency creep | Medium | High | Strict boundary: only FoodService calls USDAClient |

---

## Decision Points for Leadership

1. **Opt-in vs opt-out?** — Recommend opt-in (default OFF) to preserve privacy-first identity.
2. **Which USDA data types?** — SR Legacy is most reliable. Branded adds commercial products but is noisier. Recommend SR Legacy + Foundation only initially.
3. **Should chat queries also trigger USDA?** — When user says "log quinoa 200g" and it's not in local DB, should we auto-search USDA? Recommend yes, but only if the setting is enabled.
4. **Timeline** — 5-7 cycles to full integration. Should we start this quarter?

---

## Alternatives Considered

| Option | Pros | Cons |
|--------|------|------|
| USDA API (recommended) | Free, verified, 300K+ foods, no signup | First network call, search queries leave device |
| Manual enrichment | Zero privacy risk | Doesn't scale (1,500 → 20M is impossible) |
| OpenFoodFacts API | Community-driven, barcode data | Less reliable nutrition data, inconsistent quality |
| Nutritionix API | Better search, restaurant data | Paid ($500/mo+), requires user tracking |
| Embedded USDA DB | Fully offline | 50MB+ app size increase, stale data |

**Recommendation:** USDA API with opt-in setting. It's free, verified, and the opt-in toggle preserves our privacy-first identity while closing the food DB gap for users who want it.
