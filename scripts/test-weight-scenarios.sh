#!/bin/bash
# Test scenarios for weight UX changes
# Run from project root: ./scripts/test-weight-scenarios.sh [scenario]
#
# Scenarios:
#   fresh    - No weight data at all (new user)
#   stale    - Weight from 90 days ago, nothing recent
#   recent   - Weight logged today + yesterday (normal user)
#   mixed    - HealthKit + manual on same day (test priority)
#   profile  - Clear profile fields (test nudge)
#   reset    - Clear all test data

echo "⚠️  These scenarios modify your local database!"
echo "Make sure you're running the app in the simulator."
echo ""

# Find the simulator DB
DB_DIR="$HOME/Library/Developer/CoreSimulator/Devices"
DB_PATH=$(find "$DB_DIR" -name "drift.sqlite" -path "*/Application Support/Drift/*" 2>/dev/null | head -1)

if [ -z "$DB_PATH" ]; then
    echo "❌ Can't find drift.sqlite. Make sure the app has been run in the simulator at least once."
    exit 1
fi

echo "📂 Database: $DB_PATH"
echo ""

case "${1:-help}" in
    fresh)
        echo "🧹 Scenario: FRESH — removing all weight entries"
        sqlite3 "$DB_PATH" "DELETE FROM weight_entry;"
        echo "✅ All weight entries deleted. Dashboard should show 'Log weight' prompt."
        echo "   Goal page should show stale warning."
        ;;
    stale)
        echo "📅 Scenario: STALE — weight from 90 days ago only"
        sqlite3 "$DB_PATH" "DELETE FROM weight_entry;"
        sqlite3 "$DB_PATH" "INSERT INTO weight_entry (date, weight_kg, source, created_at, synced_from_hk, hidden) VALUES (date('now', '-90 days'), 80.0, 'manual', datetime('now'), 0, 0);"
        echo "✅ Added weight entry from 90 days ago (80 kg)."
        echo "   Dashboard should show stale weight with 'Tap to update'."
        echo "   No trend/surplus should appear."
        ;;
    recent)
        echo "📊 Scenario: RECENT — weight today + yesterday"
        sqlite3 "$DB_PATH" "DELETE FROM weight_entry;"
        sqlite3 "$DB_PATH" "INSERT INTO weight_entry (date, weight_kg, source, created_at, synced_from_hk, hidden) VALUES (date('now', '-1 day'), 81.0, 'manual', datetime('now'), 0, 0);"
        sqlite3 "$DB_PATH" "INSERT INTO weight_entry (date, weight_kg, source, created_at, synced_from_hk, hidden) VALUES (date('now'), 80.5, 'manual', datetime('now'), 0, 0);"
        echo "✅ Added 81.0 kg yesterday, 80.5 kg today."
        echo "   Dashboard should show fresh weight with trend."
        ;;
    mixed)
        echo "🔀 Scenario: MIXED — manual + HealthKit on same day"
        sqlite3 "$DB_PATH" "DELETE FROM weight_entry WHERE date = date('now');"
        sqlite3 "$DB_PATH" "INSERT INTO weight_entry (date, weight_kg, source, created_at, synced_from_hk, hidden) VALUES (date('now'), 79.0, 'manual', datetime('now'), 0, 0);"
        echo "✅ Added manual entry 79.0 kg for today."
        echo "   Next HealthKit sync should NOT overwrite this."
        echo "   Check: weight stays 79.0 after sync."
        ;;
    hidden)
        echo "👻 Scenario: HIDDEN — delete today's entry (soft-delete)"
        sqlite3 "$DB_PATH" "UPDATE weight_entry SET hidden = 1 WHERE date = date('now');"
        echo "✅ Today's entry hidden. Should disappear from history."
        echo "   HealthKit sync should NOT bring it back."
        ;;
    profile)
        echo "👤 Scenario: PROFILE — clear profile fields"
        # Clear TDEEConfig from UserDefaults
        PLIST_PATH=$(find "$DB_DIR" -name "com.drift.health.plist" -path "*/Library/Preferences/*" 2>/dev/null | head -1)
        if [ -n "$PLIST_PATH" ]; then
            defaults delete "$PLIST_PATH" drift_tdee_config 2>/dev/null
            echo "✅ Profile cleared. Dashboard should show 'Complete your profile' nudge."
        else
            echo "⚠️  Can't find preferences file. Try clearing profile from the app."
        fi
        ;;
    reset)
        echo "🔄 Scenario: RESET — restore reasonable test data"
        sqlite3 "$DB_PATH" "DELETE FROM weight_entry;"
        for i in $(seq 14 -1 0); do
            kg=$(echo "80.0 - $i * 0.1" | bc)
            sqlite3 "$DB_PATH" "INSERT INTO weight_entry (date, weight_kg, source, created_at, synced_from_hk, hidden) VALUES (date('now', '-$i days'), $kg, 'manual', datetime('now'), 0, 0);"
        done
        echo "✅ Added 15 days of weight data (80.0 → 78.6 kg, slight loss)."
        echo "   Dashboard should show healthy trend."
        ;;
    newuser)
        echo "🆕 Scenario: NEWUSER — stale weight + goal + empty profile"
        # Stale weight (90 days ago)
        sqlite3 "$DB_PATH" "DELETE FROM weight_entry;"
        sqlite3 "$DB_PATH" "INSERT INTO weight_entry (date, weight_kg, source, created_at, synced_from_hk, hidden) VALUES (date('now', '-90 days'), 80.0, 'manual', datetime('now'), 0, 0);"
        # Clear profile (TDEEConfig)
        PLIST_PATH=$(find "$DB_DIR" -name "com.drift.health.plist" -path "*/Library/Preferences/*" 2>/dev/null | head -1)
        if [ -n "$PLIST_PATH" ]; then
            defaults delete "$PLIST_PATH" drift_tdee_config 2>/dev/null
        fi
        # Set a weight goal via UserDefaults (target 72kg in 3 months)
        GOAL_JSON='{"targetWeightKg":72,"monthsToAchieve":3,"startDate":"'"$(date +%Y-%m-%d)"'","startWeightKg":80}'
        defaults write "$PLIST_PATH" drift_weight_goal -string "$GOAL_JSON"
        echo "✅ Stale weight (80 kg, 90 days ago) + goal (72 kg in 3 mo) + empty profile."
        echo "   Dashboard: stale weight warning, no surplus/deficit."
        echo "   Goal page: profile auto-expands, all fields 'Not set', staleness warning on goal card."
        ;;
    *)
        echo "Usage: $0 [scenario]"
        echo ""
        echo "Scenarios:"
        echo "  fresh    No weight data (new user)"
        echo "  stale    Weight from 90 days ago only"
        echo "  recent   Weight today + yesterday"
        echo "  mixed    Manual entry (test HealthKit priority)"
        echo "  hidden   Soft-delete today's entry"
        echo "  profile  Clear profile (test nudge)"
        echo "  reset    15 days of gradual weight loss"
        echo "  newuser  Stale weight + goal + empty profile (full test)"
        echo ""
        echo "After running a scenario, relaunch the app in the simulator to see the effect."
        ;;
esac
