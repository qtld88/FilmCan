import SwiftUI

struct DestPickerView: View {
    let destinations: [DestPickerItem]
    @Binding var selected: Set<String>
    @State private var searchText = ""

    struct DestPickerItem: Identifiable {
        let id: String
        let displayName: String
        let path: String
        let speedClass: String
        let requiresFullFsync: Bool
    }

    var filtered: [DestPickerItem] {
        if searchText.isEmpty { return destinations }
        return destinations.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.path.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "externaldrive.badge.checkmark")
                Text("Destinations (\(selected.count) selected)")
                    .font(.headline)
                Spacer()
                if !selected.isEmpty {
                    Button("Clear") { selected.removeAll() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                }
            }

            TextField("Filter destinations…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            List(filtered) { item in
                HStack {
                    Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selected.contains(item.id) ? .accentColor : .secondary)
                        .onTapGesture {
                            if selected.contains(item.id) {
                                selected.remove(item.id)
                            } else {
                                selected.insert(item.id)
                            }
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayName).font(.subheadline)
                        Text(item.path).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text(item.speedClass)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(item.requiresFullFsync ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                            .cornerRadius(4)
                        if item.requiresFullFsync {
                            Image(systemName: "lock.shield")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selected.contains(item.id) {
                        selected.remove(item.id)
                    } else {
                        selected.insert(item.id)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}
