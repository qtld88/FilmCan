import Foundation

enum BoundedChannelError: Error, Equatable {
    case finished
}

actor BoundedChannel<Element: Sendable> {
    private var buffer: [Element]
    private var receiverContinuation: CheckedContinuation<Void, Never>?
    private var senderContinuation: CheckedContinuation<Void, Never>?
    private var isFinished = false
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = Swift.max(capacity, 1)
        buffer = []
    }

    func send(_ element: Element) async {
        while buffer.count >= capacity && !isFinished {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                senderContinuation = cont
            }
        }
        // When woken by finish(), the while loop exits.
        // Append anyway so in-flight sends are not lost.
        buffer.append(element)
        receiverContinuation?.resume()
        receiverContinuation = nil
    }

    func receive() async throws -> Element {
        while buffer.isEmpty && !isFinished {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                receiverContinuation = cont
            }
        }
        if buffer.isEmpty, isFinished {
            throw BoundedChannelError.finished
        }
        let val = buffer.removeFirst()
        senderContinuation?.resume()
        senderContinuation = nil
        return val
    }

    func finish() {
        isFinished = true
        receiverContinuation?.resume()
        receiverContinuation = nil
        senderContinuation?.resume()
        senderContinuation = nil
    }
}

extension BoundedChannel: AsyncSequence {
    struct AsyncIterator: AsyncIteratorProtocol {
        let channel: BoundedChannel
        mutating func next() async throws -> Element? {
            do {
                return try await channel.receive()
            } catch BoundedChannelError.finished {
                return nil
            }
        }
    }
    nonisolated func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(channel: self)
    }
}
