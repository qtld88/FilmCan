import SwiftUI

/// Destination capacity split into free / this backup / already used, shared by the
/// main window and Quick Copy so both draw the same bar with the same colours.
struct DriveCapacityInfo {
    let ratioToAvailable: Double?
    let hasTotal: Bool
    let usedRatio: Double
    let backupRatio: Double
    let freeRatio: Double
    let usedPercent: Int
    let backupPercent: Int
    let freePercent: Int
    let usedColor: Color
    let freeColor: Color
    let backupSegmentColor: Color

    init(requiredBytes: Int64, available: Int64?, total: Int64?, treatBackupAsUsed: Bool = false) {
        let totalBytes = total ?? 0
        let hasTotal = totalBytes > 0 && available != nil
        let availableBytes = available ?? 0
        let usedBytes = max(totalBytes - availableBytes, 0)
        let backupBytes: Int64
        let usedOtherBytes: Int64
        let freeAfterBytes: Int64
        let effectiveRequiredForSpace: Int64
        if treatBackupAsUsed {
            backupBytes = min(requiredBytes, usedBytes)
            usedOtherBytes = max(usedBytes - backupBytes, 0)
            freeAfterBytes = max(totalBytes - usedBytes, 0)
            effectiveRequiredForSpace = 0
        } else {
            backupBytes = min(requiredBytes, max(availableBytes, 0))
            usedOtherBytes = usedBytes
            freeAfterBytes = max(totalBytes - usedBytes - backupBytes, 0)
            effectiveRequiredForSpace = requiredBytes
        }
        let ratioToAvailable = available.map { availableBytes -> Double in
            if effectiveRequiredForSpace <= 0 { return 0.0 }
            if availableBytes <= 0 { return Double.infinity }
            return Double(effectiveRequiredForSpace) / Double(availableBytes)
        }
        self.ratioToAvailable = ratioToAvailable
        self.hasTotal = hasTotal
        usedRatio = hasTotal ? Double(usedOtherBytes) / Double(totalBytes) : 0
        backupRatio = hasTotal ? Double(backupBytes) / Double(totalBytes) : 0
        freeRatio = hasTotal ? Double(freeAfterBytes) / Double(totalBytes) : 0
        usedPercent = Int(round(usedRatio * 100))
        backupPercent = Int(round(backupRatio * 100))
        freePercent = max(0, 100 - usedPercent - backupPercent)
        usedColor = FCCapacity.used
        freeColor = FCCapacity.free
        backupSegmentColor = FCCapacity.toCopyColor(
            ratioToAvailable: ratioToAvailable,
            backupFraction: backupRatio,
            alreadyStored: treatBackupAsUsed
        )
    }

    var notEnoughSpace: Bool { ratioToAvailable.map { $0 > 1.0 } == true }
}

struct DriveCapacityBar: View {
    let info: DriveCapacityInfo
    let requiredBytes: Int64

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(FCCapacity.track)
                if info.hasTotal {
                    HStack(spacing: 0) {
                        // Same order as the main window's vertical bar read bottom to top.
                        Rectangle()
                            .fill(info.usedColor)
                            .frame(width: geo.size.width * info.usedRatio)
                        Rectangle()
                            .fill(info.backupSegmentColor.opacity(FCCapacity.toCopyOpacity))
                            .frame(width: geo.size.width * info.backupRatio)
                        Rectangle()
                            .fill(info.freeColor)
                            .frame(width: geo.size.width * info.freeRatio)
                    }
                    .animation(.easeInOut(duration: 0.5), value: requiredBytes)
                } else {
                    Rectangle()
                        .fill(info.backupSegmentColor.opacity(FCCapacity.toCopyOpacity))
                        .frame(width: geo.size.width * min(1.0, info.ratioToAvailable ?? 0))
                        .animation(.easeInOut(duration: 0.5), value: requiredBytes)
                }
            }
            .cornerRadius(4)
        }
        .frame(height: 12)
        .accessibilityElement()
        .accessibilityLabel("Drive space")
        .accessibilityValue(info.hasTotal
            ? "\(info.usedPercent) percent used, \(info.backupPercent) percent to copy, \(info.freePercent) percent free after"
            : "Capacity unknown")
    }
}
