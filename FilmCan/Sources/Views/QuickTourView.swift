import SwiftUI

enum TourCoordinateSpace {
    static let name = "TourSpace"
}

struct TourAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func tourAnchor(_ id: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TourAnchorPreferenceKey.self,
                    value: [id: proxy.frame(in: .named(TourCoordinateSpace.name))]
                )
            }
        )
    }
}

enum QuickTourPlacement {
    case top
    case bottom
    case leading
    case trailing
    case center
}

enum QuickTourRequirement {
    case none
    case hasBackup
    case createdBackup
    case renamedBackup
    case hasSource
    case hasDestination
}

struct QuickTourStep: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let targetId: String?
    let placement: QuickTourPlacement
    let requirement: QuickTourRequirement
    let autoAdvance: Bool
    
    init(
        title: String,
        message: String,
        targetId: String?,
        placement: QuickTourPlacement,
        requirement: QuickTourRequirement,
        autoAdvance: Bool = true
    ) {
        self.title = title
        self.message = message
        self.targetId = targetId
        self.placement = placement
        self.requirement = requirement
        self.autoAdvance = autoAdvance
    }
}

struct QuickTourView: View {
    @Binding var isPresented: Bool
    @Binding var didShowTour: Bool
    let steps: [QuickTourStep]
    let currentIndex: Int
    let canAdvance: Bool
    let anchors: [String: CGRect]
    let onBack: () -> Void
    let onNext: () -> Void
    let onDone: () -> Void
    let onSkip: () -> Void

    private let cardWidth: CGFloat = 380
    @State private var stableTargetRect: CGRect? = nil
    @State private var stableTargetId: String? = nil

    var body: some View {
        GeometryReader { geo in
            let step = steps[currentIndex]
            let targetRect = step.targetId.flatMap { anchors[$0] }
            let calloutRect = step.targetId == "backupName"
                ? (stableTargetRect ?? targetRect)
                : (targetRect ?? stableTargetRect)
            ZStack {
                dimOverlay(targetRect: targetRect)
                    .allowsHitTesting(false)

                if let targetRect {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(FilmCanTheme.brandYellow, lineWidth: 2)
                        .frame(width: targetRect.width + 8, height: targetRect.height + 8)
                        .position(x: targetRect.midX, y: targetRect.midY)
                        .allowsHitTesting(false)
                }

                callout(
                    step: step,
                    targetRect: calloutRect,
                    in: geo.size
                )
            }
            .onAppear {
                setStableTarget(step: step, targetRect: targetRect)
            }
            .onChange(of: currentIndex) { _ in
                let nextStep = steps[currentIndex]
                let nextRect = nextStep.targetId.flatMap { anchors[$0] }
                setStableTarget(step: nextStep, targetRect: nextRect)
            }
            .onChange(of: targetRect) { newValue in
                guard stableTargetId == step.targetId else { return }
                if step.targetId == "backupName" {
                    return
                }
                if let newValue {
                    stableTargetRect = newValue
                }
            }
        }
        .transition(.opacity)
    }

    private func dimOverlay(targetRect: CGRect?) -> some View {
        ZStack {
            Color.black.opacity(0.65)
            if let targetRect {
                RoundedRectangle(cornerRadius: 12)
                    .frame(width: targetRect.width + 12, height: targetRect.height + 12)
                    .position(x: targetRect.midX, y: targetRect.midY)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
    }

    private func callout(step: QuickTourStep, targetRect: CGRect?, in size: CGSize) -> some View {
        let base = tourCard(step: step)
        return base
            .frame(width: cardWidth)
            .position(calloutPosition(step: step, targetRect: targetRect, in: size))
    }

    private func tourCard(step: QuickTourStep) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(step.title)
                    .font(FilmCanFont.title(20))
                    .foregroundColor(FilmCanTheme.textPrimary)
                Spacer()
                Text("Step \(currentIndex + 1) of \(steps.count)")
                    .font(FilmCanFont.body(11))
                    .foregroundColor(FilmCanTheme.textSecondary)
            }

            Text(step.message)
                .font(FilmCanFont.body(14))
                .foregroundColor(FilmCanTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if step.requirement != .none && !canAdvance {
                HStack(spacing: 6) {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 11))
                        .foregroundColor(FilmCanTheme.brandYellow)
                    Text("Complete the highlighted action to continue.")
                        .font(FilmCanFont.body(11))
                        .foregroundColor(FilmCanTheme.textSecondary)
                }
                .padding(8)
                .background(FilmCanTheme.brandYellow.opacity(0.1))
                .cornerRadius(6)
            }

            Divider()
                .opacity(0.4)

            HStack(spacing: 12) {
                Button("Skip tour") {
                    onSkip()
                }
                .buttonStyle(.plain)
                .foregroundColor(FilmCanTheme.textSecondary)

                Button("Don't show again") {
                    didShowTour = true
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(FilmCanTheme.textSecondary)

                Spacer()

                Button("Back") {
                    onBack()
                }
                .buttonStyle(.bordered)
                .disabled(currentIndex == 0)

                if currentIndex < steps.count - 1 {
                    Button("Next") {
                        onNext()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FilmCanTheme.brandYellow)
                    .disabled(step.requirement != .none && !canAdvance)
                } else {
                    Button("Done") {
                        onDone()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FilmCanTheme.brandYellow)
                }
            }
        }
        .padding(18)
        .background(FilmCanTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(FilmCanTheme.cardStroke, lineWidth: 1)
        )
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }

    private func calloutPosition(step: QuickTourStep, targetRect: CGRect?, in size: CGSize) -> CGPoint {
        let padding: CGFloat = 18
        let cardSize = CGSize(width: cardWidth, height: 220)
        guard let targetRect else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        let spacing: CGFloat = 12
        let prefersLeading = step.targetId == "backupName"
        var origin = CGPoint(
            x: (prefersLeading ? targetRect.minX : targetRect.midX - cardSize.width / 2),
            y: targetRect.midY - cardSize.height / 2
        )
        switch step.placement {
        case .top:
            origin = CGPoint(
                x: prefersLeading ? targetRect.minX : targetRect.midX - cardSize.width / 2,
                y: targetRect.minY - cardSize.height - spacing
            )
        case .bottom:
            origin = CGPoint(
                x: prefersLeading ? targetRect.minX : targetRect.midX - cardSize.width / 2,
                y: targetRect.maxY + spacing
            )
        case .leading:
            origin = CGPoint(x: targetRect.minX - cardSize.width - spacing, y: targetRect.midY - cardSize.height / 2)
        case .trailing:
            origin = CGPoint(x: targetRect.maxX + spacing, y: targetRect.midY - cardSize.height / 2)
        case .center:
            origin = CGPoint(x: (size.width - cardSize.width) / 2, y: (size.height - cardSize.height) / 2)
        }
        let clampedX = min(max(padding, origin.x), size.width - cardSize.width - padding)
        let clampedY = min(max(padding, origin.y), size.height - cardSize.height - padding)
        return CGPoint(x: clampedX + cardSize.width / 2, y: clampedY + cardSize.height / 2)
    }
    
    private func setStableTarget(step: QuickTourStep, targetRect: CGRect?) {
        stableTargetId = step.targetId
        stableTargetRect = targetRect
    }

}

extension QuickTourStep {
    static let defaultSteps: [QuickTourStep] = [
        QuickTourStep(
            title: "Create a Movie Tab",
            message: "Click the plus button to add a new movie tab. Think of each can as one shooting or movie.",
            targetId: "addBackup",
            placement: .bottom,
            requirement: .createdBackup,
            autoAdvance: false
        ),
        QuickTourStep(
            title: "Name Your Movie",
            message: "Double-click the name to edit it, then press Enter to confirm. The movie tab updates and remembers its sources, destinations, and options.",
            targetId: "backupName",
            placement: .bottom,
            requirement: .renamedBackup,
            autoAdvance: false
        ),
        QuickTourStep(
            title: "Copy From",
            message: "Drop drives, folders, or files here. Drag to reorder the copy order.",
            targetId: "sourcePanel",
            placement: .bottom,
            requirement: .hasSource
        ),
        QuickTourStep(
            title: "Save To",
            message: "Add one or more destinations. Drag to reorder destinations and remove any you do not need.",
            targetId: "destinationPanel",
            placement: .bottom,
            requirement: .hasDestination
        ),
        QuickTourStep(
            title: "Drive Space + Flow",
            message: "Vertical bars show used (dark), backup (green), and free (light) space. The flow lines show how much data moves from each source drive to each destination.",
            targetId: "capacityBars",
            placement: .bottom,
            requirement: .none
        ),
        QuickTourStep(
            title: "Options Tabs",
            message: "Basic, Destinations, Logs, and Refinements control copy behavior, organization templates, logging, and safety options.",
            targetId: "optionsTabs",
            placement: .bottom,
            requirement: .none
        ),
        QuickTourStep(
            title: "History",
            message: "The history panel keeps every run, lets you resume stopped transfers, re-verify data, open logs, or reuse settings.",
            targetId: "historyPanel",
            placement: .leading,
            requirement: .none
        )
    ]
}
