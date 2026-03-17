import SwiftUI

struct FlowLinkView: View {
    struct FlowNode: Identifiable {
        let id: String
        let name: String
        let sizeBytes: Int64
        let totalBytes: Int64?
        let availableBytes: Int64?
    }
    
    let sources: [FlowNode]
    let destinations: [FlowNode]
    let totalBytes: Int64
    let destinationStoredDrives: Set<String>
    let sourceCenters: [String: CGFloat]
    let destinationCenters: [String: CGFloat]
    
    private let maxThickness: CGFloat = 18
    private let minThickness: CGFloat = 2
    private let horizontalInset: CGFloat = 4
    private let verticalPadding: CGFloat = 12
    private let barWidth: CGFloat = 8
    private let barHeight: CGFloat = 86
    private let barGap: CGFloat = 6
    
    init(
        sources: [FlowNode],
        destinations: [FlowNode],
        totalBytes: Int64,
        destinationStoredDrives: Set<String> = [],
        sourceCenters: [String: CGFloat] = [:],
        destinationCenters: [String: CGFloat] = [:]
    ) {
        self.sources = sources
        self.destinations = destinations
        self.totalBytes = totalBytes
        self.destinationStoredDrives = destinationStoredDrives
        self.sourceCenters = sourceCenters
        self.destinationCenters = destinationCenters
    }

    var body: some View {
        GeometryReader { geo in
            let layout = makeLayout(size: geo.size)
            ZStack {
                Canvas { context, size in
                    drawFlow(context: context, size: size, layout: layout)
                }
                capacityBarsAnchor(layout: layout)
            }
            .allowsHitTesting(false)
        }
    }
    
    private func nodePositions(count: Int, height: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        if count == 1 { return [height / 2] }
        let usable = max(height - verticalPadding * 2, 1)
        let step = usable / CGFloat(count - 1)
        return (0..<count).map { verticalPadding + CGFloat($0) * step }
    }
    
    private func sourceRatios() -> [String: Double] {
        let total = totalBytes > 0 ? totalBytes : sources.map { $0.sizeBytes }.reduce(0, +)
        guard total > 0 else {
            let fallback = 1.0 / Double(max(sources.count, 1))
            return Dictionary(uniqueKeysWithValues: sources.map { ($0.id, fallback) })
        }
        return Dictionary(uniqueKeysWithValues: sources.map { source in
            return (source.id, Double(source.sizeBytes) / Double(total))
        })
    }
    
    private func destinationTotalThicknesses() -> [String: CGFloat] {
        let total = max(totalBytes, 1)
        return Dictionary(uniqueKeysWithValues: destinations.map { destination in
            let available = destination.availableBytes ?? 0
            let ratio: Double
            if available > 0 {
                ratio = min(1.0, Double(total) / Double(available))
            } else {
                ratio = totalBytes > 0 ? 1.0 : 0.2
            }
            return (destination.id, clamp(CGFloat(ratio) * maxThickness, minThickness, maxThickness))
        })
    }
    
    private func flowPath(start: CGPoint, end: CGPoint, startThickness: CGFloat, endThickness: CGFloat, width: CGFloat) -> Path {
        let startTop = CGPoint(x: start.x, y: start.y - startThickness / 2)
        let startBottom = CGPoint(x: start.x, y: start.y + startThickness / 2)
        let endTop = CGPoint(x: end.x, y: end.y - endThickness / 2)
        let endBottom = CGPoint(x: end.x, y: end.y + endThickness / 2)
        let dx = max(end.x - start.x, 1)
        let controlOffset = max(dx * 0.5, 8)
        let c1 = CGPoint(x: start.x + controlOffset, y: startTop.y)
        let c2 = CGPoint(x: end.x - controlOffset, y: endTop.y)
        let c3 = CGPoint(x: end.x - controlOffset, y: endBottom.y)
        let c4 = CGPoint(x: start.x + controlOffset, y: startBottom.y)
        
        var path = Path()
        path.move(to: startTop)
        path.addCurve(to: endTop, control1: c1, control2: c2)
        path.addLine(to: endBottom)
        path.addCurve(to: startBottom, control1: c3, control2: c4)
        path.closeSubpath()
        return path
    }
    
    private func clamp(_ value: CGFloat, _ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        min(max(value, minValue), maxValue)
    }

    private func stackedBackupCenters(info: DiskBarInfo, count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        let backupHeight = max(info.backupHeight, 0)
        if backupHeight <= 0 {
            return Array(repeating: info.backupCenterY, count: count)
        }
        let startY = info.rect.minY + info.freeHeight
        if count == 1 {
            return [startY + backupHeight / 2]
        }
        let slice = backupHeight / CGFloat(count)
        return (0..<count).map { index in
            startY + slice * (CGFloat(index) + 0.5)
        }
    }

    private struct DiskBarInfo {
        let rect: CGRect
        let usedHeight: CGFloat
        let backupHeight: CGFloat
        let freeHeight: CGFloat
        let usedColor: Color
        let backupColor: Color
        let freeColor: Color
        let backupCenterY: CGFloat
        let usedPercent: Int
        let backupPercent: Int
        let freePercent: Int
        let backupOfUsedPercent: Int?
        let driveName: String
    }

    private func diskBarInfoForSource(node: FlowNode, centerY: CGFloat, x: CGFloat, height: CGFloat) -> DiskBarInfo? {
        guard let total = node.totalBytes, total > 0 else { return nil }
        let available = node.availableBytes ?? 0
        let usedBytes = max(total - available, 0)
        let copyBytes = min(node.sizeBytes, usedBytes)
        let otherUsed = max(usedBytes - copyBytes, 0)
        let freeBytes = max(total - usedBytes, 0)

        let usedRatio = CGFloat(Double(otherUsed) / Double(total))
        let backupRatio = CGFloat(Double(copyBytes) / Double(total))
        let freeRatio = CGFloat(Double(freeBytes) / Double(total))
        let backupOfUsedPercent: Int?
        if usedBytes > 0 {
            backupOfUsedPercent = Int(round(Double(copyBytes) / Double(usedBytes) * 100))
        } else {
            backupOfUsedPercent = nil
        }
        return makeDiskBarInfo(
            centerY: centerY,
            x: x,
            height: height,
            usedRatio: usedRatio,
            backupRatio: backupRatio,
            freeRatio: freeRatio,
            backupColor: FilmCanTheme.brandGreen.opacity(0.6),
            backupOfUsedPercent: backupOfUsedPercent,
            driveName: node.name
        )
    }

    private func diskBarInfoForDestination(node: FlowNode, centerY: CGFloat, x: CGFloat, height: CGFloat) -> DiskBarInfo? {
        guard let total = node.totalBytes, total > 0 else { return nil }
        let available = node.availableBytes ?? 0
        let usedBytes = max(total - available, 0)
        let requiredBytes = max(totalBytes, 0)
        let isStored = destinationStoredDrives.contains(node.id)
        let backupBytes: Int64
        let usedOtherBytes: Int64
        let freeBytes: Int64
        let effectiveRequiredForSpace: Int64
        if isStored {
            backupBytes = min(Int64(requiredBytes), usedBytes)
            usedOtherBytes = max(usedBytes - backupBytes, 0)
            freeBytes = max(total - usedBytes, 0)
            effectiveRequiredForSpace = 0
        } else {
            backupBytes = min(Int64(requiredBytes), max(available, 0))
            usedOtherBytes = usedBytes
            freeBytes = max(total - usedBytes - backupBytes, 0)
            effectiveRequiredForSpace = Int64(requiredBytes)
        }

        let usedRatio = CGFloat(Double(usedOtherBytes) / Double(total))
        let backupRatio = CGFloat(Double(backupBytes) / Double(total))
        let freeRatio = CGFloat(Double(freeBytes) / Double(total))

        let ratioToAvailable: Double?
        if effectiveRequiredForSpace <= 0 {
            ratioToAvailable = 0
        } else if available > 0 {
            ratioToAvailable = Double(effectiveRequiredForSpace) / Double(available)
        } else {
            ratioToAvailable = Double.infinity
        }
        let backupPercent = total > 0 ? Double(backupBytes) / Double(total) : 0
        let backupColor: Color
        if isStored {
            backupColor = FilmCanTheme.brandGreen
        } else {
            if let ratio = ratioToAvailable, ratio > 1.0 {
                backupColor = .red
            } else if backupPercent > 0.8 {
                backupColor = .red
            } else {
                backupColor = FilmCanTheme.brandGreen
            }
        }

        return makeDiskBarInfo(
            centerY: centerY,
            x: x,
            height: height,
            usedRatio: usedRatio,
            backupRatio: backupRatio,
            freeRatio: freeRatio,
            backupColor: backupColor.opacity(0.6),
            backupOfUsedPercent: nil,
            driveName: node.name
        )
    }

    private func makeDiskBarInfo(
        centerY: CGFloat,
        x: CGFloat,
        height: CGFloat,
        usedRatio: CGFloat,
        backupRatio: CGFloat,
        freeRatio: CGFloat,
        backupColor: Color,
        backupOfUsedPercent: Int?,
        driveName: String
    ) -> DiskBarInfo {
        let rect = barRect(centerY: centerY, height: barHeight, width: barWidth, containerHeight: height, x: x)
        let totalHeight = rect.height
        var usedHeight = totalHeight * usedRatio
        var backupHeight = totalHeight * backupRatio
        var freeHeight = max(0, totalHeight - usedHeight - backupHeight)
        let minBackupHeight: CGFloat = 2
        if backupRatio > 0, backupHeight > 0, backupHeight < minBackupHeight {
            let delta = minBackupHeight - backupHeight
            backupHeight = minBackupHeight
            if freeHeight >= delta {
                freeHeight -= delta
            } else {
                let remaining = delta - freeHeight
                freeHeight = 0
                usedHeight = max(0, usedHeight - remaining)
            }
        }
        let usedColor = Color.gray.opacity(0.35)
        let freeColor = Color.gray.opacity(0.75)
        let backupCenterY = rect.minY + freeHeight + backupHeight / 2
        let usedPercent = Int(round(usedRatio * 100))
        let backupPercent = Int(round(backupRatio * 100))
        let freePercent = max(0, 100 - usedPercent - backupPercent)
        return DiskBarInfo(
            rect: rect,
            usedHeight: usedHeight,
            backupHeight: backupHeight,
            freeHeight: freeHeight,
            usedColor: usedColor,
            backupColor: backupColor,
            freeColor: freeColor,
            backupCenterY: backupCenterY,
            usedPercent: usedPercent,
            backupPercent: backupPercent,
            freePercent: freePercent,
            backupOfUsedPercent: backupOfUsedPercent,
            driveName: driveName
        )
    }

    private func barRect(centerY: CGFloat, height: CGFloat, width: CGFloat, containerHeight: CGFloat, x: CGFloat) -> CGRect {
        let h = min(height, containerHeight)
        var top = centerY - h / 2
        if top < 0 { top = 0 }
        var bottom = top + h
        if bottom > containerHeight {
            bottom = containerHeight
            top = max(0, bottom - h)
        }
        return CGRect(x: x, y: top, width: width, height: bottom - top)
    }

    private func drawDiskBar(info: DiskBarInfo, context: GraphicsContext) {
        let rect = info.rect
        let corner: CGFloat = 3
        context.drawLayer { layer in
            layer.clip(to: Path(roundedRect: rect, cornerRadius: corner))
            var cursor = rect.minY
            if info.freeHeight > 0 {
                let freeRect = CGRect(x: rect.minX, y: cursor, width: rect.width, height: info.freeHeight)
                layer.fill(Path(freeRect), with: .color(info.freeColor))
                cursor += info.freeHeight
            }
            if info.backupHeight > 0 {
                let backupRect = CGRect(x: rect.minX, y: cursor, width: rect.width, height: info.backupHeight)
                layer.fill(Path(backupRect), with: .color(info.backupColor))
                cursor += info.backupHeight
            }
            if info.usedHeight > 0 {
                let usedRect = CGRect(x: rect.minX, y: cursor, width: rect.width, height: info.usedHeight)
                layer.fill(Path(usedRect), with: .color(info.usedColor))
            }
        }
    }

    private struct FlowLayout {
        let startX: CGFloat
        let endX: CGFloat
        let sourcePositions: [CGFloat]
        let destinationPositions: [CGFloat]
        let ratios: [String: Double]
        let destTotalThicknesses: [String: CGFloat]
        let sourceBars: [String: DiskBarInfo]
        let destinationBars: [String: DiskBarInfo]
        let sourceBarList: [(String, DiskBarInfo)]
        let destinationBarList: [(String, DiskBarInfo)]
        let sourceCount: Int
        let destinationCount: Int
    }

    private func makeLayout(size: CGSize) -> FlowLayout {
        let leftBarX = horizontalInset
        let rightBarX = max(horizontalInset, size.width - horizontalInset - barWidth)
        let startX = leftBarX + barWidth + barGap
        let endX = max(startX + 1, rightBarX - barGap)
        let sourcePositions = nodePositions(count: sources.count, height: size.height)
        let destinationPositions = nodePositions(count: destinations.count, height: size.height)
        let ratios = sourceRatios()
        let destTotalThicknesses = destinationTotalThicknesses()
        let destinationCount = max(destinations.count, 1)
        let sourceCount = max(sources.count, 1)

        var sourceBars: [String: DiskBarInfo] = [:]
        var sourceBarList: [(String, DiskBarInfo)] = []
        for (index, source) in sources.enumerated() {
            let center = sourceCenters[source.id] ?? sourcePositions[safe: index] ?? size.height / 2
            if let info = diskBarInfoForSource(node: source, centerY: center, x: leftBarX, height: size.height) {
                sourceBars[source.id] = info
                sourceBarList.append((source.id, info))
            }
        }

        var destinationBars: [String: DiskBarInfo] = [:]
        var destinationBarList: [(String, DiskBarInfo)] = []
        for (index, destination) in destinations.enumerated() {
            let center = destinationCenters[destination.id] ?? destinationPositions[safe: index] ?? size.height / 2
            if let info = diskBarInfoForDestination(node: destination, centerY: center, x: rightBarX, height: size.height) {
                destinationBars[destination.id] = info
                destinationBarList.append((destination.id, info))
            }
        }

        return FlowLayout(
            startX: startX,
            endX: endX,
            sourcePositions: sourcePositions,
            destinationPositions: destinationPositions,
            ratios: ratios,
            destTotalThicknesses: destTotalThicknesses,
            sourceBars: sourceBars,
            destinationBars: destinationBars,
            sourceBarList: sourceBarList,
            destinationBarList: destinationBarList,
            sourceCount: sourceCount,
            destinationCount: destinationCount
        )
    }

    @ViewBuilder
    private func capacityBarsAnchor(layout: FlowLayout) -> some View {
        if let rect = capacityBarsRect(layout: layout) {
            Color.clear
                .frame(width: rect.width + 6, height: rect.height + 6)
                .position(x: rect.midX, y: rect.midY)
                .tourAnchor("capacityBars")
        } else {
            EmptyView()
        }
    }

    private func capacityBarsRect(layout: FlowLayout) -> CGRect? {
        let rects = (layout.sourceBarList.map { $0.1.rect }) + (layout.destinationBarList.map { $0.1.rect })
        guard let first = rects.first else { return nil }
        var minX = first.minX
        var maxX = first.maxX
        var minY = first.minY
        var maxY = first.maxY
        for rect in rects.dropFirst() {
            minX = min(minX, rect.minX)
            maxX = max(maxX, rect.maxX)
            minY = min(minY, rect.minY)
            maxY = max(maxY, rect.maxY)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func drawFlow(context: GraphicsContext, size: CGSize, layout: FlowLayout) {
        for info in layout.sourceBars.values {
            drawDiskBar(info: info, context: context)
        }
        for info in layout.destinationBars.values {
            drawDiskBar(info: info, context: context)
        }

        var destinationStackedCenters: [String: [CGFloat]] = [:]
        for destination in destinations {
            if let info = layout.destinationBars[destination.id] {
                destinationStackedCenters[destination.id] = stackedBackupCenters(
                    info: info,
                    count: max(sources.count, 1)
                )
            }
        }

        let orderedSourceIds: [String] = sources.enumerated().map { index, source in
            let fallbackStart = sourceCenters[source.id]
                ?? layout.sourcePositions[safe: index]
                ?? size.height / 2
            let startY = layout.sourceBars[source.id]?.backupCenterY ?? fallbackStart
            return (source.id, startY)
        }
        .sorted { $0.1 < $1.1 }
        .map { $0.0 }
        let sourceRanks = Dictionary(uniqueKeysWithValues: orderedSourceIds.enumerated().map { ($0.element, $0.offset) })

        for (sIndex, source) in sources.enumerated() {
            let sourceRatio = layout.ratios[source.id] ?? (1.0 / Double(max(sources.count, 1)))
            let fallbackThickness = clamp(CGFloat(sourceRatio) * maxThickness, minThickness, maxThickness)
            let sourceThickness = layout.sourceBars[source.id]
                .map { max(minThickness, $0.backupHeight) }
                ?? fallbackThickness
            let fallbackStart = sourceCenters[source.id] ?? layout.sourcePositions[safe: sIndex] ?? size.height / 2
            let startY = layout.sourceBars[source.id]?.backupCenterY ?? fallbackStart

            for (dIndex, destination) in destinations.enumerated() {
                let destTotal = layout.destTotalThicknesses[destination.id] ?? maxThickness * 0.2
                let fallbackDestThickness = clamp(destTotal * CGFloat(sourceRatio), minThickness, maxThickness)
                let destThickness = layout.destinationBars[destination.id]
                    .map { info in
                        let slice = info.backupHeight / CGFloat(max(sources.count, 1))
                        return clamp(slice, minThickness, maxThickness)
                    }
                    ?? fallbackDestThickness
                let fallbackEnd = destinationCenters[destination.id] ?? layout.destinationPositions[safe: dIndex] ?? size.height / 2
                let rank = sourceRanks[source.id] ?? sIndex
                let stackedEnd = destinationStackedCenters[destination.id]?[safe: rank]
                let endY = stackedEnd ?? layout.destinationBars[destination.id]?.backupCenterY ?? fallbackEnd

                let path = flowPath(
                    start: CGPoint(x: layout.startX, y: startY),
                    end: CGPoint(x: layout.endX, y: endY),
                    startThickness: sourceThickness,
                    endThickness: destThickness,
                    width: size.width
                )

                let color = layout.destinationBars[destination.id]?.backupColor ?? Color.accentColor.opacity(0.35)
                context.fill(path, with: .color(color))
            }
        }
    }

}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
