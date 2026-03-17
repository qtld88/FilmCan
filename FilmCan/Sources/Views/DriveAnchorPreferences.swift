import SwiftUI

struct DriveAnchorData {
    var sources: [String: Anchor<CGRect>] = [:]
    var destinations: [String: Anchor<CGRect>] = [:]
    var flowFrame: Anchor<CGRect>? = nil

    init(
        sources: [String: Anchor<CGRect>] = [:],
        destinations: [String: Anchor<CGRect>] = [:],
        flowFrame: Anchor<CGRect>? = nil
    ) {
        self.sources = sources
        self.destinations = destinations
        self.flowFrame = flowFrame
    }
}

struct DriveAnchorPreferenceKey: PreferenceKey {
    static var defaultValue = DriveAnchorData()

    static func reduce(value: inout DriveAnchorData, nextValue: () -> DriveAnchorData) {
        let next = nextValue()
        value.sources.merge(next.sources) { _, new in new }
        value.destinations.merge(next.destinations) { _, new in new }
        if let flowFrame = next.flowFrame {
            value.flowFrame = flowFrame
        }
    }
}
