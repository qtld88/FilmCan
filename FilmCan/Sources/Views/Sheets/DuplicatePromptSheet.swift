import SwiftUI

struct DuplicatePromptSheet: View {
    let prompt: DuplicatePrompt
    let onDecision: (OrganizationPreset.DuplicatePolicy, Bool, String?) -> Void
    let onCancel: () -> Void
    @State private var applyToAll: Bool = false
    @State private var counterTemplate: String
    @State private var showCounterStyle: Bool = false
    @State private var showCounterSheet: Bool = false
    @FocusState private var isCounterFocused: Bool

    init(
        prompt: DuplicatePrompt,
        onDecision: @escaping (OrganizationPreset.DuplicatePolicy, Bool, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.onDecision = onDecision
        self.onCancel = onCancel
        _counterTemplate = State(initialValue: prompt.counterTemplate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(UIStrings.DuplicatePrompt.title)
                .font(FilmCanFont.title(18))
                .foregroundColor(FilmCanTheme.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text(UIStrings.DuplicatePrompt.sourceLabel)
                    .font(FilmCanFont.label(12))
                    .foregroundColor(FilmCanTheme.textSecondary)
                Text(prompt.sourceName)
                    .font(FilmCanFont.body(14))
                    .foregroundColor(FilmCanTheme.textPrimary)
                Text(prompt.sourcePath)
                    .font(FilmCanFont.body(11))
                    .foregroundColor(FilmCanTheme.textTertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(UIStrings.DuplicatePrompt.destinationLabel)
                    .font(FilmCanFont.label(12))
                    .foregroundColor(FilmCanTheme.textSecondary)
                Text(prompt.destinationName)
                    .font(FilmCanFont.body(14))
                    .foregroundColor(FilmCanTheme.textPrimary)
                Text(prompt.destinationPath)
                    .font(FilmCanFont.body(11))
                    .foregroundColor(FilmCanTheme.textTertiary)
            }

            Toggle(UIStrings.DuplicatePrompt.applyToAll, isOn: $applyToAll)
                .toggleStyle(.switch)
                .tint(FilmCanTheme.toggleTint)
                .controlSize(.small)

            ViewThatFits {
                HStack(spacing: 12) {
                    duplicateActionButtons
                }
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 12) {
                        duplicateActionButtonsPrefix
                    }
                    HStack(spacing: 12) {
                        duplicateActionButtonsSuffix
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if !prompt.canVerifyWithHashList && prompt.hashListMissing {
                Text(UIStrings.DuplicatePrompt.noHashList)
                    .font(FilmCanFont.body(11))
                    .foregroundColor(FilmCanTheme.textSecondary)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
        .background(FilmCanTheme.background)
        .interactiveDismissDisabled(true)
        .sheet(isPresented: $showCounterSheet) {
            counterStyleSheet
        }
    }

    private var duplicateActionButtons: some View {
        Group {
            duplicateActionButtonsPrefix
            duplicateActionButtonsSuffix
        }
    }

    private var duplicateActionButtonsPrefix: some View {
        Group {
            Button(UIStrings.DuplicatePrompt.skip) { onDecision(.skip, applyToAll, nil) }
                .buttonStyle(.bordered)
                .fixedSize(horizontal: true, vertical: false)
            Button {
                onDecision(.verify, applyToAll, nil)
            } label: {
                Text(UIStrings.DuplicatePrompt.verifyHashList)
            }
            .buttonStyle(.bordered)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(!prompt.canVerifyWithHashList)
            Button(UIStrings.DuplicatePrompt.overwrite) { onDecision(.overwrite, applyToAll, nil) }
                .buttonStyle(.borderedProminent)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var duplicateActionButtonsSuffix: some View {
        Group {
            Button(UIStrings.DuplicatePrompt.addCounter) {
                showCounterSheet = true
                showCounterStyle = true
                isCounterFocused = true
            }
            .buttonStyle(.bordered)
            .fixedSize(horizontal: true, vertical: false)
            Button(UIStrings.DuplicatePrompt.cancelRun) { onCancel() }
                .buttonStyle(.bordered)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var counterStyleSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(UIStrings.DuplicatePrompt.counterStyleTitle)
                .font(FilmCanFont.title(16))
                .foregroundColor(FilmCanTheme.textPrimary)
            TextField(UIStrings.DuplicatePrompt.counterStylePlaceholder, text: $counterTemplate)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 160, alignment: .leading)
                .focused($isCounterFocused)
            Text(UIStrings.DuplicatePrompt.counterStyleHint)
                .font(FilmCanFont.body(11))
                .foregroundColor(FilmCanTheme.textSecondary)
            HStack(spacing: 12) {
                Spacer()
                Button(UIStrings.Alerts.deleteCancel) { showCounterSheet = false }
                    .buttonStyle(.bordered)
                Button(UIStrings.DuplicatePrompt.addCounter) {
                    let trimmed = counterTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolved = trimmed.isEmpty ? prompt.counterTemplate : trimmed
                    showCounterSheet = false
                    onDecision(.increment, applyToAll, resolved)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 280)
        .background(FilmCanTheme.background)
    }
}
