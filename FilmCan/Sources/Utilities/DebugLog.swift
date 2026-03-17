import Foundation

enum DebugLog {
    static func info(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }

    static func warn(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }

    static func error(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }
}
