import AppKit
import SwiftUI

// MenuBarExtra can reserve padding outside the content. A layer mask hides that
// padding, but WindowServer still puts the window shadow around the larger frame.
// Keep the content's intrinsic height and fit the native frame to that surface.
struct ContentSizedPopover<Content: View>: View {
    @State private var verticalCompensation: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(PopoverSizingBridge(compensation: verticalCompensation) {
                verticalCompensation = $0
            })
            // Cancel the measured host padding without shrinking the content.
            .padding(.vertical, -verticalCompensation)
            .frame(maxHeight: .infinity)
    }
}

private struct PopoverSizingBridge: NSViewRepresentable {
    let compensation: CGFloat
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> PopoverSizingView {
        PopoverSizingView()
    }

    func updateNSView(_ nsView: PopoverSizingView, context: Context) {
        nsView.compensation = compensation
        nsView.onChange = onChange
        nsView.scheduleMeasurement()
    }
}

private final class PopoverSizingView: NSView {
    var compensation: CGFloat = 0
    var onChange: ((CGFloat) -> Void)?
    private var measurementPending = false
    private var previousHeight: CGFloat?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: self)
        if let window {
            postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(geometryDidChange),
                name: NSWindow.didResizeNotification, object: window
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(geometryDidChange),
                name: NSView.frameDidChangeNotification, object: self
            )
        }
        scheduleMeasurement()
    }

    override func layout() {
        super.layout()
        scheduleMeasurement()
    }

    @objc private func geometryDidChange(_ notification: Notification) {
        scheduleMeasurement()
    }

    func scheduleMeasurement() {
        guard !measurementPending else { return }
        measurementPending = true
        // SwiftUI must finish its layout before state or native geometry changes.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.measurementPending = false
            guard !self.bounds.isEmpty, let window = self.window else { return }
            var frame = window.frame
            let heightChanged = self.previousHeight.map { abs($0 - self.bounds.height) > 0.5 } ?? false
            self.previousHeight = self.bounds.height
            guard abs(frame.height - self.bounds.height) > 0.5 else { return }
            let next = max(0, self.compensation + (frame.height - self.bounds.height) / 2)
            // A disappearing error can leave the old window height behind. That
            // difference is content shrinkage, not newly added native padding.
            if !heightChanged, abs(next - self.compensation) > 0.5 {
                self.onChange?(next)
            }
            // Older SDK compatibility modes retain their previous window size;
            // negative SwiftUI padding alone does not move the native shadow.
            frame.origin.y += frame.height - self.bounds.height
            frame.size.height = self.bounds.height
            window.setFrame(frame, display: true)
        }
    }
}
