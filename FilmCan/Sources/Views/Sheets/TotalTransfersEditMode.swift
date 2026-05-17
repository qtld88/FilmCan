import SwiftUI

struct TotalTransfersEditMode: View {
    @Binding var fanOutDestinations: [DestWriter.Config]
    let onDismiss: () -> Void
    let onSave: ([DestWriter.Config]) -> Void

    @State private var editItems: [EditItem] = []

    struct EditItem: Identifiable {
        let id: String
        var displayName: String
        var destPath: String
        var verifyMode: VerifyMode
        var requiresFullFsync: Bool
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Edit Destinations")
                    .font(.title2).bold()
                Spacer()
                Button("Done") {
                    let updated = editItems.map { item in
                        DestWriter.Config(
                            destPath: item.destPath,
                            displayName: item.displayName,
                            verifyMode: item.verifyMode,
                            requiresFullFsync: item.requiresFullFsync,
                                                        chunkSize: nil
                        )
                    }
                    onSave(updated)
                }
                .keyboardShortcut(.return)
            }
            .padding(.horizontal)

            List($editItems) { $item in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Display Name", text: $item.displayName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Path", text: $item.destPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    HStack {
                        Picker("Verify", selection: $item.verifyMode) {
                            ForEach(VerifyMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        Toggle("F_FULLFSYNC", isOn: $item.requiresFullFsync)
                            .toggleStyle(.switch)
                            .font(.caption)
                    }
                }
                .padding(8)
            }
            .listStyle(.plain)
        }
        .frame(width: 520, height: 400)
        .onAppear {
            editItems = fanOutDestinations.map {
                EditItem(id: $0.destPath, displayName: $0.displayName,
                         destPath: $0.destPath, verifyMode: $0.verifyMode,
                         requiresFullFsync: $0.requiresFullFsync)
            }
        }
    }
}
