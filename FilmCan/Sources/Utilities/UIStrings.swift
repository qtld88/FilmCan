import Foundation

enum UIStrings {
    enum Alerts {
        static let validationTitle = "Validation Error"
        static let insufficientSpaceTitle = "Insufficient Space"
        static let insufficientSpaceCancel = "Cancel"
        static let insufficientSpaceContinue = "Continue Anyway"
        static let deleteTitle = "Delete Files Not In Source"
        static let deleteCancel = "Cancel"
        static let deleteConfirm = "Delete and Run"
        static let deleteMessage = """
        This option removes any files in the destination that are not present in the source. It can permanently delete files if the destination contains extra data or if the wrong folder is selected.

        Are you sure you want to continue?
        """
    }

    enum DuplicatePrompt {
        static let title = "Duplicate found"
        static let sourceLabel = "Source"
        static let destinationLabel = "Destination"
        static let applyToAll = "Apply to all duplicates in this transfer"
        static let skip = "Skip"
        static let verifyHashList = "Verify using hash list"
        static let overwrite = "Overwrite"
        static let addCounter = "Add counter"
        static let cancelRun = "Cancel Run"
        static let noHashList = "No hash list found"
        static let counterStyleTitle = "Counter style"
        static let counterStylePlaceholder = "_001"
        static let counterStyleHint = "Used when you choose \"Add counter\"."
    }

    enum FolderPicker {
        static let title = "Select Folder"
        static let pathPlaceholder = "Path"
        static let chooseButton = "Choose..."
        static let cancel = "Cancel"
        static let select = "Select"
    }
}
