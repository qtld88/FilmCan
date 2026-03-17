import SwiftUI
import AppKit

struct OrganizationSheet: View {
    @Binding var presets: [OrganizationPreset]
    @Binding var selectedPresetId: UUID?
    let onAddPreset: () -> Void
    let onDeletePreset: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                OrganizationSettingsView(
                    presets: $presets,
                    selectedPresetId: $selectedPresetId,
                    onAddPreset: onAddPreset,
                    onDeletePreset: onDeletePreset,
                    showHeader: true,
                    allowsLocalPreset: false,
                    localPreset: .constant(OrganizationPreset())
                )
                .padding()
            }
            .navigationTitle("Organization Presets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 560)
    }
}
