import SwiftUI

struct InfoPopoverContent {
    let title: String
    let description: String
    let pros: [String]
    let cons: [String]
    let notes: [String]

    init(title: String, description: String, pros: [String] = [], cons: [String] = [], notes: [String] = []) {
        self.title = title
        self.description = description
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
            VStack(alignment: .leading, spacing: 8) {
                Text(content.title)
                    .font(.headline)
                Text(content.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !content.pros.isEmpty {
                    Text("Pros")
                        .font(.caption.bold())
                    BulletList(content.pros)
                }

                if !content.cons.isEmpty {
                    Text("Cons")
                        .font(.caption.bold())
                    BulletList(content.cons)
                }

                if !content.notes.isEmpty {
                    Text("Notes")
                        .font(.caption.bold())
                    BulletList(content.notes)
                }
            }
            .padding(12)
            .frame(width: 280, alignment: .leading)
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
