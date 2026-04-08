# AI Chat vs UI — Feature Parity Log

AI chat is the showstopper. This log tracks what's available from chat vs UI-only.
The self-improvement loop picks from the **Gap** section to close parity.

## Available from AI Chat

### Food & Nutrition
- [x] Log single food ("log 2 eggs", "ate chicken")
- [x] Log multiple foods ("log chicken and rice")
- [x] Log meal with recipe builder ("log lunch" → list ingredients → recipe)
- [x] Nutrition lookup ("calories in banana", "protein in chicken")
- [x] Meal suggestions ("what should I eat")
- [x] Calories remaining ("calories left")
- [x] Protein status ("how's my protein")
- [x] Daily summary, weekly summary, yesterday summary
- [x] Explain TDEE ("explain calories")
- [x] Gram-based logging ("log paneer biryani 300 gram")

### Weight
- [x] Log weight ("I weigh 165", "weight is 75.2 kg")
- [x] Weight trend info ("how's my weight", "am I on track")
- [x] Goal progress

### Exercise
- [x] Start template ("start push day")
- [x] Smart workout with reasoning ("start smart workout", "coach me today")
- [x] Log exercises ("add exercise" → list exercises)
- [x] Workout suggestion ("what should I train")
- [x] Progressive overload check
- [x] Workout streak info

### Health
- [x] Sleep/recovery/readiness
- [x] Supplement status ("did I take everything")
- [x] Glucose readings + spike detection
- [x] Biomarker results
- [x] Body composition info

## Gap: UI-Only Features to Bring to AI Chat

### P0 — High Impact Friction Reducers
- [x] **Mark supplement taken** — "took my creatine", "took vitamin D". StaticOverrides handler.
- [x] **Edit/delete food entry** — "remove the rice", "delete last entry". StaticOverrides handler.
- [x] **Copy yesterday's food** — "copy yesterday", "same as yesterday". StaticOverrides handler.
- [x] **Quick-add raw calories** — "just log 500 cal for lunch". StaticOverrides handler.
- [x] **Set/update weight goal** — "set goal to 160 lbs", "I want to lose 10 lbs". StaticOverrides regex + word number resolver.

### P1 — Data Entry from Chat
- [ ] **Trigger barcode scan** — "scan barcode", "scan food". Needs: open camera from chat.
- [x] **Manual food with macros** — "log 400 cal 30g protein lunch". StaticOverrides inline macro parser.
- [x] **Body comp entry** — "my body fat is 18%", "log body fat 18". StaticOverrides regex handler.
- [x] **Add supplement to stack** — "add vitamin D", "add creatine 5g". add_supplement tool in ToolRegistration.

### P2 — Multi-Turn Intelligence (Gemma 4 Only)
- [ ] **Meal planning** — "plan my meals for today" → iterative suggestions based on remaining macros + history.
- [ ] **Workout split builder** — "build me a PPL split" → multi-turn designing across sessions.
- [ ] **Cross-domain analysis** — "why am I not losing weight?" → combines food + weight + exercise data.
- [ ] **Weekly comparison** — "compare this week to last" → trend analysis with data.
- [ ] **Coaching dialogue** — "am I eating enough protein for my workouts?" → contextual advice using real data.

### P3 — Nice to Have
- [ ] **Navigate to screen** — "show me my weight chart", "go to food tab". Needs: navigation tool.
- [ ] **Export data** — "export my food log". Needs: CSV generation + share sheet.
- [ ] **Import workout** — "import from Strong". Needs: file picker from chat.

## UI Stays Best For
These are better as traditional UI — don't need AI chat parity:
- Interactive charts (weight, glucose, biomarkers) — visual, zoomable, tap-to-inspect
- Food diary editing (swipe to delete, tap to edit servings)
- Exercise browser (search 873 exercises, filter by muscle)
- Settings, algorithm tuning, HealthKit controls
- Cycle tracking calendar view
- Lab report PDF upload + OCR
- DEXA scan comparison
