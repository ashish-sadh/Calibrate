import Foundation

/// Cross-platform value type for a parsed BodySpec DEXA PDF. The parser
/// itself stays in iOS (it uses PDFKit / Vision via the iOS BodySpecPDFParser);
/// AppDatabase only needs the data shape to import a batch of scans.
public struct BodySpecParsedScan: Sendable {
    public let scanDate: String
    public let bodyFatPct: Double?
    public let totalMassLbs: Double?
    public let fatMassLbs: Double?
    public let leanMassLbs: Double?
    public let bmcLbs: Double?
    public let rmrCalories: Double?
    public let vatMassLbs: Double?
    public let vatVolumeIn3: Double?
    public let agRatio: Double?
    public let boneDensityTotal: Double?
    public let regions: [BodySpecParsedRegion]

    public init(
        scanDate: String,
        bodyFatPct: Double? = nil,
        totalMassLbs: Double? = nil,
        fatMassLbs: Double? = nil,
        leanMassLbs: Double? = nil,
        bmcLbs: Double? = nil,
        rmrCalories: Double? = nil,
        vatMassLbs: Double? = nil,
        vatVolumeIn3: Double? = nil,
        agRatio: Double? = nil,
        boneDensityTotal: Double? = nil,
        regions: [BodySpecParsedRegion] = []
    ) {
        self.scanDate = scanDate
        self.bodyFatPct = bodyFatPct
        self.totalMassLbs = totalMassLbs
        self.fatMassLbs = fatMassLbs
        self.leanMassLbs = leanMassLbs
        self.bmcLbs = bmcLbs
        self.rmrCalories = rmrCalories
        self.vatMassLbs = vatMassLbs
        self.vatVolumeIn3 = vatVolumeIn3
        self.agRatio = agRatio
        self.boneDensityTotal = boneDensityTotal
        self.regions = regions
    }
}

public struct BodySpecParsedRegion: Sendable {
    public let name: String
    public let fatPct: Double?
    public let totalMassLbs: Double?
    public let fatMassLbs: Double?
    public let leanMassLbs: Double?
    public let bmcLbs: Double?

    public init(
        name: String,
        fatPct: Double? = nil,
        totalMassLbs: Double? = nil,
        fatMassLbs: Double? = nil,
        leanMassLbs: Double? = nil,
        bmcLbs: Double? = nil
    ) {
        self.name = name
        self.fatPct = fatPct
        self.totalMassLbs = totalMassLbs
        self.fatMassLbs = fatMassLbs
        self.leanMassLbs = leanMassLbs
        self.bmcLbs = bmcLbs
    }
}
