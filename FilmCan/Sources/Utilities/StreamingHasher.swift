import Foundation

protocol StreamingHasher {
    func update(data: Data)
    func finalize() -> Data
}

final class XXH128StreamingHasher: StreamingHasher {
    private var state: XXHash128State?

    init?() {
        guard XXHash128Library.shared.isAvailable else { return nil }
        state = XXHash128State()
    }

    func update(data: Data) {
        state?.update(data: data)
    }

    func finalize() -> Data {
        state?.finalize() ?? Data()
    }
}
