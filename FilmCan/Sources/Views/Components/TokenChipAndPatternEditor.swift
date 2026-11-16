import SwiftUI

struct TokenChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .textSelection(.disabled)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .onDrag {
                NSItemProvider(object: text as NSString)
            }
    }
}

struct PatternEditor: View {
    let title: String
    let placeholder: String
    @Binding var patterns: [String]
    var showsTitle: Bool = true
    @State private var editorText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsTitle {
                Text(title)
                    .font(.subheadline)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $editorText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 56)
                .focused($isFocused)
                .onChange(of: editorText) { newValue in
                    let newPatterns = splitPatterns(newValue)
                    if newPatterns != patterns {
                        patterns = newPatterns
                    }
                }

                if editorText.isEmpty {
                    Text(placeholder)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        .padding(.top, 8)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            )
            Text("One pattern per line")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onAppear {
            editorText = patterns.joined(separator: "\n")
        }
        .onChange(of: patterns) { newValue in
            guard !isFocused else { return }
            let joined = newValue.joined(separator: "\n")
            if editorText != joined {
                editorText = joined
            }
        }
    }

    private func splitPatterns(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
