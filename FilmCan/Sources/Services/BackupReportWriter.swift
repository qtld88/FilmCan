import AppKit
import AVFoundation
import QuickLookThumbnailing

enum BackupReportWriter {
    static func reportPath(forLog logFilePath: String) -> String {
        ((logFilePath as NSString).deletingPathExtension) + "_report.pdf"
    }

    // MARK: - Thumbnails and durations

    private static let thumbnailSize = CGSize(width: 160, height: 90)

    static func thumbnail(for path: String, isVideo: Bool, isAudio: Bool) async -> NSImage {
        let fallback = { NSWorkspace.shared.icon(forFile: path) }
        if isAudio {
            let cfg = NSImage.SymbolConfiguration(pointSize: 40, weight: .regular)
            return NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg) ?? fallback()
        }
        guard isVideo else { return fallback() }

        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path), size: thumbnailSize,
            scale: 2, representationTypes: .thumbnail)
        let image: NSImage? = await withTaskGroup(of: NSImage?.self) { group in
            group.addTask {
                guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                else { return nil }
                return rep.nsImage
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return image ?? fallback()
    }

    static func duration(for path: String) async -> TimeInterval? {
        await withTaskGroup(of: TimeInterval?.self) { group in
            group.addTask {
                let asset = AVURLAsset(url: URL(fileURLWithPath: path))
                guard let t = try? await asset.load(.duration) else { return nil }
                let s = t.seconds
                return s.isFinite && s >= 0 ? s : nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - PDF rendering

    private static let pageWidth: CGFloat = 595
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat = 36
    private static let rowHeight: CGFloat = 64
    private static let footerHeight: CGFloat = 24

    private static func formatBytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    private static func formatClock(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    private final class Page {
        let ctx: CGContext
        var y: CGFloat = BackupReportWriter.margin
        var number = 0
        let generatedAt: String

        init(ctx: CGContext, generatedAt: String) {
            self.ctx = ctx
            self.generatedAt = generatedAt
        }

        func begin() {
            number += 1
            ctx.beginPDFPage(nil)
            ctx.saveGState()
            ctx.translateBy(x: 0, y: BackupReportWriter.pageHeight)
            ctx.scaleBy(x: 1, y: -1)
            y = BackupReportWriter.margin
        }

        func end() {
            let m = BackupReportWriter.margin
            let fy = BackupReportWriter.pageHeight - m + 6
            text(generatedAt, x: m, y: fy, w: 300, size: 8, color: .gray)
            text("Page \(number)", x: BackupReportWriter.pageWidth - m - 100, y: fy, w: 100,
                 size: 8, color: .gray, align: .right)
            ctx.restoreGState()
            ctx.endPDFPage()
        }

        @discardableResult
        func text(_ s: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat = 14,
                  size: CGFloat, bold: Bool = false, mono: Bool = false,
                  color: NSColor = .black, align: NSTextAlignment = .left) -> CGFloat {
            let font: NSFont = mono
                ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
                : (bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size))
            let para = NSMutableParagraphStyle()
            para.alignment = align
            para.lineBreakMode = .byTruncatingMiddle
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: color, .paragraphStyle: para]
            let prev = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            (s as NSString).draw(with: NSRect(x: x, y: y, width: w, height: h),
                                 options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                 attributes: attrs)
            NSGraphicsContext.current = prev
            return y + h
        }

        func image(_ img: NSImage, in box: NSRect) {
            let s = img.size
            guard s.width > 0, s.height > 0 else { return }
            let scale = min(box.width / s.width, box.height / s.height)
            let r = NSRect(x: box.minX + (box.width - s.width * scale) / 2,
                           y: box.minY + (box.height - s.height * scale) / 2,
                           width: s.width * scale, height: s.height * scale)
            let prev = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: true, hints: nil)
            NSGraphicsContext.current = prev
        }

        func line(y: CGFloat) {
            ctx.setStrokeColor(NSColor.lightGray.cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: BackupReportWriter.margin, y: y))
            ctx.addLine(to: CGPoint(x: BackupReportWriter.pageWidth - BackupReportWriter.margin, y: y))
            ctx.strokePath()
        }
    }

    static func render(_ report: BackupReport, thumbnails: [String: NSImage],
                       durations: [String: TimeInterval], to url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        let page = Page(ctx: ctx, generatedAt: "Generated \(df.string(from: Date()))")
        let contentW = pageWidth - 2 * margin
        let maxY = pageHeight - margin - footerHeight

        page.begin()

        // Header
        var y = page.text("FilmCan backup report", x: margin, y: page.y, w: contentW, h: 26, size: 20, bold: true)
        y += 4
        y = page.text(report.projectName, x: margin, y: y, w: contentW, h: 18, size: 13, bold: true)
        let shoot = [report.episode, report.day, report.unit].filter { !$0.isEmpty }.joined(separator: " · ")
        if !shoot.isEmpty { y = page.text(shoot, x: margin, y: y, w: contentW, size: 10, color: .darkGray) }
        y = page.text("Destination: \(report.destinationVolumeName) — \(report.destinationPath)",
                      x: margin, y: y, w: contentW, size: 10)
        let secs = max(0, report.endedAt.timeIntervalSince(report.startedAt))
        let red = NSColor(calibratedRed: 0.8, green: 0.1, blue: 0.1, alpha: 1)
        let green = NSColor(calibratedRed: 0.1, green: 0.55, blue: 0.2, alpha: 1)
        let status: (String, NSColor)
        if let recreated = report.recreated {
            y = page.text("Backed up \(df.string(from: report.startedAt))", x: margin, y: y, w: contentW, size: 10)
            y = page.text("Report created after the backup, on \(df.string(from: recreated.createdAt)), from what is on the drive.",
                          x: margin, y: y, w: contentW, size: 10)
            status = (recreated.statusText,
                      recreated.hasProblems ? red
                        : (recreated.recheck != nil && recreated.hasChecksumList) ? green : .darkGray)
        } else {
            y = page.text("\(df.string(from: report.startedAt)) → \(df.string(from: report.endedAt))  (\(formatClock(secs)))",
                          x: margin, y: y, w: contentW, size: 10)
            status = !report.success
                ? ("Failed", red)
                : report.verified
                    ? ("Verified ✓", green)
                    : ("Copied, not verified", .darkGray)
        }
        y = page.text(status.0, x: margin, y: y + 2, w: contentW, h: 16, size: 12, bold: true, color: status.1)
        if let w = report.warning, !w.isEmpty {
            y = page.text(w, x: margin, y: y, w: contentW, h: 28, size: 9, color: .orange)
        }
        y = page.text("FilmCan \(report.appVersion)", x: margin, y: y, w: contentW, size: 8, color: .gray)
        y += 8
        page.line(y: y)
        y += 8

        // Summary
        y = page.text("Summary", x: margin, y: y, w: contentW, h: 16, size: 12, bold: true)
        for roll in report.rolls {
            y = page.text("\(roll.name)  ·  \(roll.mediaKind.displayName)  ·  \(roll.clips.count) files  ·  \(formatBytes(roll.totalBytes))",
                          x: margin, y: y, w: contentW, size: 10)
        }
        if let missing = report.recreated?.missingFiles, !missing.isEmpty {
            y += 6
            y = page.text("In the checksum list, missing from the drive", x: margin, y: y, w: contentW,
                          h: 14, size: 10, bold: true, color: red)
            for name in missing.prefix(12) {
                y = page.text(name, x: margin, y: y, w: contentW, size: 8, color: .darkGray)
            }
            if missing.count > 12 {
                y = page.text("and \(missing.count - 12) more", x: margin, y: y, w: contentW, size: 8, color: .darkGray)
            }
        }
        y += 10
        page.y = y

        // Rolls
        for roll in report.rolls {
            func rollTitle(cont: Bool) {
                page.y = page.text(cont ? "\(roll.name) (cont.)" : roll.name,
                                   x: margin, y: page.y, w: contentW, h: 18, size: 13, bold: true) + 2
                page.line(y: page.y)
                page.y += 4
            }
            if page.y + 18 + 4 + rowHeight > maxY {
                page.end(); page.begin()
            }
            rollTitle(cont: false)

            for clip in roll.clips {
                if page.y + rowHeight > maxY {
                    page.end(); page.begin()
                    rollTitle(cont: true)
                }
                let top = page.y
                if let img = thumbnails[clip.absolutePath] {
                    page.image(img, in: NSRect(x: margin, y: top + 5, width: 96, height: 54))
                }
                let tx = margin + 108
                let textW = contentW - 108 - 150
                page.text(clip.name, x: tx, y: top + 6, w: textW, size: 10, bold: true)
                page.text(clip.relPath, x: tx, y: top + 21, w: textW, size: 8, color: .gray)
                if let sum = clip.checksum {
                    page.text("\(clip.checksumAlgorithm ?? "hash"): \(sum)", x: tx, y: top + 36,
                              w: contentW - 108, size: 7, mono: true, color: .darkGray)
                } else if let note = clip.note {
                    page.text(note, x: tx, y: top + 36, w: contentW - 108, size: 8, color: .orange)
                }
                let rx = pageWidth - margin - 140
                page.text(formatBytes(clip.size), x: rx, y: top + 6, w: 140, size: 10, align: .right)
                if let d = durations[clip.absolutePath] {
                    page.text(formatClock(d), x: rx, y: top + 21, w: 140, size: 9, color: .darkGray, align: .right)
                }
                page.y = top + rowHeight
            }
            page.y += 10
        }

        page.end()
        ctx.closePDF()
    }

    // MARK: - Entry point

    static func generate(result: TransferResult, config: BackupConfiguration) async -> String? {
        guard let logPath = result.logFilePath else { return nil }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let report = BackupReport.build(result: result, config: config, appVersion: version)
        return await write(report, toPath: reportPath(forLog: logPath))
    }

    /// Creates a report after the fact for one roll of the catalog on one connected
    /// drive, in the reports folder on this Mac. `recheck` re-reads every file (slow).
    /// Returns the PDF's path, nil when the roll is not reachable or the PDF failed.
    static func recreate(roll: CatalogRoll, copy: CatalogCopy, recheck: Bool,
                         base: URL = ReportArchive.baseURL(), now: Date = Date()) async -> String? {
        guard let rollFolder = ReportRecreation.currentRollFolder(
            copy: copy, mountedRootsByUUID: ReportRecreation.mountedRootsByUUID(),
            exists: { FileManager.default.fileExists(atPath: $0) }) else { return nil }
        let files = MediaCatalogStore.listFiles(inRollFolder: rollFolder)
        let checksums = ReportRecreation.checksums(rollFolder: rollFolder)
        let rechecked = recheck && checksums.found
            ? ReportRecreation.recheck(rollFolder: rollFolder, filesOnDisk: files, checksums: checksums)
            : nil
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let report = ReportRecreation.build(
            roll: roll, copy: copy, rollFolder: rollFolder, filesOnDisk: files,
            checksums: checksums, rechecked: rechecked, now: now, appVersion: version)
        let target = ReportRecreation.outputURL(roll: roll, copy: copy, base: base)
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        } catch {
            DebugLog.warn("Report: cannot create \(target.deletingLastPathComponent().path): \(error.localizedDescription)")
            return nil
        }
        return await write(report, toPath: target.path)
    }

    /// Thumbnails, durations, then the PDF at `finalPath` (replaced if present).
    private static func write(_ report: BackupReport, toPath finalPath: String) async -> String? {
        let targets = report.rolls.flatMap { $0.clips }.filter { $0.isVideo || $0.isAudio }

        var thumbs: [String: NSImage] = [:]
        var durs: [String: TimeInterval] = [:]
        var index = 0
        await withTaskGroup(of: (String, NSImage?, TimeInterval?).self) { group in
            func addNext() {
                guard index < targets.count else { return }
                let c = targets[index]; index += 1
                group.addTask {
                    async let img = thumbnail(for: c.absolutePath, isVideo: c.isVideo, isAudio: c.isAudio)
                    async let dur = duration(for: c.absolutePath)
                    return (c.absolutePath, await img, await dur)
                }
            }
            for _ in 0..<4 { addNext() }
            while let (path, img, dur) = await group.next() {
                if let img { thumbs[path] = img }
                if let dur { durs[path] = dur }
                addNext()
            }
        }
        // Non-media files get their file icon.
        for roll in report.rolls {
            for c in roll.clips where thumbs[c.absolutePath] == nil {
                thumbs[c.absolutePath] = NSWorkspace.shared.icon(forFile: c.absolutePath)
            }
        }

        let tmpURL = URL(fileURLWithPath: finalPath + ".tmp")
        let finalURL = URL(fileURLWithPath: finalPath)
        let renderedThumbs = thumbs, renderedDurs = durs
        do {
            try await MainActor.run {
                try render(report, thumbnails: renderedThumbs, durations: renderedDurs, to: tmpURL)
            }
            if FileManager.default.fileExists(atPath: finalPath) {
                _ = try FileManager.default.replaceItemAt(finalURL, withItemAt: tmpURL)
            } else {
                try FileManager.default.moveItem(at: tmpURL, to: finalURL)
            }
            return finalPath
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            DebugLog.warn("Backup report failed: \(error)")
            return nil
        }
    }
}
