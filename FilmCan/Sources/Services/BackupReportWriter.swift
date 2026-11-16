import AppKit
import AVFoundation
import MediaToolbox
import QuickLookThumbnailing
import VideoToolbox

enum BackupReportWriter {
    static func reportPath(forLog logFilePath: String) -> String {
        ((logFilePath as NSString).deletingPathExtension) + "_report.pdf"
    }

    // MARK: - Thumbnails and durations

    private static let thumbnailSize = CGSize(width: 160, height: 90)

    /// Lets AVFoundation open MXF through Apple's Pro Video Formats readers when they are
    /// installed; a no-op otherwise. Must run before the first AVURLAsset of the process.
    private static let proVideoFormatsRegistered: Void = {
        MTRegisterProfessionalVideoWorkflowFormatReaders()
        VTRegisterProfessionalVideoWorkflowVideoDecoders()
    }()

    private static func withTimeout<T>(_ work: @escaping () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Stills at 1 s, the middle and the end of the clip; nil when AVFoundation can't
    /// decode it (BRAW, R3D, ARRIRAW, or MXF without Pro Video Formats).
    private static func frameStrip(_ url: URL) async -> [NSImage]? {
        _ = proVideoFormatsRegistered
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.seconds.isFinite,
              duration.seconds > 0 else { return nil }
        let d = duration.seconds
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: thumbnailSize.width * 2, height: thumbnailSize.height * 2)
        var stills: [NSImage] = []
        for t in [min(1, d / 2), d / 2, max(0, d - 1)] {
            guard let (cg, _) = try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600))
            else { continue }
            stills.append(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
        }
        return stills.isEmpty ? nil : stills
    }

    /// Up to three stills for a video (start, middle, end); one image otherwise.
    static func stills(for path: String, isVideo: Bool, isAudio: Bool) async -> [NSImage] {
        let fallback = { [NSWorkspace.shared.icon(forFile: path)] }
        if isAudio {
            let cfg = NSImage.SymbolConfiguration(pointSize: 40, weight: .regular)
            guard let wave = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg) else { return fallback() }
            return [wave]
        }
        let url = URL(fileURLWithPath: path)
        if isVideo, let strip = await withTimeout({ () async -> [NSImage]? in await frameStrip(url) }) {
            return strip
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: thumbnailSize, scale: 2, representationTypes: .thumbnail)
        if let image = await withTimeout({ () async -> NSImage? in
            try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        }) {
            return [image]
        }
        return fallback()
    }

    static func duration(for path: String) async -> TimeInterval? {
        _ = proVideoFormatsRegistered
        return await withTimeout { () async -> TimeInterval? in
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            guard let t = try? await asset.load(.duration) else { return nil }
            let s = t.seconds
            return s.isFinite && s >= 0 ? s : nil
        }
    }

    // MARK: - PDF rendering

    private static let pageWidth: CGFloat = 595
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat = 36
    private static let rowHeight: CGFloat = 76
    private static let compactRowHeight: CGFloat = 26
    private static let stillW: CGFloat = 96
    private static let stillH: CGFloat = 54
    private static let stillGap: CGFloat = 4
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

    static func render(_ report: BackupReport, thumbnails: [String: [NSImage]],
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
                      recreated.hasProblems ? red : recreated.isFullyRechecked ? green : .darkGray)
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
                let height = clip.isMedia ? rowHeight : compactRowHeight
                if page.y + height > maxY {
                    page.end(); page.begin()
                    rollTitle(cont: true)
                }
                let top = page.y
                guard clip.isMedia else {
                    page.text(clip.relPath, x: margin, y: top + 3, w: contentW - 80, size: 8, color: .darkGray)
                    page.text(formatBytes(clip.size), x: pageWidth - margin - 80, y: top + 3, w: 80,
                              size: 8, color: .darkGray, align: .right)
                    if let sum = clip.checksum {
                        page.text("\(clip.checksumAlgorithm ?? "hash"): \(sum)", x: margin, y: top + 14,
                                  w: contentW, size: 7, mono: true, color: .gray)
                    } else if let note = clip.note {
                        page.text(note, x: margin, y: top + 14, w: contentW, size: 7, color: .orange)
                    }
                    page.y = top + height
                    continue
                }
                for (i, img) in (thumbnails[clip.absolutePath] ?? []).prefix(3).enumerated() {
                    let x = margin + CGFloat(i) * (stillW + stillGap)
                    page.image(img, in: NSRect(x: x, y: top + 5, width: stillW, height: stillH))
                }
                let tx = margin + 3 * stillW + 2 * stillGap + 10
                let textW = contentW - (tx - margin)
                let sideW: CGFloat = 70
                page.text(clip.name, x: tx, y: top + 6, w: textW - sideW, size: 10, bold: true)
                page.text(formatBytes(clip.size), x: tx + textW - sideW, y: top + 6, w: sideW, size: 10, align: .right)
                page.text(clip.relPath, x: tx, y: top + 21, w: textW - sideW, size: 8, color: .gray)
                if let d = durations[clip.absolutePath] {
                    page.text(formatClock(d), x: tx + textW - sideW, y: top + 21, w: sideW,
                              size: 9, color: .darkGray, align: .right)
                }
                if let sum = clip.checksum {
                    page.text("\(clip.checksumAlgorithm ?? "hash"): \(sum)", x: margin, y: top + stillH + 8,
                              w: contentW, size: 7, mono: true, color: .darkGray)
                } else if let note = clip.note {
                    page.text(note, x: margin, y: top + stillH + 8, w: contentW, size: 8, color: .orange)
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
            checksums: checksums, rechecked: rechecked,
            existsOnDrive: { FileManager.default.fileExists(atPath: (rollFolder as NSString).appendingPathComponent($0)) },
            now: now, appVersion: version)
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
        let targets = report.rolls.flatMap { $0.clips }.filter(\.isMedia)

        var thumbs: [String: [NSImage]] = [:]
        var durs: [String: TimeInterval] = [:]
        var index = 0
        await withTaskGroup(of: (String, [NSImage], TimeInterval?).self) { group in
            func addNext() {
                guard index < targets.count else { return }
                let c = targets[index]; index += 1
                group.addTask {
                    async let img = stills(for: c.absolutePath, isVideo: c.isVideo, isAudio: c.isAudio)
                    async let dur = duration(for: c.absolutePath)
                    return (c.absolutePath, await img, await dur)
                }
            }
            for _ in 0..<4 { addNext() }
            while let (path, img, dur) = await group.next() {
                if !img.isEmpty { thumbs[path] = img }
                if let dur { durs[path] = dur }
                addNext()
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
