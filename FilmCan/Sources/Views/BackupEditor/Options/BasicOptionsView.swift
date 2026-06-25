import SwiftUI

struct BasicOptionsView: View {
    @ObservedObject var viewModel: BackupEditorViewModel
    let availableWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Copy-engine picker removed: rsync retired, FilmCan is the only engine.
            // "Automatic parallel copy" toggle removed: destination parallelism is
            // now controlled by the Copy mode picker below.

            let verificationInfo = InfoPopoverContent(
                title: "Verification",
                description: "How thoroughly FilmCan confirms each file landed correctly.",
                options: [
                    .init("Paranoid",
                          good: ["Re-reads every file from disk and compares",
                                 "Catches write errors and in-memory corruption"],
                          bad: ["Roughly doubles disk I/O (the re-read pass)"]),
                    .init("Fast",
                          good: ["Verifies against the hash computed during the copy",
                                 "No re-read — about twice as fast as Paranoid"],
                          bad: ["Doesn't catch a bad write that the OS reported as OK",
                                "Trusts the data already in memory wasn't corrupted"]),
                    .init("Off",
                          good: ["Fastest — no hashing or checking"],
                          bad: ["A write error or corruption goes undetected",
                                "No hash list — the transfer log can't list individual files (status + counts only)"])
                ],
                notes: ["Paranoid is recommended for safety-critical backups.",
                        "The transfer log's per-file list is derived from the hash list, so it needs Fast or Paranoid."]
            )

            HStack(spacing: OptionsLayout.spacing) {
                Image(systemName: "checkmark.seal")
                    .font(.title3)
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .frame(width: OptionsLayout.iconWidth)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Verification")
                            .font(FilmCanFont.label(13))
                            .foregroundColor(FilmCanTheme.textPrimary)
                        InfoPopoverButton(content: verificationInfo)
                    }
                }
                .frame(width: optionsResolvedTextWidth(OptionsLayout.basicTextWidth, availableWidth: availableWidth), alignment: .leading)
                Menu {
                    ForEach(VerifyMode.allCases) { mode in
                        Button(action: { viewModel.verificationMode = mode }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.displayName)
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(viewModel.verificationMode.displayName)
                        Image(systemName: "chevron.down").font(.caption)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(FilmCanTheme.card)
                    .cornerRadius(6)
                    .frame(width: optionsResolvedMenuWidth(OptionsLayout.menuWidth + 60, textWidth: optionsResolvedTextWidth(OptionsLayout.basicTextWidth, availableWidth: availableWidth), availableWidth: availableWidth), alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            hashListStyleRow

            optionsRow(
                icon: "checkmark.shield",
                iconColor: FilmCanTheme.textSecondary,
                title: "Re-verify on resume",
                subtitle: "",
                isOn: $viewModel.reVerifyExistingOnResume,
                textWidth: OptionsLayout.basicTextWidth,
                info: InfoPopoverContent(
                    title: "Re-verify existing files on resume",
                    description: "When resuming a backup, re-read and hash each already-copied source file to confirm it hasn't changed since the last run.",
                    options: [
                        .init("Off (trust size)",
                              good: ["Fast resume — skips based on file size match"],
                              bad: ["Won't catch same-size content changes"]),
                        .init("On (re-hash source)",
                              good: ["Detects same-size file replacements cryptographically"],
                              bad: ["Slower — re-reads every already-backed-up file"])
                    ],
                    notes: ["Use when card contents may have been silently corrupted or replaced with same-size data."]
                ),
                availableWidth: availableWidth
            )

            optionsRow(
                icon: "arrow.triangle.2.circlepath",
                iconColor: FilmCanTheme.textSecondary,
                title: "Force re-copy",
                subtitle: "",
                isOn: $viewModel.forceRecopy,
                textWidth: OptionsLayout.basicTextWidth,
                info: InfoPopoverContent(
                    title: "Force re-copy",
                    description: "Whether a re-run copies files that are already backed up.",
                    options: [
                        .init("Off (resume skip)",
                              good: ["Skips files already in every destination's hash list and still present",
                                     "Fast re-runs — only new/changed files are copied"],
                              bad: ["A file deleted from a destination is re-copied (presence is checked)"]),
                        .init("On (force re-copy)",
                              good: ["Re-copies every file — guarantees a fresh copy"],
                              bad: ["Slower — ignores the hash list entirely"])
                    ],
                    notes: ["With a {date} folder template, resuming on a different day re-copies into that day's folder (earlier files aren't matched)."]
                ),
                availableWidth: availableWidth
            )

            HStack(spacing: OptionsLayout.spacing) {
                Image(systemName: "doc.on.doc")
                    .font(.title3)
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .frame(width: OptionsLayout.iconWidth)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Duplicate policy")
                            .font(FilmCanFont.label(13))
                            .foregroundColor(FilmCanTheme.textPrimary)
                        InfoPopoverButton(
                            content: InfoPopoverContent(
                                title: "Duplicate policy",
                                description: "What FilmCan does with a file or folder that already exists at the destination.",
                                options: [
                                    .init("Skip",
                                          good: ["Keeps existing destination files untouched"],
                                          bad: ["An out-of-date file at the destination stays out of date"]),
                                    .init("Overwrite",
                                          good: ["Destination ends up matching the source"],
                                          bad: ["Can destroy a destination-only version of the file"]),
                                    .init("Increment",
                                          good: ["Preserves both versions (adds a counter suffix)"],
                                          bad: ["Can create many duplicates over time"]),
                                    .init("Ask",
                                          good: ["You decide per conflict"],
                                          bad: ["Interrupts unattended runs"])
                                ]
                            )
                        )
                    }
                }
                .frame(width: optionsResolvedTextWidth(OptionsLayout.basicTextWidth, availableWidth: availableWidth), alignment: .leading)
                Menu {
                    ForEach(OrganizationPreset.DuplicatePolicy.allCases) { policy in
                        Button(policy.displayName) { viewModel.duplicatePolicy = policy }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(viewModel.duplicatePolicy.displayName)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(FilmCanTheme.card)
                    .cornerRadius(6)
                    .frame(width: optionsResolvedMenuWidth(OptionsLayout.menuWidth + 100, textWidth: optionsResolvedTextWidth(OptionsLayout.basicTextWidth, availableWidth: availableWidth), availableWidth: availableWidth), alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            if viewModel.duplicatePolicy == .increment {
                HStack(spacing: OptionsLayout.spacing) {
                    Color.clear
                        .frame(width: OptionsLayout.iconWidth, height: 1)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Counter style")
                                .font(FilmCanFont.label(13))
                                .foregroundColor(FilmCanTheme.textPrimary)
                            InfoPopoverButton(
                                content: InfoPopoverContent(
                                    title: "Counter style",
                                    description: "Defines the suffix format when using Increment. Example: `_001` produces file_001, file_002, etc.",
                                    pros: [
                                        "Keeps duplicates organized and predictable",
                                        "Supports zero-padded counters"
                                    ],
                                    cons: [
                                        "Only used when Increment is selected",
                                        "Inconsistent styles can clutter naming"
                                    ]
                                )
                            )
                        }
                    }
                    .frame(width: optionsResolvedTextWidth(OptionsLayout.basicTextWidth, availableWidth: availableWidth), alignment: .leading)
                    TextField("_001", text: $viewModel.duplicateCounterTemplate)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: optionsResolvedMenuWidth(OptionsLayout.menuWidth, textWidth: optionsResolvedTextWidth(OptionsLayout.basicTextWidth, availableWidth: availableWidth), availableWidth: availableWidth), alignment: .leading)
                }
            }

            let copyModeInfo = InfoPopoverContent(
                title: "Copy mode",
                description: "How FilmCan writes to multiple destinations.",
                options: [
                    .init("Automatic",
                          good: ["Parallel for SSDs, sequential for hard drives / shared buses",
                                 "Sensible default — no need to think about it"]),
                    .init("All destinations at once (parallel)",
                          good: ["Reads the source once, writes everywhere together",
                                 "Fastest with multiple SSDs"],
                          bad: ["More bandwidth and disk activity",
                                "Can thrash if destinations share one drive/bus"]),
                    .init("One destination at a time (sequential)",
                          good: ["Gentler on shared buses and hard drives"],
                          bad: ["Re-reads the source for each destination",
                                "Slower total time with multiple destinations"])
                ],
                notes: ["With one destination this setting has no effect."]
            )

            HStack(spacing: OptionsLayout.spacing) {
                Image(systemName: "square.stack.3d.down.right")
                    .font(.title3)
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .frame(width: OptionsLayout.iconWidth)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Copy mode")
                            .font(FilmCanFont.label(13))
                            .foregroundColor(FilmCanTheme.textPrimary)
                        InfoPopoverButton(content: copyModeInfo)
                    }
                }
                .frame(width: optionsResolvedTextWidth(OptionsLayout.basicTextWidth, availableWidth: availableWidth), alignment: .leading)
                Menu {
                    ForEach(DestinationCopyMode.allCases) { mode in
                        Button(action: { viewModel.destinationCopyMode = mode }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.displayName)
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(viewModel.destinationCopyMode.displayName)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(FilmCanTheme.card)
                    .cornerRadius(6)
                    .frame(width: optionsResolvedMenuWidth(OptionsLayout.menuWidth + 100, textWidth: optionsResolvedTextWidth(OptionsLayout.basicTextWidth, availableWidth: availableWidth), availableWidth: availableWidth), alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            let fileOrderInfo = InfoPopoverContent(
                title: "Copy order",
                description: "The order FilmCan copies files in.",
                options: [
                    .init("Default", good: ["Preserves the filesystem order"]),
                    .init("Smallest first",
                          good: ["Can speed up cards with lots of tiny files"],
                          bad: ["May not help on all drives"]),
                    .init("Largest first",
                          good: ["Can stabilize throughput on big files"]),
                    .init("Creation date",
                          good: ["Keeps footage order consistent"])
                ]
            )

            HStack(spacing: OptionsLayout.spacing) {
                Image(systemName: "arrow.up.arrow.down.circle")
                    .font(.title3)
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .frame(width: OptionsLayout.iconWidth)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Copy order")
                            .font(FilmCanFont.label(13))
                            .foregroundColor(FilmCanTheme.textPrimary)
                        InfoPopoverButton(content: fileOrderInfo)
                    }
                }
                .frame(width: optionsResolvedTextWidth(OptionsLayout.basicTextWidth, availableWidth: availableWidth), alignment: .leading)
                Menu {
                    ForEach(FileOrdering.allCases) { ordering in
                        Button(ordering.displayName) { viewModel.engineOptions.fileOrdering = ordering }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(viewModel.engineOptions.fileOrdering.displayName)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(FilmCanTheme.card)
                    .cornerRadius(6)
                    .frame(width: optionsResolvedMenuWidth(OptionsLayout.menuWidth + 100, textWidth: optionsResolvedTextWidth(OptionsLayout.basicTextWidth, availableWidth: availableWidth), availableWidth: availableWidth), alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var selectedOrganizationPresetName: String {
        let presets = viewModel.organizationPresets
        if let id = viewModel.selectedOrganizationPresetId,
           let preset = presets.first(where: { $0.id == id }) {
            return preset.name
        }
        return "Off"
    }

    private var hashListStyleLocked: Bool {
        selectedOrganizationPresetName == OrganizationPreset.netflixIngestName
    }

    @ViewBuilder
    private var hashListStyleRow: some View {
        let info = InfoPopoverContent(
            title: "Hash list style",
            description: "Which checksum manifest FilmCan writes next to each backed-up roll.",
            options: [
                .init("ASC MHL (Netflix-ready)",
                      good: ["Visible ascmhl/ folder + chain of custody",
                             "Validated by the reference ascmhl tool; accepted for delivery"],
                      bad: ["More files on the destination (manifest + chain per generation)"]),
                .init("Simple (hidden)",
                      good: ["One lightweight hidden .filmcan hash list per roll",
                             "Cleaner destination for users who don't deliver an MHL"],
                      bad: ["No chain of custody / generations",
                            "Not a Netflix-conformant deliverable"])
            ],
            notes: ["Resume-skip and verification work the same either way.",
                    "The Netflix Ingest preset always uses ASC MHL (this picker is locked)."]
        )
        HStack(spacing: OptionsLayout.spacing) {
            Image(systemName: "list.bullet.rectangle")
                .font(.title3)
                .foregroundColor(FilmCanTheme.textSecondary)
                .frame(width: OptionsLayout.iconWidth)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Hash list style")
                        .font(FilmCanFont.label(13))
                        .foregroundColor(FilmCanTheme.textPrimary)
                    InfoPopoverButton(content: info)
                }
            }
            .frame(width: optionsResolvedTextWidth(OptionsLayout.basicTextWidth, availableWidth: availableWidth), alignment: .leading)
            Menu {
                ForEach(HashListStyle.allCases) { style in
                    Button(action: { viewModel.hashListStyle = style }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(style.displayName)
                            Text(style.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(hashListStyleLocked ? HashListStyle.ascMHL.shortName : viewModel.hashListStyle.shortName)
                    Image(systemName: "chevron.down").font(.caption)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(FilmCanTheme.card)
                .cornerRadius(6)
                .frame(width: optionsResolvedMenuWidth(OptionsLayout.menuWidth + 60, textWidth: optionsResolvedTextWidth(OptionsLayout.basicTextWidth, availableWidth: availableWidth), availableWidth: availableWidth), alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(hashListStyleLocked)
            .opacity(hashListStyleLocked ? 0.5 : 1)
        }
    }
}
