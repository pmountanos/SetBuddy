//
//  ShareExportSheet.swift
//  Set Buddy
//

import SwiftUI
import UIKit

/// Presents the system share sheet for a file URL (Save to Files, AirDrop, etc.).
struct ShareExportSheet: UIViewControllerRepresentable {
    var items: [Any]
    var onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete()
        }
        if let popover = controller.popoverPresentationController {
            let bounds = UIScreen.main.bounds
            popover.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
            popover.sourceView = UIView()
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
