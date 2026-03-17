import Foundation

struct PreviewInfo {
    var totalBytes: Int64 = 0
    var fileCount: Int = 0
    var folderCount: Int = 0
    var sourceSizes: [String: Int64] = [:]
    var sourceItemCounts: [String: Int] = [:]
    var isLoading: Bool = false
}
