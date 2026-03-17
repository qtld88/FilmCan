import Foundation

extension TransferViewModel {
    struct DestinationPresentation {
        enum Status {
            case pending
            case active
            case done
            case failed
            case paused
        }

        let status: Status
        let progressText: String
        let speedText: String
        let etaText: String
        let failureMessage: String?
        let warningMessage: String?
        let canCancel: Bool
        let shouldShowInfo: Bool
    }

    func destinationPresentation(
        for destination: String,
        configId: UUID?,
        progress: TransferProgress
    ) -> DestinationPresentation {
        let isActiveTransfer = activeConfigId == configId
        let result = results.last { $0.destination == destination }
        let shouldShowInfo = isActiveTransfer && (isTransferring || result != nil)
        let status = destinationStatus(for: destination, result: result, progress: progress)
        let stats = destinationStats(for: destination, result: result, progress: progress)
        let failureMessage = failureStatus(for: result)
        let warningMessage = result?.warningMessage
        let canCancel = !cancelledDestinations.contains(destination)
            && result == nil
            && isTransferring

        return DestinationPresentation(
            status: status,
            progressText: stats.progressText,
            speedText: stats.speedText,
            etaText: stats.etaText,
            failureMessage: failureMessage,
            warningMessage: warningMessage,
            canCancel: canCancel,
            shouldShowInfo: shouldShowInfo
        )
    }

    private func destinationStatus(
        for destination: String,
        result: TransferResult?,
        progress: TransferProgress
    ) -> DestinationPresentation.Status {
        if let result {
            if result.wasPaused { return .paused }
            return result.success ? .done : .failed
        }
        if cancelledDestinations.contains(destination) { return .failed }
        if destination == currentDestination {
            if progress.isPaused { return .paused }
            if progress.isCancelled { return .failed }
            if progress.phase == .checksumming
                || progress.phase == .copying
                || progress.phase == .verifying
                || isTransferring {
                return .active
            }
        }
        return .pending
    }

    private func destinationStats(
        for destination: String,
        result: TransferResult?,
        progress: TransferProgress
    ) -> (progressText: String, speedText: String, etaText: String) {
        if destination == currentDestination {
            if progress.phase == .verifying {
                let progressText = progress.verificationFilesTotal > 0
                    ? progress.formattedVerificationProgress
                    : "Verifying…"
                return (progressText, "--", verificationEtaValue(progress))
            }
            if progress.phase == .finished,
               isTransferring,
               !progress.isCancelled,
               !progress.isPaused {
                return currentTransferStats(progress, etaOverride: "--")
            }
            if progress.isRunning {
                return currentTransferStats(progress, etaOverride: progress.formattedETA)
            }
        }

        let destinationResults = results.filter { $0.destination == destination }
        if let lastResult = destinationResults.last {
            if destinationResults.count > 1, !isTransferring {
                return cumulativeStats(for: destinationResults)
            }
            let totalBytes = lastResult.totalBytes > 0 ? lastResult.totalBytes : lastResult.bytesTransferred
            let totalText = totalBytes > 0 ? FilmCanFormatters.bytes(totalBytes, style: .decimal) : "--"
            let progressText: String
            if lastResult.wasPaused {
                let transferredText = lastResult.bytesTransferred > 0
                    ? FilmCanFormatters.bytes(lastResult.bytesTransferred, style: .decimal)
                    : "--"
                progressText = totalBytes > 0 ? "\(transferredText) / \(totalText)" : "--"
            } else if totalBytes > 0 {
                progressText = "\(totalText) / \(totalText)"
            } else {
                progressText = "--"
            }
            let speedText: String
            if let duration = lastResult.duration, duration > 0, lastResult.bytesTransferred > 0 {
                let avg = Double(lastResult.bytesTransferred) / duration
                speedText = FilmCanFormatters.speed(avg, style: .decimal)
            } else {
                speedText = "--"
            }
            let etaText: String
            if let duration = lastResult.duration, duration > 0 {
                etaText = FilmCanFormatters.durationCompact(duration)
            } else {
                etaText = "--"
            }
            return (progressText, speedText, etaText)
        }

        return ("--", "--", "--")
    }

    private func currentTransferStats(
        _ progress: TransferProgress,
        etaOverride: String
    ) -> (progressText: String, speedText: String, etaText: String) {
        let progressBytes = progress.cumulativeBytes > 0 ? progress.cumulativeBytes : progress.bytesCompleted
        let progressText: String
        if progress.totalBytes > 0 {
            let done = FilmCanFormatters.bytes(progressBytes, style: .decimal)
            let total = FilmCanFormatters.bytes(progress.totalBytes, style: .decimal)
            progressText = "\(done) / \(total)"
        } else {
            progressText = FilmCanFormatters.bytes(progressBytes, style: .decimal)
        }
        let speedText = FilmCanFormatters.speed(progress.speedBytesPerSecond, style: .decimal)
        return (progressText, speedText, etaOverride)
    }

    private func cumulativeStats(
        for results: [TransferResult]
    ) -> (progressText: String, speedText: String, etaText: String) {
        let totalBytes = results.reduce(Int64(0)) { total, result in
            let bytes = result.totalBytes > 0 ? result.totalBytes : result.bytesTransferred
            return total + bytes
        }
        let transferredBytes = results.reduce(Int64(0)) { total, result in
            total + result.bytesTransferred
        }
        let duration = results.compactMap { $0.duration }.reduce(0, +)
        let totalText = totalBytes > 0 ? FilmCanFormatters.bytes(totalBytes, style: .decimal) : "--"
        let transferredText = transferredBytes > 0
            ? FilmCanFormatters.bytes(transferredBytes, style: .decimal)
            : "--"
        let progressText: String
        if results.contains(where: { $0.wasPaused }) {
            progressText = totalBytes > 0 ? "\(transferredText) / \(totalText)" : "--"
        } else if totalBytes > 0 {
            progressText = "\(totalText) / \(totalText)"
        } else {
            progressText = "--"
        }
        let speedText: String
        if duration > 0, transferredBytes > 0 {
            let avg = Double(transferredBytes) / duration
            speedText = FilmCanFormatters.speed(avg, style: .decimal)
        } else {
            speedText = "--"
        }
        let etaText: String
        if duration > 0 {
            etaText = FilmCanFormatters.durationCompact(duration)
        } else {
            etaText = "--"
        }
        return (progressText, speedText, etaText)
    }

    private func verificationEtaValue(_ progress: TransferProgress) -> String {
        if let eta = progress.estimatedTimeRemaining, eta > 0 {
            return FilmCanFormatters.durationCompact(eta)
        }
        guard let start = progress.verificationStartTime else { return "--" }
        let estimate = max(progress.verificationEstimatedDuration ?? 0, 0)
        if estimate <= 0 {
            return "--"
        }
        let elapsed = Date().timeIntervalSince(start)
        let remaining = max(0, estimate - elapsed)
        return FilmCanFormatters.durationCompact(remaining)
    }

    private func failureStatus(for result: TransferResult?) -> String? {
        guard let result, !result.success else { return nil }
        if let message = result.errorMessage, !message.isEmpty {
            return message
        }
        return "Failed"
    }
}
