# Design: Cal AI — Photo-Based Calorie Identification (Beta)

> References: Issue #224

## Problem

Logging food by typing or speaking has friction. Cal AI proved users will snap a photo and log a meal in seconds. Drift's on-device models (SmolLM 360M, Gemma 4 2B) cannot do accurate vision — neither has image encoders, both are too small for multi-object food recognition with portion estimation.

To deliver this experience we must call a larger cloud vision model (Anthropic Claude, OpenAI GPT-4o). This is the **first cloud path** in a local-first app — it must be opt-in, beta-gated, BYOK (bring-your-own-key), and secure by default.

## Proposal

Ship a **Beta** feature called **Photo Log** where a user can:
1. Tap a camera icon in the chat / food log sheet.
2. Capture or pick a photo of their meal.
3. Drift sends the image + a structured prompt to the user's configured cloud model (Claude or OpenAI).
4. The model returns a structured list of foods + estimated portions + macros.
5. User reviews the result in a confirmation card and taps "Log" — regular `FoodEntry` rows are saved.

**Scope in:**
- BYOK flow: user pastes their Anthropic or OpenAI API key in Settings → "Photo Log (Beta)".
- Keychain storage with biometric gate on retrieval.
- One image per request, single-turn (no follow-up).
- Vision call → parsed `[FoodEntry]` → existing confirmation UI.
- Clear cost/privacy banner at feature entry and at each photo send.
- Beta opt-in toggle hidden behind a "Beta Features" section; off by default.

**Scope out (follow-up work):**
- Multi-photo / multi-meal batch upload.
- Continuous camera (live overlay).
- Drift-managed billing or proxy (would break BYOK privacy promise).
- On-device vision (future, when a useful small vision model is viable).
- Barcode scanning (separate design).
- Feedback / correction loop that mutates a personal prompt.

## UX Flow

### First-run entry (Settings → Photo Log Beta)

```
[Beta Badge] Photo Log
Snap your meal, get calories.

⚠️  This feature sends photos to a cloud AI service. Everything else in Drift
    stays on your device. Only turn this on if you're comfortable with that
    tradeoff.

You provide and pay for your own API key — Drift never sees your photos or key.

Provider:   ( ) Anthropic (Claude)   ( ) OpenAI (GPT-4o)
API Key:    [•••••••••••••••]   [Paste]
            Stored in iOS Keychain, protected by Face ID.

[Test Connection]  → sends a tiny text ping to verify the key works.
[Enable Photo Log]
```

Once enabled: a camera button appears in the Food Log sheet and in chat input.

### Photo send

```
User: taps camera → captures / picks a photo
  │
  ▼
┌──────────────────────────────────────────┐
│  [image preview]                         │
│                                          │
│  This will send your photo to Claude     │
│  (Anthropic). Est. cost: ~$0.01          │
│                                          │
│  [Cancel]              [Analyze]         │
└──────────────────────────────────────────┘
  │
  ▼ user taps Analyze
  │
  ▼
Spinner: "Looking at your plate…"
  │
  ▼
┌──────────────────────────────────────────┐
│  Found 3 items                           │
│                                          │
│  ✓ Grilled salmon       ~180 g   320 kcal│
│  ✓ White rice           ~150 g   200 kcal│
│  ✓ Steamed broccoli     ~100 g    35 kcal│
│                                          │
│  Total: 555 kcal · 42g P · 48g C · 18g F │
│  Confidence: medium                      │
│                                          │
│  [Discard]  [Edit]  [Log as Dinner]      │
└──────────────────────────────────────────┘
```

### Error states

- **No key / bad key:** card explaining, deep-link to Settings.
- **Rate limited / 429:** "Provider is throttling. Try again in a minute."
- **No food detected:** "We couldn't identify food in this photo. Try again or log manually."
- **Offline:** "Photo Log needs internet. Your on-device chat still works."
- **Timeout (>20 s):** cancel button surfaces; show graceful fallback to manual logging.

### Chat-initiated path

If the user drops an image in chat ("what is this?", "log this meal"), the router detects an image attachment. When Photo Log is enabled, the pipeline routes to the same vision call rather than telling the user images aren't supported.

## Technical Approach

### New files

| File | Purpose |
|------|---------|
| `Drift/Services/CloudVision/CloudVisionClient.swift` | Protocol + Anthropic/OpenAI implementations |
| `Drift/Services/CloudVision/CloudVisionKey.swift` | Keychain-backed key storage, biometric gate |
| `Drift/Services/CloudVision/PhotoLogService.swift` | Orchestrates: image → prompt → client → parsed response |
| `Drift/Services/CloudVision/PhotoLogResponse.swift` | Codable struct for the structured output |
| `Drift/Views/PhotoLog/PhotoLogCaptureView.swift` | Camera + picker entry |
| `Drift/Views/PhotoLog/PhotoLogReviewView.swift` | Confirmation card (matches existing food confirm UI) |
| `Drift/Views/Settings/PhotoLogBetaSettingsView.swift` | Provider, key, test connection |
| `Drift/Models/PhotoLogEntry.swift` | Transient model before confirmation → turns into `FoodEntry[]` |

### Changed files

| File | Change |
|------|--------|
| `Drift/AI/AIToolAgent.swift` | New `PhotoLogTool` registered when beta flag is on and key is set |
| `Drift/Views/Food/FoodLogSheet.swift` | Add camera button (hidden unless feature enabled) |
| `Drift/Views/Chat/ChatInputView.swift` | Accept image attachments when beta enabled |
| `Drift/Models/UserSettings.swift` | `photoLogEnabled: Bool`, `photoLogProvider: Provider` (key itself stays in Keychain) |
| `Drift/Services/SettingsStore.swift` | Persist the two new flags |

### Key storage (security is load-bearing)

```swift
enum CloudVisionKey {
    static let service = "com.drift.photolog"
    
    static func set(_ key: String, provider: Provider) throws {
        // kSecClassGenericPassword
        // kSecAttrAccessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        // kSecAttrAccount  = provider.rawValue
        // Wraps value with access control requiring .biometryCurrentSet || .devicePasscode
    }
    
    static func get(provider: Provider) throws -> String
    static func clear(provider: Provider) throws
}
```

Rules:
- **`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`** — key never leaves the device, not in iCloud Keychain backup, lost if restored to a new device (user re-enters).
- **`SecAccessControl`** with `.biometryCurrentSet` — Face ID / Touch ID gate on every retrieval; a jailbreak-enabled attacker still cannot pull the key without biometrics.
- Key is read once per app session into a `String` that lives in a Swift `actor`; it is never written to `UserDefaults`, logs, crash reports, analytics, or persisted files.
- `CloudVisionClient` never prints the key; URLRequest headers are redacted in any debug log.
- On disable: key is deleted from Keychain synchronously.
- No encryption-on-top-of-Keychain — Keychain is already hardware-backed on iOS. Adding app-level AES would be cargo-cult and increase attack surface via custom crypto.

### Vision call

**Anthropic Claude:**
- `POST https://api.anthropic.com/v1/messages`
- Model: `claude-sonnet-4-6` (default), user can override.
- `x-api-key` header.
- Image sent as `base64` block, max 1 MB after downscaling to 1024 px on long edge.
- System prompt: "You are a nutrition estimator. Return only JSON." 
- Tool-use `food_log` with a typed schema (see below) to force structured output.

**OpenAI:**
- `POST https://api.openai.com/v1/chat/completions`
- Model: `gpt-4o` (default).
- `response_format: { type: "json_schema" }` with the same schema.

Both implementations live behind:

```swift
protocol CloudVisionClient {
    func analyze(image: Data, prompt: String) async throws -> PhotoLogResponse
}
```

So the UI and service layers stay provider-agnostic.

### Response schema

```json
{
  "items": [
    {
      "name": "grilled salmon",
      "grams": 180,
      "calories": 320,
      "protein_g": 34,
      "carbs_g": 0,
      "fat_g": 18,
      "confidence": "high"
    }
  ],
  "overall_confidence": "medium",
  "notes": "Portion estimates assume a dinner plate ~25cm wide."
}
```

Confidence is an enum `low | medium | high`. Anything below `medium` shows a warning icon and a "verify" CTA. Fields missing from the model response default to 0 and flag the item as low confidence.

### Image preprocessing (on-device, before upload)

- Downscale long edge to 1024 px — enough for food ID, cuts tokens ~4×.
- JPEG re-encode at 0.7 quality → ~150 KB typical payload.
- Strip EXIF (location, device, timestamp) — user photos stay private even on the server trip.
- Hash the image with SHA-256 and cache the last 20 (image hash → response). Re-snapping the same plate while debugging doesn't re-bill the user.

### Interaction with dual-model architecture

- This feature **does not touch SmolLM or Gemma**. On-device pipeline remains the default path for every non-image request.
- `AIToolAgent` learns a new tool `photo_log` that is only registered when `photoLogEnabled && keychainHasKey`. The router stays on-device — only the tool call itself hits the network.
- Multi-turn context is not supported in round 1 — each photo is a fresh call. Chat history is not sent with the image.

### Performance

- Payload ~150 KB image + ~300 token prompt.
- Typical Claude / GPT-4o vision response: 3–8 s.
- Target budget: 12 s P95, 20 s hard timeout.
- UI shows a progress shimmer; cancel button at 6 s.

### Cost transparency

Before each send: inline estimate ("~$0.01"). After each send: real cost pulled from response headers (`anthropic-prompt-tokens`, etc.) shown in a compact footnote in the review card. Settings has a rolling 30-day spend estimate (stored locally, never uploaded).

## Edge Cases

- **Key revoked mid-session:** first 401 → invalidate in-memory key → show "Re-enter key" sheet → do not retry.
- **Partial JSON from model:** attempt repair via `JSONSerialization` with `.allowFragments` first, then fall back to manual logging card. Never silently log corrupt data.
- **Huge photo (>15 MB from newer iPhones):** downscale before any network call.
- **Photo that is not food:** model returns `items: []` → UX shows "No food detected" instead of logging an empty meal.
- **Multiple plates / group meal:** model still returns per-item list; user can deselect items before logging. Our schema doesn't enforce a single meal.
- **User has both Anthropic and OpenAI keys:** Settings picks one active; switching preserves the other key in Keychain under a different account attribute.
- **Offline when tapping Analyze:** detect via `NWPathMonitor`; short-circuit before any call, show offline card.
- **Exported meals / backup:** Photos are not persisted — only the resulting `FoodEntry` rows. Image data is purged from memory after the response parses.
- **TestFlight reviewer without a key:** feature toggle visible but gated — they can see the promise without a mandatory BYOK flow blocking review.
- **Family Sharing / multi-profile:** key is per-device, per-install. Not a shared setting.
- **Network MITM:** we pin to the provider's TLS via `URLSession` defaults + `App Transport Security` with explicit domains in `Info.plist`. No custom cert pinning — Apple's defaults are strong enough and avoid key rotation pain.

## Privacy & Trust

Because this is our first cloud feature, the first-run copy is careful:

> "Turning on Photo Log sends your meal photos to the AI provider you choose
>  (Anthropic or OpenAI). Drift never sees your photos. Your API key is stored
>  in the iOS Keychain and protected by Face ID."

This copy appears in:
- Settings toggle subtitle
- First-enable confirmation sheet (must be acknowledged)
- A subtle banner above the camera preview (not dismissible on first 5 uses)

Privacy policy addendum required in App Store metadata before shipping.

## Telemetry

None. We're a local-first app. The only "tracking" is the local 30-day spend counter the user can see in Settings.

## Open Questions

1. **Default provider?** Anthropic (Claude) is the better vision model for food today, but OpenAI is more familiar and has a simpler key UX. Recommend: ship with Claude preselected and an explanatory toggle. 
2. **Do we offer a Drift-hosted proxy later?** Would let us support users without a key, but adds a server, a billing relationship, and breaks the no-cloud promise. Recommend: explicitly no for v1 — revisit if Beta uptake is strong.
3. **Save the photo to FoodEntry?** Could attach image for history. Disk cost + privacy risk. Recommend: no in v1 — photos are ephemeral, only parsed macros persist.
4. **Gemma fallback?** On devices without a key configured, should we still attempt a Gemma+describe-from-user-text flow? Recommend: no — feature advertises photo-to-calories; a degraded text flow confuses the value prop. Fall back to the existing food log flow.
5. **Price guardrail?** Cap monthly spend (user-configurable) with a hard stop? Recommend: add a soft warning at $10/mo; don't block — their money, their choice.
6. **Naming — "Photo Log" vs "Cal AI"?** "Cal AI" is the category but also the name of a competitor. Recommend: internal name `PhotoLog`, user-facing name **Photo Log (Beta)** — descriptive, non-trademarked.

---

*To approve: add `approved` label to the PR. To request changes: comment on the PR.*
