import Foundation

@MainActor
protocol TransferService: AnyObject {
    var progress: TransferProgress { get }
    func resetProgress()
    func cancel()
    func pause()
}
