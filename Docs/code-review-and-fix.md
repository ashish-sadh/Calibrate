# Calibrate - Code Review & Fix Process

## Review Checklist

### Before Each Commit
- [ ] `xcodebuild build` succeeds with zero errors
- [ ] `xcodebuild test` passes all unit tests
- [ ] No force-unwraps (`!`) except in test fixtures
- [ ] No hardcoded strings that should be localized (skip for v1)
- [ ] Database migrations are additive (never modify existing migrations)
- [ ] GRDB records conform to required protocols
- [ ] SwiftUI previews compile (use `AppDatabase.empty()`)
- [ ] No retain cycles in closures (use `[weak self]` where needed)

### Architecture Rules
1. **Views** never access database directly → go through ViewModel
2. **ViewModels** are `@Observable` and `@MainActor`
3. **Services** are stateless or actors (for thread safety)
4. **Models** are value types (structs), never classes
5. **Database** writes go through `AppDatabase` methods, not raw SQL
6. **HealthKit** calls only happen in `HealthKitService`

### Common Issues to Watch

#### GRDB
- Always use `try db.write { }` for mutations (not `try db.read`)
- Use `ValueObservation` for reactive UI, not polling
- Column names in Swift must match SQLite column names exactly (snake_case)
- Use `didInsert(_:)` to capture auto-generated IDs

#### HealthKit
- Always check `HKHealthStore.isHealthDataAvailable()` before any HK calls
- Handle authorization status gracefully (user may deny specific types)
- Never assume `requestAuthorization` success means data is readable (privacy: HK returns empty, not error)
- Use anchored queries for weight sync to avoid re-processing

#### Swift Charts
- `LineMark` needs sorted data by x-axis value
- Use `.interpolationMethod(.catmullRom)` for smooth trend lines
- Large datasets: use stride/sampling to avoid rendering 10K+ points

#### SwiftUI
- `@Observable` requires iOS 17+ (our minimum target)
- Use `@Environment(AppDatabase.self)` for database injection
- Avoid heavy computation in `body` - move to ViewModel

## Fix Process

### When a Bug is Found
1. Write a failing test that reproduces the bug
2. Fix the code
3. Verify the test passes
4. Check no other tests broke
5. Commit with descriptive message

### When a Build Fails
1. Read the full error message
2. Check if it's a dependency issue (`swift package resolve`)
3. Check if it's a missing file in `project.yml` → re-run `xcodegen generate`
4. Check if it's a type mismatch (common with GRDB column mappings)
5. Fix and verify clean build

### When Tests Fail
1. Run the specific failing test in isolation
2. Check test fixtures are correct
3. Check if database schema changed without updating test setup
4. Check if HealthKit mock needs updating
5. Fix and verify all tests pass

## Iteration Cycle

```
Write spec (Docs/*.md)
  → Implement code
    → Build (xcodebuild build)
      → Fix build errors
        → Write tests
          → Run tests (xcodebuild test)
            → Fix test failures
              → Manual test on Simulator/Device
                → Fix UI issues
                  → Commit + push
                    → Next feature
```

## Git Workflow
- Commit after each phase completes
- Push to `main` (solo developer)
- Commit messages: `feat: <phase description>` or `fix: <what was fixed>`
- Tag releases: `v0.1.0` (Phase 0-3), `v0.2.0` (Phase 4-5), `v0.3.0` (Phase 6-8)
