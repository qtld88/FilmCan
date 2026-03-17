import SwiftUI
import AppKit

struct TitlebarAccessory<Content: View>: NSViewRepresentable {
    let id: String
    let layout: NSLayoutConstraint.Attribute
    let expandsToWindowWidth: Bool
    let fillsTitlebarHeight: Bool
    let content: () -> Content

    init(
        id: String,
        layout: NSLayoutConstraint.Attribute,
        expandsToWindowWidth: Bool = false,
        fillsTitlebarHeight: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.id = id
        self.layout = layout
        self.expandsToWindowWidth = expandsToWindowWidth
        self.fillsTitlebarHeight = fillsTitlebarHeight
        self.content = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(identifier: NSUserInterfaceItemIdentifier(id), layout: layout)
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            let accessory = context.coordinator.accessory(in: window)
            let titlebarHeight = max(0, window.frame.height - window.contentLayoutRect.height)
            let targetHeight: CGFloat
            if let hostingView = accessory.view as? TitlebarHostingView {
                hostingView.rootView = AnyView(content())
                let fittingSize = hostingView.fittingSize
                targetHeight = fillsTitlebarHeight ? max(fittingSize.height, titlebarHeight) : fittingSize.height
                let targetWidth = expandsToWindowWidth ? window.frame.width : fittingSize.width
                hostingView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
                hostingView.autoresizingMask = expandsToWindowWidth ? [.width] : []
            } else {
                let hostingView = TitlebarHostingView(rootView: AnyView(content()))
                let fittingSize = hostingView.fittingSize
                targetHeight = fillsTitlebarHeight ? max(fittingSize.height, titlebarHeight) : fittingSize.height
                let targetWidth = expandsToWindowWidth ? window.frame.width : fittingSize.width
                hostingView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
                hostingView.autoresizingMask = expandsToWindowWidth ? [.width] : []
                accessory.view = hostingView
            }
            if fillsTitlebarHeight {
                accessory.fullScreenMinHeight = targetHeight
            }
        }
    }

    final class TitlebarHostingView: NSHostingView<AnyView> {
        override var mouseDownCanMoveWindow: Bool {
            false
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }
    }

    final class Coordinator {
        private let identifier: NSUserInterfaceItemIdentifier
        private let layout: NSLayoutConstraint.Attribute

        init(identifier: NSUserInterfaceItemIdentifier, layout: NSLayoutConstraint.Attribute) {
            self.identifier = identifier
            self.layout = layout
        }

        func accessory(in window: NSWindow) -> NSTitlebarAccessoryViewController {
            if let existing = window.titlebarAccessoryViewControllers.first(where: { $0.identifier == identifier }) {
                return existing
            }
            let accessory = NSTitlebarAccessoryViewController()
            accessory.identifier = identifier
            accessory.layoutAttribute = layout
            window.addTitlebarAccessoryViewController(accessory)
            return accessory
        }
    }
}
