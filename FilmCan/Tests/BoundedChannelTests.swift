import XCTest
@testable import FilmCan

final class BoundedChannelTests: XCTestCase {
    func test_sendReceive_singleElement() async {
        let ch = BoundedChannel<Int>(capacity: 4)
        await ch.send(42)
        let val = try? await ch.receive()
        XCTAssertEqual(val, 42)
    }

    func test_sendReceive_orderPreserved() async {
        let ch = BoundedChannel<Int>(capacity: 4)
        await ch.send(1); await ch.send(2); await ch.send(3)
        let a = try? await ch.receive()
        let b = try? await ch.receive()
        let c = try? await ch.receive()
        XCTAssertEqual([a, b, c], [1, 2, 3])
    }

    func test_receive_throws_whenFinished() async {
        let ch = BoundedChannel<Int>(capacity: 2)
        await ch.send(1)
        await ch.finish()
        let val = try? await ch.receive()
        XCTAssertEqual(val, 1)
        do {
            let _ = try await ch.receive()
            XCTFail("Should throw")
        } catch let err as BoundedChannelError {
            XCTAssertEqual(err, .finished)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_iteration_finishes() async throws {
        let ch = BoundedChannel<Int>(capacity: 4)
        async let producer: Void = {
            for i in 0..<5 { await ch.send(i) }
            await ch.finish()
        }()
        var collected: [Int] = []
        for try await val in ch { collected.append(val) }
        await producer
        XCTAssertEqual(collected, [0, 1, 2, 3, 4])
    }

    func test_concurrent_sendReceive() async throws {
        let ch = BoundedChannel<Int>(capacity: 4)
        async let producer: Void = {
            for i in 0..<20 { await ch.send(i) }
            await ch.finish()
        }()
        var results: [Int] = []
        for try await val in ch { results.append(val) }
        await producer
        XCTAssertEqual(results.sorted(), Array(0..<20))
    }
}
