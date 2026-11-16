import Foundation

/// First-level labels of the settings, in one place so a test can hold them to the
/// rule: a label says what happens, in plain words, never the mechanism.
enum SettingsWording {
    static let movieSettings = "Movie settings"
    static let ifFileExists = "If a file already exists"
    static let checksumListFormat = "Checksum list format"
    static let folderLayout = "Folder layout"
    static let renameFiles = "Rename files"
    static let customDateInNames = "Custom date in names"

    static func verification(_ mode: VerifyMode) -> String {
        switch mode {
        case .paranoid: return "Full check (re-reads every file)"
        case .fast: return "Fast check"
        case .off: return "Off"
        }
    }

    /// Words a first-level label must not contain.
    static let avoidedTerms = ["paranoid", "bearer", "token", "hash", "policy", "template"]

    static var firstLevelLabels: [String] {
        [movieSettings, ifFileExists, checksumListFormat, folderLayout, renameFiles, customDateInNames]
            + VerifyMode.allCases.map(verification)
            + SettingsPage.allCases.map(\.title)
    }
}

/// Pages of the Settings window, listed in its sidebar.
enum SettingsPage: String, CaseIterable, Identifiable {
    case appearance, notifications, push, history, drives, recognition, hotkeys, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .notifications: return "Notifications"
        case .push: return "Phone & webhooks"
        case .history: return "History"
        case .drives: return "Drives"
        case .recognition: return "Recognition"
        case .hotkeys: return "Shortcuts"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintpalette"
        case .notifications: return "bell"
        case .push: return "paperplane"
        case .history: return "clock"
        case .drives: return "externaldrive"
        case .recognition: return "sdcard"
        case .hotkeys: return "keyboard"
        case .about: return "info.circle"
        }
    }

    /// The page to show for a stored value; an unknown value opens the first page.
    static func page(for stored: String) -> SettingsPage {
        SettingsPage(rawValue: stored) ?? .appearance
    }
}

/// Which side panel may be open next to the main screen: one at a time.
enum MovieSettingsPanel {
    /// The panel shows only while no other side pane (history, catalog) is open.
    static func isShown(wantsOpen: Bool, otherPaneOpen: Bool) -> Bool {
        wantsOpen && !otherPaneOpen
    }

    /// The settings rows need this much to show their switch or menu unclipped.
    static let minimumWidth: CGFloat = 480

    /// Below this editor width there is no room for the cards next to the panel:
    /// the panel then takes the whole editor.
    static let sideBySideEditorWidth: CGFloat = 840

    static func isSideBySide(editorWidth: CGFloat) -> Bool {
        editorWidth >= sideBySideEditorWidth
    }

    /// Width given to the panel inside an editor of `editorWidth`.
    static func width(editorWidth: CGFloat) -> CGFloat {
        guard isSideBySide(editorWidth: editorWidth) else { return editorWidth }
        return min(540, max(minimumWidth, editorWidth * 0.42))
    }
}

/// The movie settings panel stacks its groups one under the other, each one folding
/// open or closed on its title (as in Lightroom). Which groups are open is remembered
/// as a comma-separated list of group keys.
enum MovieSettingsSections {
    /// Keys in the order the groups are stacked.
    static let order = ["basic", "source", "destinations", "logs"]

    /// What a fresh install shows: the first group open.
    static let defaultStored = "basic"

    /// Horizontal inset of a group's content inside the panel, on each side.
    static let contentInset: CGFloat = 16

    static func openKeys(from stored: String) -> Set<String> {
        Set(stored.split(separator: ",").map(String.init).filter(order.contains))
    }

    static func isOpen(_ key: String, stored: String) -> Bool {
        openKeys(from: stored).contains(key)
    }

    /// Flips one group and returns the new stored value, keys kept in stacking order.
    static func toggling(_ key: String, in stored: String) -> String {
        var keys = openKeys(from: stored)
        if keys.contains(key) { keys.remove(key) } else if order.contains(key) { keys.insert(key) }
        return order.filter(keys.contains).joined(separator: ",")
    }

    /// Opens one group (a preset change shows its result), leaving the others as they are.
    static func opening(_ key: String, in stored: String) -> String {
        isOpen(key, stored: stored) ? stored : toggling(key, in: stored)
    }

    /// The width a group's rows may use: the panel minus the content inset on both sides.
    static func contentWidth(panelWidth: CGFloat) -> CGFloat {
        max(0, panelWidth - contentInset * 2)
    }
}
