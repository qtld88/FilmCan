import Foundation
import Darwin

final class XXHash128Library {
    static let shared = XXHash128Library()

    typealias CreateState = @convention(c) () -> UnsafeMutableRawPointer?
    typealias Reset = @convention(c) (UnsafeMutableRawPointer?) -> UInt32
    typealias Update = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int) -> UInt32
    typealias Digest = @convention(c) (UnsafeRawPointer?) -> SIMD2<UInt64>
    typealias FreeState = @convention(c) (UnsafeMutableRawPointer?) -> Void

    private let handle: UnsafeMutableRawPointer?
    private let createStateFn: CreateState?
    private let resetFn: Reset?
    private let updateFn: Update?
    private let digestFn: Digest?
    private let freeStateFn: FreeState?

    var isAvailable: Bool {
        handle != nil && createStateFn != nil && resetFn != nil && updateFn != nil && digestFn != nil && freeStateFn != nil
    }

    private init() {
        handle = XXHash128Library.loadLibrary()
        if let handle {
            createStateFn = XXHash128Library.loadSymbol(handle, name: "XXH3_createState", as: CreateState.self)
            resetFn = XXHash128Library.loadSymbol(handle, name: "XXH3_128bits_reset", as: Reset.self)
            updateFn = XXHash128Library.loadSymbol(handle, name: "XXH3_128bits_update", as: Update.self)
            digestFn = XXHash128Library.loadSymbol(handle, name: "XXH3_128bits_digest", as: Digest.self)
            freeStateFn = XXHash128Library.loadSymbol(handle, name: "XXH3_freeState", as: FreeState.self)
        } else {
            createStateFn = nil
            resetFn = nil
            updateFn = nil
            digestFn = nil
            freeStateFn = nil
        }
    }

    func createState() -> UnsafeMutableRawPointer? {
        createStateFn?()
    }

    func reset(_ state: UnsafeMutableRawPointer?) -> Bool {
        guard let resetFn else { return false }
        return resetFn(state) == 0
    }

    func update(_ state: UnsafeMutableRawPointer?, data: UnsafeRawPointer?, length: Int) -> Bool {
        guard let updateFn else { return false }
        return updateFn(state, data, length) == 0
    }

    func digest(_ state: UnsafeRawPointer?) -> SIMD2<UInt64> {
        digestFn?(state) ?? SIMD2<UInt64>(0, 0)
    }

    func freeState(_ state: UnsafeMutableRawPointer?) {
        freeStateFn?(state)
    }

    private static func loadLibrary() -> UnsafeMutableRawPointer? {
        let candidates = possibleLibraryPaths()
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                if let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) {
                    return handle
                }
            }
        }
        return nil
    }

    private static func loadSymbol<T>(_ handle: UnsafeMutableRawPointer, name: String, as type: T.Type) -> T? {
        guard let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }

    private static func possibleLibraryPaths() -> [String] {
        var paths: [String] = []
        if let resourceURL = Bundle.main.resourceURL {
            #if arch(arm64)
            let arch = "arm64"
            #else
            let arch = "x86_64"
            #endif
            let bundled = resourceURL
                .appendingPathComponent("rsync")
                .appendingPathComponent("lib")
                .appendingPathComponent(arch)
                .appendingPathComponent("libxxhash.0.dylib")
            paths.append(bundled.path)
        }
        paths.append("/opt/homebrew/lib/libxxhash.0.dylib")
        paths.append("/usr/local/lib/libxxhash.0.dylib")
        paths.append("/usr/lib/libxxhash.0.dylib")
        return paths
    }
}

final class XXHash128State {
    private let library = XXHash128Library.shared
    private var state: UnsafeMutableRawPointer?
    private var freed = false

    init?() {
        guard library.isAvailable else { return nil }
        guard let created = library.createState() else { return nil }
        state = created
        _ = library.reset(created)
    }

    func update(data: Data) {
        guard let state else { return }
        data.withUnsafeBytes { buffer in
            _ = library.update(state, data: buffer.baseAddress, length: buffer.count)
        }
    }

    func finalize() -> Data {
        guard let state else { return Data() }
        let hash = library.digest(UnsafeRawPointer(state))
        freeIfNeeded()
        var low = hash[0].littleEndian
        var high = hash[1].littleEndian
        var bytes = Data(bytes: &low, count: MemoryLayout<UInt64>.size)
        bytes.append(Data(bytes: &high, count: MemoryLayout<UInt64>.size))
        return bytes
    }

    private func freeIfNeeded() {
        if !freed {
            library.freeState(state)
            freed = true
        }
    }

    deinit {
        freeIfNeeded()
    }
}
