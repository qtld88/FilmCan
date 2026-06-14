import SwiftUI

struct InfoPopoverContent {
    /// One choice (e.g. a picker option, or On/Off for a toggle), with its own
    /// upsides and downsides grouped together.
    struct Option: Identifiable {
        let label: String
        let good: [String]
        let bad: [String]
        var id: String { label }
        init(_ label: String, good: [String] = [], bad: [String] = []) {
            self.label = label
            self.good = good
            self.bad = bad
        }
    }

    let title: String
    let description: String
    let options: [Option]
    let pros: [String]
    let cons: [String]
    let notes: [String]

    init(title: String, description: String,
         options: [Option] = [],
         pros: [String] = [], cons: [String] = [], notes: [String] = []) {
        self.title = title
        self.description = description
        self.options = options
        self.pros = pros
        self.cons = cons
        self.notes = notes
    }
}

struct InfoPopoverButton: View {
    let content: InfoPopoverContent
    @State private var isPresented = false

    var body: some View {
        Button(action: { isPresented.toggle() }) {
            Image(systemName: "info.circle")
                .foregroundColor(FilmCanTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            InfoPopoverBody(content: content)
                .padding(12)
                .frame(width: 300, alignment: .leading)
        }
    }
}

/// Shared popover body so InfoPopoverButton and any other presenter render the
/// same way. When `options` are present they're shown grouped by choice (each
/// with its own ✓ / ✗ lines); otherwise the legacy Pros/Cons layout is used.
struct InfoPopoverBody: View {
    let content: InfoPopoverContent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(content.title)
                .font(.headline)
            if !content.description.isEmpty {
                Text(content.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !content.options.isEmpty {
                ForEach(content.options) { option in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(option.label)
                            .font(.caption.bold())
                        ForEach(option.good, id: \.self) { ProConLine($0, isPro: true) }
                        ForEach(option.bad, id: \.self) { ProConLine($0, isPro: false) }
                    }
                }
            } else {
                if !content.pros.isEmpty {
                    Text("Pros").font(.caption.bold())
                    BulletList(content.pros)
                }
                if !content.cons.isEmpty {
                    Text("Cons").font(.caption.bold())
                    BulletList(content.cons)
                }
            }

            if !content.notes.isEmpty {
                Text("Notes").font(.caption.bold())
                BulletList(content.notes)
            }
        }
    }
}

private struct ProConLine: View {
    let text: String
    let isPro: Bool
    init(_ text: String, isPro: Bool) {
        self.text = text
        self.isPro = isPro
    }
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: isPro ? "checkmark" : "xmark")
                .font(.caption2.bold())
                .foregroundColor(isPro ? FilmCanTheme.brandGreen : FilmCanTheme.brandRed)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct BulletList: View {
    let items: [String]

    init(_ items: [String]) {
        self.items = items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                    Text(item)
                        .font(.caption)
                }
            }
        }
    }
}
