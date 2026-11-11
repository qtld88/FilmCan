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
