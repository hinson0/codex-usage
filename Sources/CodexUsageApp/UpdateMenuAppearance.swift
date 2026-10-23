import AppKit
import SwiftUI

struct UpdateMenuAppearance: NSViewRepresentable {
    let title: String
    let hasAvailableUpdate: Bool

    func makeNSView(context: Context) -> UpdateMenuAppearanceView {
        UpdateMenuAppearanceView()
    }

    func updateNSView(_ view: UpdateMenuAppearanceView, context: Context) {
        view.title = title
        view.hasAvailableUpdate = hasAvailableUpdate
    }
}

@MainActor
final class UpdateMenuAppearanceView: NSView {
    var title = ""
    var hasAvailableUpdate = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuWillTrack(_:)),
            name: NSMenu.didBeginTrackingNotification, object: nil
        )
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(menuWillTrack(_:)), name: name, object: nil
            )
        }
    }

    required init?(coder: NSCoder) { nil }

    @objc private func menuWillTrack(_ notification: Notification) {
        guard !title.isEmpty, let menu = notification.object as? NSMenu else { return }
        // SwiftUI's native menu ignores foregroundStyle on Button labels.
        // Apply AppKit's supported attributed title as the menu opens.
        for item in menu.items where item.title == title && item.submenu == nil {
            let styledTitle = hasAvailableUpdate
                ? NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.systemGreen])
                : nil
            // SwiftUI builds menu items lazily and may replace their titles.
            // Avoid re-entering didChangeItemNotification for our own change.
            if item.attributedTitle != styledTitle {
                item.attributedTitle = styledTitle
            }
        }
    }
}
