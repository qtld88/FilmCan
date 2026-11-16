import XCTest
@testable import FilmCan

@MainActor
final class TodayClockTests: XCTestCase {

    private func date(_ d: Int, hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2030; c.month = 11; c.day = d; c.hour = hour
        return Calendar.current.date(from: c)!
    }

    func test_refresh_sameDay_keepsValue() {
        let clock = TodayClock()
        clock.refresh(now: date(10, hour: 9))
        let morning = clock.today
        clock.refresh(now: date(10, hour: 23))
        XCTAssertEqual(clock.today, morning)
    }

    func test_refresh_nextDay_publishesNewDate() {
        let clock = TodayClock()
        clock.refresh(now: date(10, hour: 23))
        var received: [Date] = []
        let sub = clock.$today.dropFirst().sink { received.append($0) }
        clock.refresh(now: date(11, hour: 0))
        XCTAssertEqual(received, [date(11, hour: 0)])
        sub.cancel()
    }
}
