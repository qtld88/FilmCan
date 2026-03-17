import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct SourceListView: View {
    @Binding var sources: [String]
    var refreshToken: Int = 0
    var sourceSizes: [String: Int64] = [:]
    var sourceItemCounts: [String: Int] = [:]
    var isLoading: Bool = false
    var isTourHighlighted: Bool = false
    @State private var isDropTargeted: Bool = false
    @State private var dragPayload: String? = nil
    @State private var draggingDriveId: String? = nil
    @State private var draggingPath: String? = nil
    var showsTitle: Bool = true
    var headerView: AnyView? = nil
    var footerView: AnyView? = nil
    
    var body: some View {
        let _ = refreshToken
        VStack(alignment: .leading, spacing: 8) {
            if showsTitle {
                Text("Copy From")
                    .font(FilmCanFont.label(12))
                    .foregroundColor(FilmCanTheme.textSecondary)
            }
            
            VStack(spacing: 8) {
                if let headerView {
                    headerView
                }
                if sources.isEmpty {
                    // EMPTY STATE - Big and obvious
                    emptyDropZone
                } else {
                    // Grouped by drive
                    driveBlocks
                }
                
                // Add button (always visible)
                if !sources.isEmpty {
                    Button(action: addSource) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(FilmCanTheme.brandYellow)
                            Text("Add more files or folders")
                                .font(FilmCanFont.body(12))
                        }
                    }
                    .buttonStyle(.borderless)
                }
                
                if let footerView {
                    footerView
                }
            }
            .padding(12)
            .background(FilmCanTheme.panel)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isDropTargeted || isTourHighlighted ? FilmCanTheme.brandYellow : FilmCanTheme.cardStrokeStrong,
                        style: StrokeStyle(
                            lineWidth: isDropTargeted || isTourHighlighted ? 2 : 1,
                            dash: isDropTargeted ? [6, 4] : []
                        )
                    )
            )
            .shadow(color: isTourHighlighted ? FilmCanTheme.brandYellow.opacity(0.35) : .clear, radius: 10)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
            }
        }
    }
    
    private var emptyDropZone: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 56))
                .foregroundColor(FilmCanTheme.brandYellow.opacity(isDropTargeted ? 1.0 : 0.6))
                .opacity(isDropTargeted ? 1.0 : 0.8)
                .scaleEffect(isDropTargeted ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDropTargeted)
            
            VStack(spacing: 4) {
                Text("Drop files or folders here")
                    .font(FilmCanFont.label(16))
                    .foregroundColor(FilmCanTheme.textPrimary)
                Text("or")
                    .font(FilmCanFont.body(11))
                    .foregroundColor(FilmCanTheme.textSecondary)
            }
            
            Button("Browse Files...") {
                addSource()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 160)
    }
    
    private var driveBlocks: some View {
        let summaries = driveSummaries(for: sources)
        let indexed = Array(summaries.enumerated())
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(indexed, id: \.element.id) { index, summary in
                HStack(alignment: .center, spacing: 12) {
                    Text("\(index + 1)")
                        .font(FilmCanFont.label(11))
                        .foregroundColor(FilmCanTheme.textSecondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: DriveUtilities.driveIconName(isExternal: summary.isExternal, style: .filled))
                                .foregroundColor(FilmCanTheme.textSecondary)
                                .frame(width: 18)
                            Text(summary.name)
                                .font(FilmCanFont.body(11))
                                .foregroundColor(FilmCanTheme.textSecondary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Remove drive from this backup") {
                                removeDriveGroup(summary.id)
                            }
                            Button("Remove and eject drive from this backup") {
                                removeAndEjectDriveGroup(summary.id, paths: summary.paths)
                            }
                            Button("Eject drive") {
                                ejectDriveGroup(paths: summary.paths)
                            }
                        }
                        
                        if summary.isConnected {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(summary.paths) { source in
                                    sourceRow(source: source, isExternal: summary.isExternal)
                                }
                            }
                            .padding(.leading, 26)

                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(summary.paths) { source in
                                    sourceRow(source: source, isExternal: summary.isExternal)
                                }
                                Text(summary.connectionMessage)
                                    .font(FilmCanFont.body(10))
                                    .foregroundColor(FilmCanTheme.brandRed)
                            }
                            .padding(.leading, 26)
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(FilmCanTheme.card)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(FilmCanTheme.cardStroke, lineWidth: 1)
                )
                .cornerRadius(8)
                .anchorPreference(key: DriveAnchorPreferenceKey.self, value: .bounds) { bounds in
                    DriveAnchorData(sources: [summary.id: bounds])
                }
                .onDrag {
                    let payload = "drive:\(summary.id)"
                    dragPayload = payload
                    draggingDriveId = summary.id
                    return NSItemProvider(object: payload as NSString)
                }
                .onDrop(
                    of: [.text],
                    delegate: DriveDropDelegate(
                        targetId: summary.id,
                        draggingId: $draggingDriveId,
                        moveAction: { fromId, toId in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                moveDriveGroup(fromId: fromId, toId: toId)
                            }
                        }
                    )
                )
            }
        }
    }

    private func sourceRow(source: SourcePath, isExternal: Bool) -> some View {
        let metadata = getFileMetadata(source.path)
        let iconName = DriveUtilities.iconName(
            isExternal: isExternal,
            isRoot: source.isRoot,
            isDirectory: metadata.isDirectory,
            style: .filled,
            treatExternalAsDrive: false,
            treatRootAsDrive: true
        )
        
        return HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundColor(FilmCanTheme.textSecondary)
                .frame(width: 18)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(metadata.name)
                    .font(FilmCanFont.label(12))
                    .foregroundColor(FilmCanTheme.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if let size = metadata.formattedSize {
                        Text(size)
                            .font(FilmCanFont.body(11))
                            .foregroundColor(FilmCanTheme.textSecondary)
                    } else if isLoading {
                        Text("--")
                            .font(FilmCanFont.body(11))
                            .foregroundColor(FilmCanTheme.textSecondary)
                    }
                    if metadata.isDirectory {
                        if let count = metadata.itemCount {
                            Text("•")
                                .foregroundColor(FilmCanTheme.textSecondary)
                            Text("\(count) items")
                                .font(FilmCanFont.body(11))
                                .foregroundColor(FilmCanTheme.textSecondary)
                        } else if isLoading {
                            Text("•")
                                .foregroundColor(FilmCanTheme.textSecondary)
                            Text("-- items")
                                .font(FilmCanFont.body(11))
                                .foregroundColor(FilmCanTheme.textSecondary)
                        }
                    }
                }
                
                Text(source.path)
                    .font(FilmCanFont.body(10))
                    .foregroundColor(FilmCanTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Remove source from this backup") {
                removeSource(source.path)
            }
            Button("Remove and eject source from this backup") {
                removeAndEjectSource(source.path)
            }
        }
        .overlay(
            dragPayload == "path:\(source.path)" ?
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor, lineWidth: 2)
                : nil
        )
        .onDrag {
            let payload = "path:\(source.path)"
            dragPayload = payload
            draggingPath = source.path
            return NSItemProvider(object: payload as NSString)
        }
        .onDrop(
            of: [.text],
            delegate: PathDropDelegate(
                targetPath: source.path,
                draggingPath: $draggingPath,
                moveAction: { fromPath, toPath in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        movePath(fromPath: fromPath, toPath: toPath)
                    }
                }
            )
        )
    }
    
    private func getFileMetadata(_ path: String) -> FileMetadata {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            return FileMetadata(name: (path as NSString).lastPathComponent, isDirectory: false)
        }
        
        let name = (path as NSString).lastPathComponent
        
        if !isDir.boolValue {
            if let sizeHint = sourceSizes[path] {
                return FileMetadata(
                    name: name,
                    isDirectory: false,
                    size: sizeHint,
                    formattedSize: FilmCanFormatters.bytes(sizeHint, style: .file)
                )
            }
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                return FileMetadata(
                    name: name,
                    isDirectory: false,
                    size: size,
                    formattedSize: FilmCanFormatters.bytes(size, style: .file)
                )
            }
            return FileMetadata(name: name, isDirectory: false)
        }
        
        if let sizeHint = sourceSizes[path] {
            let countHint = sourceItemCounts[path]
            return FileMetadata(
                name: name,
                isDirectory: true,
                size: sizeHint,
                formattedSize: FilmCanFormatters.bytes(sizeHint, style: .file),
                itemCount: countHint
            )
        }
        return FileMetadata(name: name, isDirectory: true)
    }

    private func driveSummaries(for sources: [String]) -> [SourceDriveSummary] {
        var summaries: [String: SourceDriveSummary] = [:]
        var order: [String] = []
        
        for path in sources {
            let summary = DriveUtilities.summary(for: path)
            let volumeId = summary.id
            let name = summary.name
            let isExternal = summary.isExternal
            let isRoot = summary.isRoot
            let entry = SourcePath(path: path, isRoot: isRoot)
            let connection = connectionStatus(for: path, summary: summary)
            
            if summaries[volumeId] == nil {
                order.append(volumeId)
                summaries[volumeId] = SourceDriveSummary(
                    id: volumeId,
                    name: name,
                    paths: [entry],
                    isExternal: isExternal,
                    isConnected: connection.isConnected,
                    connectionMessage: connection.message
                )
            } else if var existing = summaries[volumeId] {
                existing.paths.append(entry)
                existing.isConnected = existing.isConnected || connection.isConnected
                if existing.connectionMessage.isEmpty {
                    existing.connectionMessage = connection.message
                }
                summaries[volumeId] = existing
            }
        }
        
        return order.compactMap { summaries[$0] }
    }

    private func connectionStatus(for path: String, summary: DriveUtilities.Summary) -> (isConnected: Bool, message: String) {
        if let root = volumeRootPath(for: path) {
            if FileManager.default.fileExists(atPath: root) {
                if summary.isReadOnly == true {
                    let formatLabel = summary.formatLabel.map { " (\($0))" } ?? ""
                    return (true, "Read-only\(formatLabel)")
                }
                return (true, "")
            }
            return (false, "Drive not connected")
        }
        if FileManager.default.fileExists(atPath: path) {
            if summary.isReadOnly == true {
                let formatLabel = summary.formatLabel.map { " (\($0))" } ?? ""
                return (true, "Read-only\(formatLabel)")
            }
            return (true, "")
        }
        return (false, "Source path not found")
    }

    private func handleDriveDrop(providers: [NSItemProvider], targetDriveId: String) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String, text.hasPrefix("drive:") else { return }
                    let fromId = String(text.dropFirst("drive:".count))
                    DispatchQueue.main.async {
                        moveDriveGroup(fromId: fromId, toId: targetDriveId)
                    }
                }
                return true
            }
        }
        return false
    }

    private struct DriveDropDelegate: DropDelegate {
        let targetId: String
        @Binding var draggingId: String?
        let moveAction: (String, String) -> Void

        func dropEntered(info: DropInfo) {
            guard let draggingId, draggingId != targetId else { return }
            moveAction(draggingId, targetId)
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            DropProposal(operation: .move)
        }

        func performDrop(info: DropInfo) -> Bool {
            draggingId = nil
            return true
        }

        func dropExited(info: DropInfo) {
            // no-op
        }
    }

    private func removeSource(_ path: String) {
        if let index = sources.firstIndex(of: path) {
            sources.remove(at: index)
        }
    }

    private func removeDriveGroup(_ driveGroupId: String) {
        sources.removeAll { driveId(for: $0) == driveGroupId }
    }

    private func removeAndEjectDriveGroup(_ driveGroupId: String, paths: [SourcePath]) {
        removeDriveGroup(driveGroupId)
        ejectDriveGroup(paths: paths)
    }

    private func ejectDriveGroup(paths: [SourcePath]) {
        guard let firstPath = paths.first?.path else { return }
        ejectVolume(for: firstPath)
    }

    private func removeAndEjectSource(_ path: String) {
        removeSource(path)
        ejectVolume(for: path)
    }

    private func ejectVolume(for path: String) {
        guard let root = volumeRootPath(for: path) else { return }
        let url = URL(fileURLWithPath: root)
        Task {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: url)
        }
    }

    private func volumeRootPath(for path: String) -> String? {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard components.count >= 3, components[1] == "Volumes" else { return nil }
        return "/Volumes/\(components[2])"
    }

    private struct PathDropDelegate: DropDelegate {
        let targetPath: String
        @Binding var draggingPath: String?
        let moveAction: (String, String) -> Void

        func dropEntered(info: DropInfo) {
            guard let draggingPath, draggingPath != targetPath else { return }
            moveAction(draggingPath, targetPath)
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            DropProposal(operation: .move)
        }

        func performDrop(info: DropInfo) -> Bool {
            draggingPath = nil
            return true
        }
    }

    private func handlePathDrop(providers: [NSItemProvider], targetPath: String) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String, text.hasPrefix("path:") else { return }
                    let fromPath = String(text.dropFirst("path:".count))
                    DispatchQueue.main.async {
                        movePath(fromPath: fromPath, toPath: targetPath)
                    }
                }
                return true
            }
        }
        return false
    }

    private func moveDriveGroup(fromId: String, toId: String) {
        guard fromId != toId else { return }
        let idsByPath = sources.map { driveId(for: $0) }
        let driveOrder = idsByPath.reduce(into: [String]()) { order, id in
            if order.last != id {
                order.append(id)
            }
        }
        let fromIndex = driveOrder.firstIndex(of: fromId) ?? 0
        let toIndex = driveOrder.firstIndex(of: toId) ?? 0
        let insertAfter = fromIndex < toIndex

        let fromPaths = zip(sources, idsByPath).filter { $0.1 == fromId }.map { $0.0 }
        var remaining = zip(sources, idsByPath).filter { $0.1 != fromId }.map { $0.0 }
        if insertAfter {
            let lastIndex = remaining.lastIndex { driveId(for: $0) == toId } ?? (remaining.count - 1)
            let insertIndex = min(lastIndex + 1, remaining.count)
            remaining.insert(contentsOf: fromPaths, at: insertIndex)
        } else {
            let firstIndex = remaining.firstIndex { driveId(for: $0) == toId } ?? remaining.count
            remaining.insert(contentsOf: fromPaths, at: firstIndex)
        }
        sources = remaining
    }

    private func movePath(fromPath: String, toPath: String) {
        guard fromPath != toPath,
              let fromIndex = sources.firstIndex(of: fromPath),
              let toIndex = sources.firstIndex(of: toPath) else { return }
        let fromDrive = driveId(for: fromPath)
        let toDrive = driveId(for: toPath)
        guard fromDrive == toDrive else { return }
        var updated = sources
        let item = updated.remove(at: fromIndex)
        let insertIndex = min(toIndex, updated.count)
        updated.insert(item, at: insertIndex)
        sources = updated
    }

    private func driveId(for path: String) -> String {
        DriveUtilities.driveId(for: path)
    }
    
    private func selectSource(at index: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK {
            let paths = panel.urls.map(\.path)
            if paths.count == 1 {
                if index < sources.count {
                    sources[index] = paths[0]
                }
            } else {
                if index < sources.count {
                    sources[index] = paths[0]
                }
                for path in paths.dropFirst() {
                    if !sources.contains(path) {
                        sources.append(path)
                    }
                }
            }
        }
    }
    
    private func addSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK {
            for url in panel.urls where !sources.contains(url.path) {
                sources.append(url.path)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        if !sources.contains(url.path) {
                            sources.append(url.path)
                        }
                    }
                }
            }
        }
        return true
    }
}

private struct FileMetadata {
    let name: String
    let isDirectory: Bool
    var size: Int64? = nil
    var formattedSize: String? = nil
    var itemCount: Int? = nil
}

private struct SourceDriveSummary: Identifiable {
    let id: String
    let name: String
    var paths: [SourcePath]
    let isExternal: Bool
    var isConnected: Bool
    var connectionMessage: String
}

private struct SourcePath: Identifiable {
    let id: String
    let path: String
    let isRoot: Bool

    init(path: String, isRoot: Bool) {
        self.path = path
        self.isRoot = isRoot
        self.id = path
    }
}
