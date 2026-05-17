import Foundation

enum BoundedChannelError: Error, Equatable {
    case finished
}

actor BoundedChannel<Element: Sendable> {
    private var buffer: [Element] = []
    private var senderContinuations: [CheckedContinuation<Void, Never>] = []
    private var receiverContinuations: [CheckedContinuation<Void, Never>] = []
    private var isFinished = false
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = Swift.max(capacity, 1)
    }

    func send(_ element: Element) async throws {
        if isFinished { throw BoundedChannelError.finished }
        if buffer.count >= capacity {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                senderContinuations.append(cont)
            }
            if isFinished { throw BoundedChannelError.finished }
        }
        buffer.append(element)
        if !receiverContinuations.isEmpty {
            receiverContinuations.removeFirst().resume()
        }
    }

    func receive() async throws -> Element {
        if buffer.isEmpty && isFinished { throw BoundedChannelError.finished }
        if buffer.isEmpty {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                receiverContinuations.append(cont)
            }
            if buffer.isEmpty && isFinished { throw BoundedChannelError.finished }
        }
        let val = buffer.removeFirst()
        if !senderContinuations.isEmpty {
            senderContinuations.removeFirst().resume()
        }
        return val
    }

    func finish() {
        isFinished = true
        for cont in senderContinuations { cont.resume() }
        senderContinuations.removeAll()
        for cont in receiverContinuations { cont.resume() }
        receiverContinuations.removeAll()
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
            } catch {
                throw error
            }
        }
    }

    nonisolated func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(channel: self)
    }
}
