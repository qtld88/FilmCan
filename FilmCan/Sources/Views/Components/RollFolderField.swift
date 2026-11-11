import SwiftUI

/// Editable roll folder name of a generic-named card (Untitled -> Untitled_01).
/// Commits on Return or when focus leaves; an empty value means "keep the card's own name".
struct RollFolderField: View {
    let value: String
    let onCommit: (String) -> Void
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("Roll folder")
                .font(FCType.meta)
                .foregroundColor(FilmCanTheme.textSecondary)
            TextField("Card name", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(FCType.meta)
                .frame(maxWidth: 160)
                .focused($focused)
                .onSubmit { onCommit(draft) }
                .onChange(of: focused) { isFocused in
                    if !isFocused, draft != value { onCommit(draft) }
                }
        }
        .onAppear { draft = value }
        .onChange(of: value) { newValue in
            if !focused { draft = newValue }
        }
    }
}
