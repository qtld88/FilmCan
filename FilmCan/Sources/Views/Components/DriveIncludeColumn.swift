import SwiftUI

/// Left column of a source/destination drive card: a checkbox (in or out of this backup)
/// and the drive's order number, which unchecked drives don't get.
struct DriveIncludeColumn: View {
    let number: Int?
    let isIncluded: Bool
    var isLocked: Bool = false
    let setIncluded: ((Bool) -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            if let setIncluded {
                Toggle("", isOn: Binding(get: { isIncluded }, set: setIncluded))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(isLocked)
                    .help(isIncluded ? "Included in this backup — uncheck to skip this drive"
                                     : "Skipped — check to include this drive in the backup")
            }
            Text(number.map(String.init) ?? "")
                .font(FilmCanFont.label(11))
                .foregroundColor(FilmCanTheme.textSecondary)
                .frame(width: 14)
        }
    }

    /// Order numbers for the checked drives only: 1, 2, 3… skipping unchecked ones.
    static func numbers<ID: Hashable>(for ids: [ID], isIncluded: (ID) -> Bool) -> [ID: Int] {
        var result: [ID: Int] = [:]
        var next = 1
        for id in ids where isIncluded(id) {
            result[id] = next
            next += 1
        }
        return result
    }
}
