import AppKit

@main
struct UpdateMenuAppearanceTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let view = UpdateMenuAppearanceView()
        for title in ["新版本", "New Version"] {
            view.title = title
            view.hasAvailableUpdate = true
            let menu = NSMenu()
            let update = NSMenuItem(title: title, action: #selector(NSApplication.hide(_:)), keyEquivalent: "")
            let feedback = NSMenuItem(title: "Feedback", action: nil, keyEquivalent: "")
            menu.addItem(update)
            menu.addItem(feedback)
            guard update.attributedTitle != nil else {
                fatalError("Lazily inserted SwiftUI menu items must be styled when added")
            }
            NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
            let color = update.attributedTitle?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
            guard color == NSColor.systemGreen else {
                fatalError("Available update title must use native green text: \(title)")
            }
            precondition(feedback.attributedTitle == nil, "Other menu items must remain unchanged")
            precondition(update.action == #selector(NSApplication.hide(_:)), "Update action must remain unchanged")
            view.hasAvailableUpdate = false
            NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
            precondition(update.attributedTitle == nil, "Clearing availability must restore native title styling")
        }
        print("Native update menu appearance checks passed")
    }
}
