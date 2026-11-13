import Foundation

/// Text of the pre-run warning "this card was already copied under another name".
/// Pure, so it can be tested without a catalog on disk.
enum EarlierCopyWarning {

    struct Card {
        /// Roll folder name this run will use.
        let plannedName: String
        let earlier: [CatalogEarlierCopy]
    }

    /// Nil when no card was copied before under a different roll name. The same name
    /// is the normal case (second drive, resume) and is not warned about.
    static func message(for cards: [Card], formatDate: (Date) -> String) -> String? {
        var lines: [String] = []
        for card in cards {
            for hit in card.earlier where hit.roll.rollName != card.plannedName {
                let drives = orderedUnique(hit.roll.copies.map(\.destVolumeName))
                let latest = hit.roll.copies.map(\.date).max() ?? hit.roll.firstBackedUp
                let clips = hit.matchingClips >= hit.cardClips
                    ? "“\(card.plannedName)”"
                    : "\(hit.matchingClips) of \(hit.cardClips) clips of “\(card.plannedName)”"
                lines.append("\(clips) already copied as “\(hit.roll.rollName)” on "
                             + "\(drives.joined(separator: ", ")) (\(formatDate(latest))).")
            }
        }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
            + "\n\nThe folders on your drives will have different names for the same card."
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
