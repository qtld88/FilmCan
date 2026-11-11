import SwiftUI

/// The folder layout as a tree you edit: rename a folder, add one, remove it, move it,
/// and see where cards and sound land. Thin: every rule is in `FolderStructure`; the
/// text field below it edits the same setting.
struct FolderStructureEditor: View {
    let structure: FolderStructure
    let onChange: (FolderStructure) -> Void

    @State private var renamingRowId: String?
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool
    @State private var pendingStart: FolderStructure.StartingPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            startingPoints
            tree
        }
        .confirmationDialog(
            "Replace the current folder layout?",
            isPresented: Binding(get: { pendingStart != nil }, set: { if !$0 { pendingStart = nil } }),
            presenting: pendingStart
        ) { point in
            Button("Use \u{201C}\(point.title)\u{201D}") { onChange(point.structure) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The folders you set up for this movie are replaced. Backups already made stay where they are.")
        }
    }

    // MARK: Starting points

    private var startingPoints: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Start from")
                .font(FCType.meta)
                .foregroundColor(FilmCanTheme.textSecondary)
            TokenFlowLayout(spacing: 8) {
                ForEach(FolderStructure.startingPoints) { point in
                    Button {
                        if structure == point.structure { return }
                        if structure == FolderStructure() { onChange(point.structure) } else { pendingStart = point }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.title)
                                .font(FCType.bodyStrong)
                                .foregroundColor(FilmCanTheme.textPrimary)
                            Text(point.detail)
                                .font(FCType.meta)
                                .foregroundColor(FilmCanTheme.textSecondary)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(width: 190, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(FilmCanTheme.card))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                            structure == point.structure ? FilmCanTheme.brandYellow : FilmCanTheme.cardStroke,
                            lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Tree

    private var tree: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "externaldrive").font(.system(size: 11)).frame(width: 16)
                Text("Drive").font(FCType.body)
                if structure.cardsAtTopLevel { landingBadge("Cards go here") }
                if structure.soundAtTopLevel { landingBadge("Sound goes here") }
                Spacer(minLength: 8)
                addMenu(inside: nil)
            }
            .foregroundColor(FilmCanTheme.textSecondary)

            ForEach(structure.rows) { row in
                rowView(row)
                    .padding(.leading, CGFloat(row.depth + 1) * 16)
            }

            if structure.soundIsSeparate {
                Button("Put sound with the cards") { edit { $0.putSoundWithCards() } }
                    .buttonStyle(.link)
                    .font(FCType.meta)
            } else if !structure.cardsAtTopLevel {
                Button("Give sound its own folder") { edit { $0.separateSound() } }
                    .buttonStyle(.link)
                    .font(FCType.meta)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(FilmCanTheme.background.opacity(0.6)))
    }

    private func rowView(_ row: FolderStructure.Row) -> some View {
        HStack(spacing: 6) {
            Image(systemName: row.isPlain ? "folder" : "folder.badge.gearshape")
                .font(.system(size: 11))
                .frame(width: 16)
                .foregroundColor(FilmCanTheme.textSecondary)
            if renamingRowId == row.id {
                TextField("Folder name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .focused($nameFocused)
                    .onSubmit { commitRename(row) }
                    .onExitCommand { renamingRowId = nil }
            } else {
                Text(row.label)
                    .font(FCType.body)
                    .foregroundColor(FilmCanTheme.textPrimary)
                    .lineLimit(1)
                    .help(row.isPlain ? "A folder with this name" : "Named automatically for each backup")
            }
            if row.holdsCards { landingBadge("Cards go here") }
            if row.holdsSound { landingBadge("Sound goes here") }
            Spacer(minLength: 8)
            Menu {
                if row.isPlain {
                    Button("Rename") { startRename(row) }
                }
                Menu("Add a folder inside") { addChoices(inside: row) }
                Button("Move up") { edit { $0.move(row, by: -1) } }
                    .disabled(!structure.canMove(row, by: -1))
                Button("Move down") { edit { $0.move(row, by: 1) } }
                    .disabled(!structure.canMove(row, by: 1))
                Divider()
                Button("Remove", role: .destructive) { edit { $0.remove(row) } }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Rename, add, move or remove this folder")
        }
    }

    private func addMenu(inside row: FolderStructure.Row?) -> some View {
        Menu {
            addChoices(inside: row)
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add a folder at the top of the drive")
    }

    @ViewBuilder
    private func addChoices(inside row: FolderStructure.Row?) -> some View {
        Button("Folder with a name…") { edit { $0.addFolder("New folder", inside: row) } }
        Divider()
        ForEach(FolderStructure.knownTokens, id: \.token) { known in
            Button(known.label) { edit { $0.addFolder(known.token, inside: row) } }
        }
    }

    private func landingBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(FilmCanTheme.brandYellow))
    }

    // MARK: Actions

    private func edit(_ change: (inout FolderStructure) -> Void) {
        renamingRowId = nil
        var copy = structure
        change(&copy)
        if copy != structure { onChange(copy) }
    }

    private func startRename(_ row: FolderStructure.Row) {
        draftName = row.segment
        renamingRowId = row.id
        DispatchQueue.main.async { nameFocused = true }
    }

    private func commitRename(_ row: FolderStructure.Row) {
        let name = draftName
        edit { $0.rename(row, to: name) }
    }
}
