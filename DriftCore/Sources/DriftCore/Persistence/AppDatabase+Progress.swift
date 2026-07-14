import Foundation
import GRDB

// MARK: - Body Measurements + Progress Photos

extension AppDatabase {

    // MARK: Measurements

    /// Upsert a measurement set by date (one per day).
    public func saveBodyMeasurement(_ measurement: inout BodyMeasurement) throws {
        try writer.write { [measurement] db in
            if let existing = try BodyMeasurement.filter(Column("date") == measurement.date).fetchOne(db) {
                var updated = measurement
                updated.id = existing.id
                try updated.update(db)
            } else {
                var mutable = measurement
                try mutable.insert(db)
            }
        }
        measurement = try reader.read { db in
            try BodyMeasurement.filter(Column("date") == measurement.date).fetchOne(db)
        } ?? measurement
    }

    public func fetchBodyMeasurements() throws -> [BodyMeasurement] {
        try reader.read { db in
            try BodyMeasurement.order(Column("date").desc).fetchAll(db)
        }
    }

    public func fetchBodyMeasurement(forDate date: String) throws -> BodyMeasurement? {
        try reader.read { db in
            try BodyMeasurement.filter(Column("date") == date).fetchOne(db)
        }
    }

    public func deleteBodyMeasurement(forDate date: String) throws {
        _ = try writer.write { db in
            try BodyMeasurement.filter(Column("date") == date).deleteAll(db)
        }
    }

    // MARK: Progress photos

    /// Upsert a photo by (date, pose). Returns the previous filename if one was
    /// replaced, so the caller can delete the orphaned file on disk.
    @discardableResult
    public func saveProgressPhoto(_ photo: inout ProgressPhoto) throws -> String? {
        let previousFilename: String? = try writer.write { [photo] db in
            let existing = try ProgressPhoto
                .filter(Column("date") == photo.date && Column("pose") == photo.pose)
                .fetchOne(db)
            if let existing {
                var updated = photo
                updated.id = existing.id
                try updated.update(db)
                return existing.filename == photo.filename ? nil : existing.filename
            } else {
                var mutable = photo
                try mutable.insert(db)
                return nil
            }
        }
        photo = try reader.read { db in
            try ProgressPhoto
                .filter(Column("date") == photo.date && Column("pose") == photo.pose)
                .fetchOne(db)
        } ?? photo
        return previousFilename
    }

    public func fetchProgressPhotos() throws -> [ProgressPhoto] {
        try reader.read { db in
            try ProgressPhoto.order(Column("date").desc).fetchAll(db)
        }
    }

    public func fetchProgressPhotos(forDate date: String) throws -> [ProgressPhoto] {
        try reader.read { db in
            try ProgressPhoto.filter(Column("date") == date).fetchAll(db)
        }
    }

    /// Delete a single photo row; returns its filename so the caller removes
    /// the file from disk.
    @discardableResult
    public func deleteProgressPhoto(id: Int64) throws -> String? {
        try writer.write { db in
            let photo = try ProgressPhoto.fetchOne(db, id: id)
            _ = try ProgressPhoto.deleteOne(db, id: id)
            return photo?.filename
        }
    }

    /// Delete every photo taken on `date`; returns their filenames for disk cleanup.
    public func deleteProgressPhotos(forDate date: String) throws -> [String] {
        try writer.write { db in
            let photos = try ProgressPhoto.filter(Column("date") == date).fetchAll(db)
            _ = try ProgressPhoto.filter(Column("date") == date).deleteAll(db)
            return photos.map(\.filename)
        }
    }

    // MARK: Combined entries

    /// All progress entries (a day's photos + that day's measurement), newest
    /// first. Days with only photos or only a measurement are both included.
    public func fetchProgressEntries() throws -> [ProgressEntry] {
        let photos = try fetchProgressPhotos()
        let measurements = try fetchBodyMeasurements()
        let photosByDate = Dictionary(grouping: photos, by: \.date)
        let measurementByDate = Dictionary(measurements.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let dates = Set(photosByDate.keys).union(measurementByDate.keys)
        return dates.sorted(by: >).map { date in
            ProgressEntry(date: date, photos: photosByDate[date] ?? [], measurement: measurementByDate[date])
        }
    }
}
