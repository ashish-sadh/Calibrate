# Testing Calibrate on Your iPhone

## Prerequisites

1. **Install Xcode** (required - not just Command Line Tools)
   ```bash
   # Option 1: Mac App Store
   # Search "Xcode" and install

   # Option 2: Direct download from developer.apple.com
   # https://developer.apple.com/download/all/

   # After install, set the active developer directory:
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

2. **Install xcodegen** (if not already installed)
   ```bash
   brew install xcodegen
   ```

## Build & Run

### Generate the Xcode Project
```bash
cd /Users/ashishsadh/workspace/Calibrate
xcodegen generate
```

### Option 1: Build from Xcode (Recommended for Device)
```bash
open Calibrate.xcodeproj
```
1. Select your iPhone as the build target (top bar)
2. Go to **Signing & Capabilities** in the target settings
3. Select your **Personal Team** under "Team"
4. Click **Run** (Cmd+R)
5. On first run, you may need to trust the developer certificate on your iPhone:
   - iPhone Settings > General > VPN & Device Management > Trust your developer certificate

### Option 2: Build from Command Line (Simulator)
```bash
xcodebuild -project Calibrate.xcodeproj \
  -scheme Calibrate \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

### Option 3: Build for Device (CLI)
```bash
xcodebuild -project Calibrate.xcodeproj \
  -scheme Calibrate \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  build
```

## First Launch Testing Checklist

### 1. Apple Health Permission
- [ ] App prompts for HealthKit access on first launch
- [ ] Grant all permissions
- [ ] Dashboard should immediately populate with:
  - Calories burned (active + basal)
  - Sleep hours
  - Step count
  - Weight data (if you have smart scale data in Health)

### 2. Weight Tracking
- [ ] Tap Weight tab
- [ ] If Health has weight data: chart should show historical weights
- [ ] Tap "+" to manually log a weight
- [ ] Verify trend line appears after 3+ data points
- [ ] Try different time ranges (1W, 1M, 3M, etc.)
- [ ] Check "Insights & Data" section shows:
  - Weight changes (3d, 7d, 14d, 30d, 90d)
  - Current weight (smoothed)
  - Weekly rate
  - Energy deficit/surplus
  - 30-day projection

### 3. Food Logging
- [ ] Tap Food tab
- [ ] Tap "+" > Search Food
- [ ] Search "daal" - should find multiple types
- [ ] Log Moong Dal with 2 servings to Lunch
- [ ] Verify daily totals update
- [ ] Try Quick Add with custom macros
- [ ] Check Dashboard calorie balance updates

### 4. Supplements
- [ ] Tap Supplements tab
- [ ] Should see 3 defaults: Electrolytes, Magnesium Glycinate, Creatine
- [ ] Tap to mark as taken - should show checkmark + timestamp
- [ ] Tap "+" to add a custom supplement
- [ ] Check Dashboard shows supplement status

### 5. Body Composition (More tab)
- [ ] Tap More > Body Composition
- [ ] Tap "Add DEXA Scan"
- [ ] Enter data from a BodySpec report:
  - Body Fat: 16.4%
  - Fat Mass: 19.8 lbs
  - Lean Mass: 95.5 lbs
  - Visceral Fat: 0.6 lbs
- [ ] Save and verify the overview cards show correctly

### 6. Glucose (More tab)
- [ ] Tap More > Glucose
- [ ] Tap "Import Lingo CSV"
- [ ] Select a CSV file from Files app
- [ ] Verify glucose chart displays with color bands

## Troubleshooting

### "Untrusted Developer" on iPhone
Settings > General > VPN & Device Management > Select your developer certificate > Trust

### Build fails with signing errors
In Xcode: Target > Signing & Capabilities > Select "Automatically manage signing" and pick your Personal Team

### HealthKit returns no data
- HealthKit returns empty (not errors) when permission is denied
- Check iPhone Settings > Privacy & Security > Health > Calibrate

### GRDB build errors
```bash
# Clean and resolve packages
xcodebuild clean -project Calibrate.xcodeproj -scheme Calibrate
swift package resolve
xcodegen generate
```

## Architecture

```
Calibrate/
├── CalibrateApp.swift          # App entry
├── ContentView.swift           # Tab navigation
├── Models/                     # GRDB data models
├── Views/                      # SwiftUI views by feature
│   ├── Dashboard/
│   ├── Weight/                 # MacroFactor-inspired weight trend
│   ├── Food/                   # Food search + logging
│   ├── Supplements/            # Daily checklist
│   ├── Glucose/                # CGM chart
│   ├── BodyComposition/        # DEXA scan data
│   └── Settings/
├── ViewModels/                 # @Observable view models
├── Services/                   # Business logic
│   ├── WeightTrendCalculator   # EMA + deficit math
│   ├── HealthKitService        # Apple Health bridge
│   └── CGMImportService        # Lingo CSV parser
├── Database/                   # GRDB setup + migrations
└── Resources/                  # foods.json, supplements JSON, assets
```
