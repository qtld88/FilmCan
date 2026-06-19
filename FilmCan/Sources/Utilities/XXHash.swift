import Foundation
import Darwin

/// Mirrors C `XXH128_hash_t { XXH64_hash_t low64; XXH64_hash_t high64; }`.
/// Must be top-level for use in `@convention(c)` function types.
/// A two-field UInt64 aggregate uses the C integer-aggregate return ABI on
/// both arm64 (x0/x1) and x86_64 (rax/rdx) — unlike SIMD2, whose vector ABI
/// mismatches the C function and yields garbage on x86_64.
struct XXH128Hash { var low64: UInt64; var high64: UInt64 }

final class XXHash128Library {
    static let shared = XXHash128Library()

    typealias CreateState = @convention(c) () -> UnsafeMutableRawPointer?
    typealias Reset = @convention(c) (UnsafeMutableRawPointer?) -> UInt32
    typealias Update = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int) -> UInt32
    // NSRange {Int location; Int length} is ObjC-representable and has the same
    // two-integer-register ABI as C's XXH128_hash_t {uint64_t low64; uint64_t high64}.
    // Direct use of a Swift struct in @convention(c) is rejected by the compiler
    // despite being ABI-equivalent — this is a known Swift type-system limitation.
    typealias Digest = @convention(c) (UnsafeRawPointer?) -> NSRange
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

    func digest(_ state: UnsafeRawPointer?) -> XXH128Hash {
        let range = digestFn?(state) ?? NSRange(location: 0, length: 0)
        // NSRange.location maps to low64, NSRange.length maps to high64 (same registers).
        return XXH128Hash(low64: UInt64(bitPattern: Int64(range.location)),
                          high64: UInt64(bitPattern: Int64(range.length)))
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
        var out = Data()
        out.reserveCapacity(16)
        withUnsafeBytes(of: hash.high64.bigEndian) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: hash.low64.bigEndian) { out.append(contentsOf: $0) }
        return out
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
