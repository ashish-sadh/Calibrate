# Drift - Use Cases

## Core Use Cases

### UC-1: First Launch (Apple Health Setup)
**Actor**: New user
**Flow**:
1. User opens app for the first time
2. App requests HealthKit permissions (weight, calories, sleep, steps)
3. User grants permissions
4. App immediately syncs all historical weight data from Apple Health
5. Dashboard populates with today's data: weight trend, calories burned, sleep, steps
6. Weight tab shows trend chart with all historical weights

**Success**: User sees their weight history and current deficit/surplus within seconds of granting permission.

### UC-2: Check Daily Deficit Status
**Actor**: User checking progress
**Flow**:
1. User opens app → Dashboard tab
2. Sees: calories consumed (from food log) vs calories burned (from Apple Health)
3. Sees deficit/surplus number prominently displayed
4. Sees current smoothed weight and weekly trend direction

**Success**: User knows at a glance if they're in deficit today.

### UC-3: Review Weight Trend
**Actor**: User tracking progress over time
**Flow**:
1. User taps Weight tab
2. Sees dual-line chart: actual scale weights (dots) + smooth trend line
3. Scrolls down to "Insights & Data":
   - Weight changes: 3d (-0.2kg), 7d (-0.4kg), 14d (-0.7kg), 30d (-1.8kg), 90d (-3.3kg)
   - Current weight: 53.8 kg (smoothed)
   - Weekly rate: -0.27 kg/week
   - Energy deficit: -296 kcal/day
   - 30-day projection: 52.7 kg
4. Scrolls to daily log: sees each day's weight with day-over-day change

**Success**: User understands their true weight trend and estimated deficit.

### UC-4: Log a Meal
**Actor**: User tracking nutrition
**Flow**:
1. User taps Food tab
2. Searches "chicken breast" in search bar
3. Taps result → sees macros per serving (165 cal, 31g P, 0g C, 3.6g F)
4. Adjusts serving count to 1.5
5. Picks meal type: "Lunch"
6. Taps "Log"
7. Daily totals update on Dashboard

**Success**: Food logged in under 10 seconds.

### UC-5: Quick-Add Custom Food
**Actor**: User eating something not in database
**Flow**:
1. User taps Food tab → "Quick Add"
2. Enters: "Homemade dal makhani" - 350 cal, 15g P, 12g F, 45g C, 8g fiber
3. Picks meal: "Dinner"
4. Taps "Log"

**Success**: Custom food logged with macros.

### UC-6: Log Manual Weight
**Actor**: User without smart scale / Apple Health weight
**Flow**:
1. User taps Weight tab → "+" button
2. Enters weight: 54.2 kg
3. Date defaults to today (can change)
4. Taps "Save"
5. Weight appears in chart and trend recalculates

**Success**: Manual weight entry works alongside HealthKit weights.

### UC-7: Track Supplements
**Actor**: User taking daily supplements
**Flow**:
1. User taps Supplements tab
2. Sees checklist: Electrolytes [ ], Magnesium Glycinate [ ], Creatine [ ]
3. Taps "Electrolytes" → marked as taken with timestamp
4. Dashboard shows "1/3 supplements taken"

**Success**: Quick daily supplement tracking.

### UC-8: Upload BodySpec DEXA Report
**Actor**: User with quarterly DEXA scans
**Flow**:
1. User taps More → Body Composition
2. Taps "Import DEXA Scan"
3. Picks BodySpec PDF from Files app
4. App parses PDF and extracts body composition data
5. Shows overview: Body Fat 16.4%, Lean Mass 95.5 lbs, Fat Mass 19.8 lbs, Visceral Fat 0.6 lbs
6. If previous scan exists, shows deltas: Body Fat -4.5%, Lean Mass +4 lbs, Fat Mass -5.9 lbs

**Success**: User sees body composition progress without manual data entry.

### UC-9: Import CGM Data from Lingo
**Actor**: User wearing Lingo CGM sensor
**Flow**:
1. User exports CSV from Lingo app to Files
2. Opens Drift → More → Glucose
3. Taps "Import CGM Data" → picks CSV
4. App parses and imports glucose readings
5. Shows glucose chart with color bands (green 70-100, yellow 100-140, orange 140+)
6. If meals logged, shows meal markers on chart
7. Taps a meal marker → sees glucose response: pre-meal 95, peak 135, rise +40

**Success**: User correlates glucose response with meals.

### UC-10: View Sleep Data
**Actor**: User checking sleep quality
**Flow**:
1. User opens Dashboard
2. Sees last night's sleep: "7h 23m" with time range
3. Data comes directly from Apple Health (Apple Watch or other sleep tracker)

**Success**: Sleep data displayed without any setup beyond HealthKit permission.

## Edge Cases

### EC-1: No HealthKit Permission
- App still works for manual weight entry, food logging, supplements
- Dashboard shows "Grant Health access to see calories burned, sleep, and steps"
- Weight tab shows manual entries only

### EC-2: No Weight Data Yet
- Weight tab shows empty state: "Log your first weight or connect Apple Health"
- No trend calculations possible

### EC-3: Gap in Weight Data
- EMA handles gaps naturally (picks up from last trend value)
- Chart shows gaps in scale weight dots but continuous trend line

### EC-4: Duplicate CGM Import
- Skip rows where timestamp already exists
- Show import summary: "Imported 288 readings, skipped 0 duplicates"

### EC-5: Malformed BodySpec PDF
- Fall back to manual entry form
- Show error: "Could not parse PDF. Enter your scan data manually."
