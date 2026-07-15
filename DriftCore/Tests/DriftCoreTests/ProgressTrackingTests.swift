import Testing
import Foundation
@testable import DriftCore

/// Tier 0 — body-measurement + progress-photo models, analysis, and
/// persistence. Uses the in-memory AppDatabase for the CRUD half.
struct ProgressTrackingTests {

    // MARK: - Measurement model

    @Test func measurementJSONMapRoundTrips() {
        var m = BodyMeasurement(date: "2026-07-14")
        m.measurementsCm[MeasurementSite.waist.rawValue] = 82.5
        m.measurementsCm[MeasurementSite.chest.rawValue] = 102.0
        #expect(m.value(for: .waist) == 82.5)
        #expect(m.value(for: .chest) == 102.0)
        #expect(m.value(for: .neck) == nil)
        #expect(!m.isEmpty)
    }

    @Test func poseRelevantSitesAreSideAppropriate() {
        // Front shows torso girths; sides show that side's limbs + waist.
        #expect(ProgressPose.front.relevantSites.contains(.chest))
        #expect(ProgressPose.front.relevantSites.contains(.waist))
        #expect(ProgressPose.left.relevantSites.contains(.leftBicep))
        #expect(ProgressPose.left.relevantSites.contains(.leftThigh))
        #expect(!ProgressPose.left.relevantSites.contains(.rightBicep))
        #expect(ProgressPose.right.relevantSites.contains(.rightCalf))
        #expect(!ProgressPose.right.relevantSites.contains(.leftCalf))
        // Every pose surfaces the waist (the universal reference).
        for pose in ProgressPose.allCases {
            #expect(pose.relevantSites.contains(.waist))
        }
    }

    @Test func measurementSiteMetadata() {
        #expect(MeasurementSite.leftBicep.mirror == .rightBicep)
        #expect(MeasurementSite.waist.mirror == nil)
        #expect(MeasurementSite.chest.group == .upper)
        #expect(MeasurementSite.waist.group == .core)
        #expect(MeasurementSite.leftCalf.group == .lower)
        #expect(MeasurementSite.displayOrder.count == MeasurementSite.allCases.count)
    }

    // MARK: - Analysis

    @Test func deltasComputedForSharedSitesOnly() {
        var prev = BodyMeasurement(date: "2026-06-01")
        prev.measurementsCm = [
            MeasurementSite.waist.rawValue: 85, MeasurementSite.chest.rawValue: 100,
            MeasurementSite.neck.rawValue: 40]
        var cur = BodyMeasurement(date: "2026-07-01")
        cur.measurementsCm = [
            MeasurementSite.waist.rawValue: 82, MeasurementSite.chest.rawValue: 101]  // neck dropped
        let deltas = BodyMeasurementAnalysis.deltas(from: prev, to: cur)
        #expect(deltas.count == 2)
        let waist = deltas.first { $0.site == .waist }!
        #expect(waist.changeCm == -3)
        let chest = deltas.first { $0.site == .chest }!
        #expect(chest.changeCm == 1)
    }

    @Test func symmetryFindsLargerSide() {
        var m = BodyMeasurement(date: "2026-07-14")
        m.measurementsCm = [
            MeasurementSite.leftBicep.rawValue: 38.0,
            MeasurementSite.rightBicep.rawValue: 39.5,
            MeasurementSite.leftThigh.rawValue: 58.0,
            MeasurementSite.rightThigh.rawValue: 58.2]  // within noise
        let sym = BodyMeasurementAnalysis.symmetry(in: m)
        // Bicep imbalance (1.5) sorts before thigh (0.2).
        #expect(sym.first?.leftSite == .leftBicep)
        #expect(sym.first?.largerSide == .rightBicep)
        #expect(sym.first?.differenceCm == 1.5)
        // Thigh within 0.5 cm → no larger side.
        let thigh = sym.first { $0.leftSite == .leftThigh }!
        #expect(thigh.largerSide == nil)
    }

    @Test func changeSummaryLeadsWithBiggestMoves() {
        var prev = BodyMeasurement(date: "2026-06-01")
        prev.measurementsCm = [
            MeasurementSite.waist.rawValue: 85, MeasurementSite.chest.rawValue: 100,
            MeasurementSite.neck.rawValue: 40]
        var cur = BodyMeasurement(date: "2026-07-01")
        cur.measurementsCm = [
            MeasurementSite.waist.rawValue: 82, MeasurementSite.chest.rawValue: 101,
            MeasurementSite.neck.rawValue: 40.2]  // 0.2 change → below 0.5 threshold, excluded
        let summary = try! #require(BodyMeasurementAnalysis.changeSummary(from: prev, to: cur, inInches: false))
        #expect(summary.contains("Waist −3"))
        #expect(summary.contains("Chest +1"))
        #expect(!summary.contains("Neck"))   // sub-threshold move dropped
    }

    @Test func changeSummaryNilWhenNoMeaningfulChange() {
        var prev = BodyMeasurement(date: "2026-06-01")
        prev.measurementsCm = [MeasurementSite.waist.rawValue: 85]
        var cur = BodyMeasurement(date: "2026-07-01")
        cur.measurementsCm = [MeasurementSite.waist.rawValue: 85.2]
        #expect(BodyMeasurementAnalysis.changeSummary(from: prev, to: cur, inInches: false) == nil)
    }

    @Test func unitConversionRoundTrips() {
        let cm = BodyMeasurementAnalysis.cm(fromInches: 32)
        #expect(abs(cm - 81.28) < 0.01)
        #expect(abs(BodyMeasurementAnalysis.inches(fromCm: 81.28) - 32) < 0.01)
    }

    // MARK: - Intelligent comparisons

    @Test func waistToHipRatioClassified() {
        var m = BodyMeasurement(date: "2026-07-14")
        m.measurementsCm = [MeasurementSite.waist.rawValue: 80, MeasurementSite.hips.rawValue: 100]
        let ratios = BodyMeasurementAnalysis.ratios(in: m)
        let whr = try! #require(ratios.first { $0.id == "whr" })
        #expect(abs(whr.value - 0.8) < 0.001)
        #expect(whr.interpretation.contains("lower-risk"))
    }

    @Test func waistToChestVTaper() {
        var m = BodyMeasurement(date: "2026-07-14")
        m.measurementsCm = [MeasurementSite.waist.rawValue: 74, MeasurementSite.chest.rawValue: 104]
        let wcr = try! #require(BodyMeasurementAnalysis.ratios(in: m).first { $0.id == "wcr" })
        #expect(wcr.interpretation.contains("V-taper"))
    }

    @Test func biggestMoversRankedByPercent() {
        var prev = BodyMeasurement(date: "2026-06-01")
        prev.measurementsCm = [MeasurementSite.waist.rawValue: 90, MeasurementSite.leftBicep.rawValue: 35]
        var cur = BodyMeasurement(date: "2026-07-01")
        // Waist −3 (−3.3%), bicep +2 (+5.7%) → bicep is the bigger % mover.
        cur.measurementsCm = [MeasurementSite.waist.rawValue: 87, MeasurementSite.leftBicep.rawValue: 37]
        let movers = BodyMeasurementAnalysis.biggestMovers(from: prev, to: cur)
        #expect(movers.first?.site == .leftBicep)
        #expect(movers.count == 2)
    }

    @Test func ratiosEmptyWithoutPairs() {
        var m = BodyMeasurement(date: "2026-07-14")
        m.measurementsCm = [MeasurementSite.neck.rawValue: 40]
        #expect(BodyMeasurementAnalysis.ratios(in: m).isEmpty)
    }

    // MARK: - Save-time resolution (data-integrity core)

    private func field(_ entered: String, loadedText: String? = nil, loadedCm: Double? = nil, ghost: Double? = nil) -> BodyMeasurementAnalysis.FieldInput {
        .init(enteredText: entered, loadedText: loadedText, loadedCm: loadedCm, ghostCm: ghost)
    }

    @Test func resolveEmptyCheckInWritesNothing() {
        // Photo-only / empty check-in: all fields blank but ghosts present →
        // must NOT fabricate a duplicate measurement set (the regression).
        let fields: [MeasurementSite: BodyMeasurementAnalysis.FieldInput] = [
            .waist: field("", ghost: 82), .chest: field("", ghost: 100)]
        #expect(BodyMeasurementAnalysis.resolveMeasurements(fields, inInches: false).isEmpty)
    }

    @Test func resolveGhostAdoptedOnlyWhenUserLoggedSomething() {
        // User measured waist, left chest blank → chest carries forward.
        let fields: [MeasurementSite: BodyMeasurementAnalysis.FieldInput] = [
            .waist: field("80"), .chest: field("", ghost: 100)]
        let out = BodyMeasurementAnalysis.resolveMeasurements(fields, inInches: false)
        #expect(out[MeasurementSite.waist.rawValue] == 80)
        #expect(out[MeasurementSite.chest.rawValue] == 100)   // ghost adopted
    }

    @Test func resolveUntouchedFieldReusesOriginalCmNoDrift() {
        // Editing in inches: waist loaded as 82.5cm shows "32.5"; unchanged →
        // must persist the ORIGINAL 82.5, not 32.5*2.54.
        let fields: [MeasurementSite: BodyMeasurementAnalysis.FieldInput] = [
            .waist: field("32.5", loadedText: "32.5", loadedCm: 82.5, ghost: nil),
            .chest: field("40")]
        let out = BodyMeasurementAnalysis.resolveMeasurements(fields, inInches: true)
        #expect(out[MeasurementSite.waist.rawValue] == 82.5)   // no re-round drift
        #expect(abs(out[MeasurementSite.chest.rawValue]! - 40 * 2.54) < 0.001)
    }

    @Test func resolveClearedFieldIsDropped() {
        // A field that HAD a loaded value, blanked by the user, with no ghost →
        // dropped (deletion works).
        let fields: [MeasurementSite: BodyMeasurementAnalysis.FieldInput] = [
            .waist: field("", loadedText: "80", loadedCm: 80, ghost: nil),
            .chest: field("40")]
        let out = BodyMeasurementAnalysis.resolveMeasurements(fields, inInches: false)
        #expect(out[MeasurementSite.waist.rawValue] == nil)
    }

    @Test func resolveEditedFieldConverts() {
        let fields: [MeasurementSite: BodyMeasurementAnalysis.FieldInput] = [
            .waist: field("31", loadedText: "32.5", loadedCm: 82.5, ghost: nil)]
        let out = BodyMeasurementAnalysis.resolveMeasurements(fields, inInches: true)
        #expect(abs(out[MeasurementSite.waist.rawValue]! - 31 * 2.54) < 0.001)
    }

    // MARK: - Persistence

    @Test func measurementUpsertByDate() throws {
        let db = try AppDatabase.empty()
        var m = BodyMeasurement(date: "2026-07-14", measurementsCm: [MeasurementSite.waist.rawValue: 82])
        try db.saveBodyMeasurement(&m)
        #expect(m.id != nil)
        // Re-save same date → update, not duplicate.
        var m2 = BodyMeasurement(date: "2026-07-14", measurementsCm: [MeasurementSite.waist.rawValue: 80, MeasurementSite.chest.rawValue: 101])
        try db.saveBodyMeasurement(&m2)
        let all = try db.fetchBodyMeasurements()
        #expect(all.count == 1)
        #expect(all.first?.value(for: .waist) == 80)
        #expect(all.first?.value(for: .chest) == 101)
    }

    @Test func progressPhotoUpsertReturnsReplacedFilename() throws {
        let db = try AppDatabase.empty()
        var p = ProgressPhoto(date: "2026-07-14", pose: .front, filename: "a.jpg")
        let firstReplaced = try db.saveProgressPhoto(&p)
        #expect(firstReplaced == nil)
        // Re-shoot the front pose same day → replaces, returns old filename for cleanup.
        var p2 = ProgressPhoto(date: "2026-07-14", pose: .front, filename: "b.jpg")
        let replaced = try db.saveProgressPhoto(&p2)
        #expect(replaced == "a.jpg")
        let photos = try db.fetchProgressPhotos(forDate: "2026-07-14")
        #expect(photos.count == 1)
        #expect(photos.first?.filename == "b.jpg")
    }

    @Test func progressEntriesGroupPhotosAndMeasurementByDate() throws {
        let db = try AppDatabase.empty()
        var front = ProgressPhoto(date: "2026-07-14", pose: .front, filename: "f.jpg")
        var back = ProgressPhoto(date: "2026-07-14", pose: .back, filename: "b.jpg")
        try db.saveProgressPhoto(&front)
        try db.saveProgressPhoto(&back)
        var m = BodyMeasurement(date: "2026-07-14", measurementsCm: [MeasurementSite.waist.rawValue: 82])
        try db.saveBodyMeasurement(&m)
        // A photos-only earlier day.
        var older = ProgressPhoto(date: "2026-06-01", pose: .front, filename: "old.jpg")
        try db.saveProgressPhoto(&older)

        let entries = try db.fetchProgressEntries()
        #expect(entries.count == 2)
        #expect(entries.first?.date == "2026-07-14")   // newest first
        #expect(entries.first?.photos.count == 2)
        #expect(entries.first?.measurement?.value(for: .waist) == 82)
        #expect(entries.first?.photo(for: .front)?.filename == "f.jpg")
        // Older day: photos only, no measurement.
        #expect(entries.last?.measurement == nil)
        #expect(entries.last?.hasPhotos == true)
    }

    @Test func deletePhotosForDateReturnsFilenames() throws {
        let db = try AppDatabase.empty()
        var f = ProgressPhoto(date: "2026-07-14", pose: .front, filename: "f.jpg")
        var b = ProgressPhoto(date: "2026-07-14", pose: .back, filename: "b.jpg")
        try db.saveProgressPhoto(&f)
        try db.saveProgressPhoto(&b)
        let removed = try db.deleteProgressPhotos(forDate: "2026-07-14")
        #expect(Set(removed) == ["f.jpg", "b.jpg"])
        #expect(try db.fetchProgressPhotos(forDate: "2026-07-14").isEmpty)
    }

    /// The "i" guide on every check-in row: each site must carry a tape-
    /// placement sentence, and its figure highlight must resolve to REAL
    /// body-diagram slugs — an empty slug set renders a blank figure, which
    /// is exactly the silent failure this pins (vocabulary drift between
    /// MeasurementSite.highlightMuscles and BodyDiagram).
    @Test func everyMeasurementSiteHasAGuide() {
        #expect(!MeasurementSite.measuringTips.isEmpty)
        for site in MeasurementSite.allCases {
            #expect(site.tapePlacement.count > 30, "\(site) tape placement too thin")
            let slugs = site.highlightMuscles.flatMap { BodyDiagram.librarySlugs(forDriftMuscle: $0) }
            #expect(!slugs.isEmpty, "\(site) highlight resolves to no diagram region")
        }
        // Mirrored sites share one guide — left/right must not diverge.
        for site in MeasurementSite.allCases {
            if let mirror = site.mirror {
                #expect(site.tapePlacement == mirror.tapePlacement)
                #expect(site.highlightMuscles == mirror.highlightMuscles)
            }
        }
    }
}
