# Graph Report - Drift  (2026-04-18)

## Corpus Check
- 140 files · ~151,522 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1760 nodes · 4101 edges · 29 communities detected
- Extraction: 60% EXTRACTED · 40% INFERRED · 0% AMBIGUOUS · INFERRED: 1641 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_AI Chat & Food Log UI|AI Chat & Food Log UI]]
- [[_COMMUNITY_AI Planning & Workout Flow|AI Planning & Workout Flow]]
- [[_COMMUNITY_AI Backend & Model Types|AI Backend & Model Types]]
- [[_COMMUNITY_Data Persistence Layer|Data Persistence Layer]]
- [[_COMMUNITY_Food Data Model|Food Data Model]]
- [[_COMMUNITY_Model Management & Device|Model Management & Device]]
- [[_COMMUNITY_Supplement & Health Tracking|Supplement & Health Tracking]]
- [[_COMMUNITY_Biomarkers & Analytics UI|Biomarkers & Analytics UI]]
- [[_COMMUNITY_Core Database Operations|Core Database Operations]]
- [[_COMMUNITY_Intent Actions & Cache|Intent Actions & Cache]]
- [[_COMMUNITY_AI Action Execution|AI Action Execution]]
- [[_COMMUNITY_AI Response Parsing|AI Response Parsing]]
- [[_COMMUNITY_Conversation State Machine|Conversation State Machine]]
- [[_COMMUNITY_Templates & Barcode Data|Templates & Barcode Data]]
- [[_COMMUNITY_Biomarker Definitions|Biomarker Definitions]]
- [[_COMMUNITY_Active Workout UI|Active Workout UI]]
- [[_COMMUNITY_Charts & Layout|Charts & Layout]]
- [[_COMMUNITY_BodySpec PDF Import|BodySpec PDF Import]]
- [[_COMMUNITY_Barcode Scanner|Barcode Scanner]]
- [[_COMMUNITY_TDEE Estimation|TDEE Estimation]]
- [[_COMMUNITY_Lab & DEXA Data|Lab & DEXA Data]]
- [[_COMMUNITY_Food Search & Favorites|Food Search & Favorites]]
- [[_COMMUNITY_Food Entry Model|Food Entry Model]]
- [[_COMMUNITY_Workout Body Map|Workout Body Map]]
- [[_COMMUNITY_Input Normalization|Input Normalization]]
- [[_COMMUNITY_App Entry Point|App Entry Point]]
- [[_COMMUNITY_Saved Food Model|Saved Food Model]]
- [[_COMMUNITY_Logging Utility|Logging Utility]]
- [[_COMMUNITY_Date Utilities|Date Utilities]]

## God Nodes (most connected - your core abstractions)
1. `date` - 126 edges
2. `text` - 104 edges
3. `weight` - 73 edges
4. `AppDatabase` - 52 edges
5. `AIChatViewModel` - 38 edges
6. `FoodService` - 32 edges
7. `RawIngredient` - 30 edges
8. `WorkoutService` - 29 edges
9. `error` - 28 edges
10. `loadToday()` - 26 edges

## Surprising Connections (you probably didn't know these)
- `loadToday()` --calls--> `error`  [INFERRED]
  Drift/ViewModels/DashboardViewModel.swift → Drift/Services/ToolSchema.swift
- `seedMockFoodIfNeeded()` --calls--> `date`  [INFERRED]
  Drift/ViewModels/FoodLogViewModel.swift → Drift/Models/SupplementLog.swift
- `copyEntryToToday()` --calls--> `date`  [INFERRED]
  Drift/ViewModels/FoodLogViewModel.swift → Drift/Models/SupplementLog.swift
- `quickAdd()` --calls--> `date`  [INFERRED]
  Drift/ViewModels/FoodLogViewModel.swift → Drift/Models/SupplementLog.swift
- `goToPreviousDay()` --calls--> `date`  [INFERRED]
  Drift/ViewModels/FoodLogViewModel.swift → Drift/Models/SupplementLog.swift

## Communities

### Community 0 - "AI Chat & Food Log UI"
Cohesion: 0.03
Nodes (31): logFood, AIChatView, TypewriterText, AIView, BarcodeLookupView, food, weight, CycleView (+23 more)

### Community 1 - "AI Planning & Workout Flow"
Cohesion: 0.03
Nodes (26): AIChainOfThought, bodyComposition, AIScreenTracker, Step, AIChatViewModel, AIContextBuilder, AIContextBuilder, AIRuleEngine (+18 more)

### Community 2 - "AI Backend & Model Types"
Cohesion: 0.02
Nodes (93): AIBackend, AIBackendType, llamaCpp, mlx, AIModelTier, large, small, ModelFile (+85 more)

### Community 3 - "Data Persistence Layer"
Cohesion: 0.03
Nodes (58): BarcodeCache, BiomarkerResult, BodyComposition, Codable, DEXARegion, DEXAScan, FetchableRecord, Food (+50 more)

### Community 4 - "Food Data Model"
Cohesion: 0.02
Nodes (99): CodingKeys, barcode, brand, caloriesPer100g, carbsGPer100g, createdAt, fatGPer100g, fiberGPer100g (+91 more)

### Community 5 - "Model Management & Device"
Cohesion: 0.03
Nodes (38): AIBackend, DeviceCapability, AIModelManager, DownloadState, completed, downloading, error, idle (+30 more)

### Community 6 - "Supplement & Health Tracking"
Cohesion: 0.02
Nodes (76): AddMode, custom, popular, AddSupplementView, CaseIterable, FoodSortMode, carbs, fat (+68 more)

### Community 7 - "Biomarkers & Analytics UI"
Cohesion: 0.03
Nodes (39): BiomarkerRow, BiomarkersTabView, DonutRing, RangeBar, BodyCompEntryView, ContentView, View, CreateTemplateView (+31 more)

### Community 8 - "Core Database Operations"
Cohesion: 0.03
Nodes (12): AppDatabase, DefaultFoods, Recipe, loggedDays(), BBTEntry, CycleEntry, HealthKitService, OvulationEntry (+4 more)

### Community 9 - "Intent Actions & Cache"
Cohesion: 0.03
Nodes (32): Action, createWorkout, logWeight, none, showNutrition, showWeight, startWorkout, AIDataCache (+24 more)

### Community 10 - "AI Action Execution"
Cohesion: 0.06
Nodes (23): AIActionExecutor, FoodIntent, FoodMatch, WeightIntent, AIChatViewModel, AIChatViewModel, BiomarkerCardData, ChatMessage (+15 more)

### Community 11 - "AI Response Parsing"
Cohesion: 0.06
Nodes (24): AIActionParser, WorkoutExercise, AIResponseCleaner, AgentOutput, AIToolAgent, StreamState, CGMImportService, ImportResult (+16 more)

### Community 12 - "Conversation State Machine"
Cohesion: 0.04
Nodes (40): GeneratingState, generating, idle, thinking, ConversationState, PendingIntent, awaitingConfirmation, awaitingParam (+32 more)

### Community 13 - "Templates & Barcode Data"
Cohesion: 0.06
Nodes (15): DefaultTemplates, ExerciseDatabase, ExerciseInfo, ExerciseService, LookupError, networkError, noNutrition, notFound (+7 more)

### Community 14 - "Biomarker Definitions"
Cohesion: 0.04
Nodes (25): BiomarkerDefinition, BiomarkerStatus, optimal, outOfRange, sufficient, CodingKeys, absoluteHigh, absoluteLow (+17 more)

### Community 15 - "Active Workout UI"
Cohesion: 0.07
Nodes (26): ActiveExercise, ActiveSet, ActiveWorkoutView, CodingKeys, bodyPart, category, createdAt, date (+18 more)

### Community 16 - "Charts & Layout"
Cohesion: 0.09
Nodes (15): ChartPoint, FlowLayout, LayoutResult, Layout, PlantPeriod, day, week, PlantPointsCardView (+7 more)

### Community 17 - "BodySpec PDF Import"
Cohesion: 0.09
Nodes (23): BodySpecPDFParser, ParsedRegion, ParsedScan, Supplemental, CodingKeys, agRatio, armsFatPct, bodyFatPct (+15 more)

### Community 18 - "Barcode Scanner"
Cohesion: 0.08
Nodes (11): AVCaptureMetadataOutputObjectsDelegate, BarcodeScannerView, CameraView, Coordinator, NutritionPhotoCaptureView, ScannerViewController, ShareSheet, UIImagePickerControllerDelegate (+3 more)

### Community 19 - "TDEE Estimation"
Cohesion: 0.12
Nodes (15): Confidence, high, low, medium, Estimate, Sex, female, male (+7 more)

### Community 20 - "Lab & DEXA Data"
Cohesion: 0.09
Nodes (3): AppDatabase, DEXAEntryView, DEXAService

### Community 21 - "Food Search & Favorites"
Cohesion: 0.11
Nodes (4): AppDatabase, RecentEntry, AnyCodable, SpellCorrectService

### Community 22 - "Food Entry Model"
Cohesion: 0.11
Nodes (17): CodingKeys, calories, carbsG, createdAt, date, fatG, fiberG, foodId (+9 more)

### Community 23 - "Workout Body Map"
Cohesion: 0.21
Nodes (6): BodyMapView, MuscleStatus, moderate, recovered, recovering, untrained

### Community 24 - "Input Normalization"
Cohesion: 0.36
Nodes (1): InputNormalizer

### Community 25 - "App Entry Point"
Cohesion: 0.67
Nodes (2): App, DriftApp

### Community 26 - "Saved Food Model"
Cohesion: 0.67
Nodes (1): Food

### Community 27 - "Logging Utility"
Cohesion: 1.0
Nodes (1): Log

### Community 28 - "Date Utilities"
Cohesion: 1.0
Nodes (1): DateFormatters

## Knowledge Gaps
- **375 isolated node(s):** `oneWeek`, `oneMonth`, `threeMonths`, `sixMonths`, `oneYear` (+370 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Logging Utility`** (2 nodes): `Log.swift`, `Log`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Date Utilities`** (2 nodes): `DateFormatters`, `DateFormatters.swift`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `date` connect `AI Planning & Workout Flow` to `AI Chat & Food Log UI`, `AI Backend & Model Types`, `Data Persistence Layer`, `Food Data Model`, `Supplement & Health Tracking`, `Biomarkers & Analytics UI`, `Core Database Operations`, `Intent Actions & Cache`, `AI Action Execution`, `AI Response Parsing`, `Conversation State Machine`, `Templates & Barcode Data`, `Active Workout UI`, `Charts & Layout`, `TDEE Estimation`, `Food Search & Favorites`?**
  _High betweenness centrality (0.065) - this node is a cross-community bridge._
- **Why does `AppDatabase` connect `Core Database Operations` to `AI Chat & Food Log UI`, `AI Planning & Workout Flow`, `AI Backend & Model Types`, `Data Persistence Layer`, `Intent Actions & Cache`, `AI Response Parsing`, `Food Search & Favorites`?**
  _High betweenness centrality (0.054) - this node is a cross-community bridge._
- **Why does `text` connect `AI Chat & Food Log UI` to `AI Backend & Model Types`, `Model Management & Device`, `Supplement & Health Tracking`, `Biomarkers & Analytics UI`, `Intent Actions & Cache`, `AI Action Execution`, `AI Response Parsing`, `Templates & Barcode Data`, `Biomarker Definitions`, `Active Workout UI`, `Charts & Layout`, `Lab & DEXA Data`, `Workout Body Map`, `Input Normalization`?**
  _High betweenness centrality (0.049) - this node is a cross-community bridge._
- **Are the 171 inferred relationships involving `String` (e.g. with `.toggleSupplementTaken()` and `.trackFoodUsage()`) actually correct?**
  _`String` has 171 INFERRED edges - model-reasoned connections that need verification._
- **Are the 125 inferred relationships involving `date` (e.g. with `.toggleSupplementTaken()` and `.trackFoodUsage()`) actually correct?**
  _`date` has 125 INFERRED edges - model-reasoned connections that need verification._
- **Are the 103 inferred relationships involving `text` (e.g. with `.fieldRow()` and `.entryRow()`) actually correct?**
  _`text` has 103 INFERRED edges - model-reasoned connections that need verification._
- **Are the 72 inferred relationships involving `weight` (e.g. with `.entryRow()` and `.bodyCompCard()`) actually correct?**
  _`weight` has 72 INFERRED edges - model-reasoned connections that need verification._