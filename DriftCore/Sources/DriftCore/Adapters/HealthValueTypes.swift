import Foundation

/// Sleep stages for one night, surfaced from HealthKit. Cross-platform value
/// type so services in DriftCore can consume it through the
/// `HealthDataProvider` adapter without importing HealthKit.
public struct SleepDetail: Sendable {
    public let totalHours: Double
    public let remHours: Double
    public let deepHours: Double
    public let lightHours: Double
    public let awakeHours: Double
    public let bedStart: Date?
    public let bedEnd: Date?

    public init(totalHours: Double, remHours: Double, deepHours: Double,
                lightHours: Double, awakeHours: Double,
                bedStart: Date?, bedEnd: Date?) {
        self.totalHours = totalHours
        self.remHours = remHours
        self.deepHours = deepHours
        self.lightHours = lightHours
        self.awakeHours = awakeHours
        self.bedStart = bedStart
        self.bedEnd = bedEnd
    }
}

/// One day's menstrual flow signal sourced from HealthKit (`HKCategoryType
/// .menstrualFlow`). Cross-platform value type.
public struct CycleEntry: Sendable, Identifiable {
    public let id = UUID()
    public let date: Date
    public let flow: Int // 1=light, 2=medium, 3=heavy, 4=none/spotting ended

    public init(date: Date, flow: Int) {
        self.date = date
        self.flow = flow
    }

    /// HK: 1=unspecified, 2=light, 3=medium, 4=heavy, 5=none
    public var flowDisplay: String {
        switch flow {
        case 1: "Unspecified"
        case 2: "Light"
        case 3: "Medium"
        case 4: "Heavy"
        case 5: "None"
        default: "Unknown"
        }
    }
}

public struct OvulationEntry: Sendable, Identifiable {
    public let id = UUID()
    public let date: Date
    public let result: Int // 1=negative, 2=LH surge, 3=indeterminate, 4=estrogen surge

    public init(date: Date, result: Int) {
        self.date = date
        self.result = result
    }

    public var isPositive: Bool { result == 2 || result == 4 }
}

public struct BBTEntry: Sendable, Identifiable {
    public let id = UUID()
    public let date: Date
    public let temperatureCelsius: Double

    public init(date: Date, temperatureCelsius: Double) {
        self.date = date
        self.temperatureCelsius = temperatureCelsius
    }
}

public struct SpottingEntry: Sendable, Identifiable {
    public let id = UUID()
    public let date: Date

    public init(date: Date) {
        self.date = date
    }
}
