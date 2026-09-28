import AppKit
import SwiftUI

/// Shared by the live MenuBarExtra and its native rendering fixture.
struct StatusItemContent: View {
    let title: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(nsImage: Self.icon)
        }
        .labelStyle(.titleAndIcon)
        .accessibilityLabel("Codex \(title)")
    }

    private static let icon: NSImage = {
        // Packaged apps own this resource; SwiftPM runs use the module bundle.
        let url = Bundle.main.url(forResource: "StatusIconTemplate", withExtension: "png")
            ?? Bundle.module.url(forResource: "StatusIconTemplate", withExtension: "png")!
        let image = NSImage(contentsOf: url)!
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}
