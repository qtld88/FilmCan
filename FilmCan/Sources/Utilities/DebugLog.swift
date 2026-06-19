import Foundation
import os

/// Diagnostics. `info` stays debug-only (chatty); `warn`/`error` go to the unified
/// log in ALL builds so failures (keychain, webhook, MHL seal, save) are
/// diagnosable in the field — previously they were `#if DEBUG print` only, leaving
/// release builds completely silent on data-integrity failures.
///
/// Messages carry error descriptions and file paths (useful for support) but never
/// secrets — bearer tokens / keychain values are never passed here.
enum DebugLog {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.filmcan.app", category: "FilmCan")

    static func info(_ message: String) {
        #if DEBUG
        print(message)
        #endif
        logger.debug("\(message, privacy: .public)")
    }

    static func warn(_ message: String) {
        #if DEBUG
        print(message)
        #endif
        logger.warning("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        #if DEBUG
        print(message)
        #endif
        logger.error("\(message, privacy: .public)")
    }
}
