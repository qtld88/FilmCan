import Foundation

struct RollNumbering: Codable, Equatable {
    var enabled = false
    var cameraPrefix = "A"
    var soundPrefix = "S"
    var digits = 3
    var cameraStart = 1
    var soundStart = 1
    /// ARRI / RED cards keep their own reel name.
    var keepCameraReelNames = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        cameraPrefix = try c.decodeIfPresent(String.self, forKey: .cameraPrefix) ?? "A"
        soundPrefix = try c.decodeIfPresent(String.self, forKey: .soundPrefix) ?? "S"
        digits = try c.decodeIfPresent(Int.self, forKey: .digits) ?? 3
        cameraStart = try c.decodeIfPresent(Int.self, forKey: .cameraStart) ?? 1
        soundStart = try c.decodeIfPresent(Int.self, forKey: .soundStart) ?? 1
        keepCameraReelNames = try c.decodeIfPresent(Bool.self, forKey: .keepCameraReelNames) ?? true
    }
}

enum CardRole: String, Codable { case camera, sound, notACard }

enum ShootDayCounter {
    /// First run on a new calendar day (vs lastRun, in `calendar`) ⇒ increment the trailing
    /// number of `day`, keeping its width ("Day01"→"Day02", "D9"→"D10", "Day099"→"Day100").
    /// Empty day ⇒ "Day01". Day without trailing digits ⇒ unchanged. lastRun nil ⇒ unchanged
    /// (the user's typed value is day one). Same day ⇒ unchanged.
    static func advance(day: String, lastRun: Date?, now: Date, calendar: Calendar) -> String {
        let trimmed = day.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Day01" }
        guard let lastRun else { return day }
        if calendar.isDate(lastRun, inSameDayAs: now) { return day }
        let digits = trimmed.reversed().prefix { $0.isNumber }
        guard !digits.isEmpty else { return day }
        let numberString = String(digits.reversed())
        guard let value = Int(numberString) else { return day }
        let prefix = String(trimmed.dropLast(numberString.count))
        let next = String(value + 1)
        let padded = String(repeating: "0", count: max(0, numberString.count - next.count)) + next
        return prefix + padded
    }
}
