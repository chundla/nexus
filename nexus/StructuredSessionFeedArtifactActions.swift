import Foundation
import NexusSessionPresentation

#if os(macOS)
    import AppKit

    enum StructuredSessionFeedArtifactHostActions {
        static func openOnHost(path: String) {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("/") else {
                return
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: trimmed))
        }
    }
#endif

#if os(iOS)
    import UIKit

    enum StructuredSessionFeedArtifactSharePresenter {
        static func presentShare(for fileURL: URL, from viewController: UIViewController?) {
            let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            viewController?.present(controller, animated: true)
        }
    }
#endif
