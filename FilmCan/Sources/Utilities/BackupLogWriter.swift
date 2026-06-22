import Foundation

enum BackupLogWriter {

    static func resolvedLogFilePath(
        logEnabled: Bool,
        logLocation: BackupConfiguration.LogLocation,
        customLogPath: String,
        logFileNameTemplate: String,
        configName: String,
        destination: String,
        sources: [String],
        customDate: Date?
    ) -> (path: String?, warning: String?) {
        guard logEnabled else { return (nil, nil) }
        let effectiveDate = customDate ?? Date()
        let logName = LogFileNamer.makeFileName(
            template: logFileNameTemplate,
            configName: configName,
            destination: destination,
            sources: sources,
            date: effectiveDate
        )

        let preferredBase: String
        if logLocation == .custom && !customLogPath.isEmpty {
            let resolved = LogFolderNamer.resolveFolderPath(
                template: customLogPath,
                destination: destination,
                sources: sources,
                date: effectiveDate
            )
            preferredBase = resolved.isEmpty ? customLogPath : resolved
        } else {
            preferredBase = destination
        }

        let preferredPath = (preferredBase as NSString).appendingPathComponent(logName)
        if Self.ensureWritableLogPath(preferredPath) {
            return (preferredPath, nil)
        }

        let fallbackDir = Self.appSupportLogDirectory()
        let fallbackPath = (fallbackDir as NSString).appendingPathComponent(logName)
        if Self.ensureWritableLogPath(fallbackPath) {
            return (
                fallbackPath,
                "Log file could not be created at the destination. Using the app log folder instead."
            )
        }

        return (nil, "Log file could not be created. Continuing without a log file.")
    }

    /// Write a per-destination log for the fan-out engine. The single-transfer path
    /// (`runSingleTransfer`) writes its own log; the fan-out path did not, so logs
    /// never got created for the (only) FilmCan Engine. Mirrors that behavior:
    /// resolve the log path (same-as-destination or custom folder template) and
    /// write it, recording the path / any warning back onto each result.
    static func writeFanOutLogs(
        config: BackupConfiguration,
        sources: [String],
        results: inout [TransferResult],
        preset: OrganizationPreset?
    ) {
        guard config.logEnabled else { return }
        let customDate = preset?.useCustomDate == true ? preset?.customDate : nil
        for index in results.indices {
            let destination = results[index].destination
            // The Netflix preset must put the report in the shoot-day Reports/ folder
            // at THIS destination — a relative "Reports" custom path can't anchor there,
            // so resolve it explicitly. Other configs use the normal log resolver.
            var resolution: (path: String?, warning: String?)
            if let preset, preset.name == OrganizationPreset.netflixIngestName,
               let nfPath = Self.netflixReportLogPath(destination: destination, config: config,
                                                      preset: preset, sources: sources, customDate: customDate) {
                resolution = (nfPath, nil)
            } else {
                resolution = Self.resolvedLogFilePath(
                    logEnabled: true,
                    logLocation: config.logLocation,
                    customLogPath: config.customLogPath,
                    logFileNameTemplate: config.logFileNameTemplate,
                    configName: config.name,
                    destination: destination,
                    sources: sources,
                    customDate: customDate
                )
            }
            guard let logFile = resolution.path else {
                results[index].logFilePath = nil
                if let warning = resolution.warning {
                    results[index].warningMessage = Self.mergeWarning(results[index].warningMessage, warning)
                }
                continue
            }
            // The transferred-items list is the engine's truthful per-run list
            // (set in explodeFanOutResult). It is deliberately NOT derived from the
            // hash list, which is cumulative and would also list carried-forward /
            // skipped files that weren't copied this run.
            if let writeWarning = Self.writeCustomLog(
                result: results[index],
                logFile: logFile,
                sources: sources,
                destination: destination
            ) {
                results[index].logFilePath = nil
                results[index].warningMessage = Self.mergeWarning(results[index].warningMessage, writeWarning)
            } else {
                results[index].logFilePath = logFile
                if let warning = resolution.warning {
                    results[index].warningMessage = Self.mergeWarning(results[index].warningMessage, warning)
                }
            }
        }
    }

    static func mergeWarning(_ existing: String?, _ new: String) -> String {
        guard let existing, !existing.isEmpty else { return new }
        return existing.contains(new) ? existing : "\(existing)\n\(new)"
    }

    /// `<destination>/<shoot-day-root>/Reports/<logname>` for the Netflix preset, where
    /// the shoot-day root is the first folder component of the resolved Netflix template.
    static func netflixReportLogPath(destination: String, config: BackupConfiguration,
                                     preset: OrganizationPreset, sources: [String],
                                     customDate: Date?) -> String? {
        let date = customDate ?? Date()
        let meta = ShootMetadata(episode: config.episode, day: config.day,
                                 unit: config.unit, cameraFormat: config.cameraFormat)
        let resolved = OrganizationTemplate.resolve(
            preset: preset, sourcePath: sources.first ?? "", destinationRoot: destination,
            counter: 0, date: date, metadata: meta)
        guard let shootDay = resolved.folderPath.split(separator: "/").first.map(String.init),
              !shootDay.isEmpty else { return nil }
        let reportsDir = (destination as NSString)
            .appendingPathComponent(shootDay)
            .appending("/Reports")
        let logName = LogFileNamer.makeFileName(
            template: config.logFileNameTemplate, configName: config.name,
            destination: destination, sources: sources, date: date)
        let path = (reportsDir as NSString).appendingPathComponent(logName)
        return Self.ensureWritableLogPath(path) ? path : nil
    }

    static func writeCustomLog(
        result: TransferResult,
        logFile: String,
        sources: [String],
        destination: String
    ) -> String? {
        let start = result.startTime
        let end = result.endTime ?? Date()
        let duration = FilmCanFormatters.durationCompact(end.timeIntervalSince(start))
        let status = result.success ? "SUCCESS" : "FAILED"
        let bytes = FilmCanFormatters.bytes(result.bytesTransferred, style: .file)
        let totalBytes = FilmCanFormatters.bytes(result.totalBytes, style: .file)
        let filesTransferred = result.filesTransferred
        let filesSkipped = result.filesSkipped
        let sourcesList = sources.map { "- \($0)" }.joined(separator: "\n")
        let transferredList = result.transferredPaths.isEmpty
            ? "  (none)"
            : result.transferredPaths.map { "  \($0)" }.joined(separator: "\n")

        var lines: [String] = []
        lines.append("FilmCan Copy Log")
        lines.append("Backup: \(result.configurationName)")
        lines.append("Engine: FilmCan Engine")
        lines.append("Status: \(status)")
        if let message = result.errorMessage, !message.isEmpty {
            lines.append("Error: \(message)")
        }
        if let warning = result.warningMessage, !warning.isEmpty {
            lines.append("Warning: \(warning)")
        }
        lines.append("Start: \(start)")
        lines.append("End: \(end)")
        lines.append("Duration: \(duration)")
        lines.append("Destination: \(destination)")
        lines.append("Sources:\n\(sourcesList)")
        lines.append("Bytes: \(bytes) of \(totalBytes)")
        lines.append("Files: \(filesTransferred) transferred, \(filesSkipped) skipped")
        lines.append("")
        lines.append("Transferred items:")
        lines.append(transferredList)
        lines.append("")

        if !result.errors.isEmpty {
            lines.append("Verification issues:")
            lines.append(result.errors.map { "  \($0)" }.joined(separator: "\n"))
            lines.append("")
        }

        let content = lines.joined(separator: "\n")
        do {
            try content.write(toFile: logFile, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return "Log file could not be written at \(logFile). Transfer completed without a log file."
        }
    }

    static func appSupportLogDirectory() -> String {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base else { return NSTemporaryDirectory() }
        let dir = base.appendingPathComponent("FilmCan/logs", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.path
    }

    static func ensureWritableLogPath(_ path: String) -> Bool {
        let dir = (path as NSString).deletingLastPathComponent
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) {
            do {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            } catch {
                return false
            }
        }

        if !fm.fileExists(atPath: path) {
            let created = fm.createFile(atPath: path, contents: nil)
            if !created { return false }
        }

        if !fm.isWritableFile(atPath: path) {
            return false
        }

        if let handle = FileHandle(forWritingAtPath: path) {
            try? handle.close()
            return true
        }
        return false
    }
}
