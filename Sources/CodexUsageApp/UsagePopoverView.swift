import AppKit
import CodexUsageCore
import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var controller: UsageController
    @ObservedObject var updater: UpdateCoordinator

    private var presentation: MenuPresentation {
        MenuPresentation(
            snapshot: controller.snapshot,
            isRefreshing: controller.isRefreshing,
            error: controller.displayError,
            appearance: controller.appearance,
            language: controller.language,
            canCheckForUpdates: updater.canCheckForUpdates,
            hasAvailableUpdate: updater.hasAvailableUpdate
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            usageSection
            Divider()
                .padding(.horizontal, 20)
            preferencesFooter
            actionsSection
        }
        .frame(width: 348)
        .background(popoverBackgroundColor)
        .environment(\.colorScheme, controller.appearance == .dark ? .dark : .light)
        .background(
            PopoverAppearanceBridge(
                appearanceName: controller.appearance.nativeAppearancePolicy.popoverName
            )
        )
        .onAppear {
            updater.checkForUpdateInformation()
            Task { await controller.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSLocale.currentLocaleDidChangeNotification
        )) { _ in
            controller.notifySystemLocaleChanged()
        }
    }

    private var popoverBackgroundColor: Color {
        switch controller.appearance.nativeAppearancePolicy.backgroundStyle {
        case .opaqueWhite:
            .white
        case .opaqueWindow:
            Color(nsColor: .windowBackgroundColor)
        }
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let remaining = presentation.remainingPercent {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(presentation.text(.codexRemaining))
                        .font(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 16)
                    Text(presentation.usagePercentText)
                        .font(.system(size: 23, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                ProgressView(value: Double(remaining), total: 100)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .scaleEffect(x: 1, y: 1.4, anchor: .center)
                    .padding(.vertical, 2)

                if presentation.nextResetText != nil || presentation.availableResetsText != nil {
                    resetMetadata
                }

                if let fiveHourStatus = presentation.fiveHourStatusText {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(presentation.text(.fiveHourRemaining))
                        Spacer(minLength: 8)
                        Text(fiveHourStatus)
                    }
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(presentation.text(.loading))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            }

            if let error = presentation.errorText {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if !presentation.displayedAdditionalBuckets.isEmpty {
                ForEach(presentation.displayedAdditionalBuckets, id: \.limitId) { _ in
                    EmptyView()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var resetMetadata: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if let nextReset = presentation.nextResetText {
                        Text(nextReset)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 8)
                    if let resetCount = presentation.availableResetsText {
                        Text(resetCount)
                            .lineLimit(1)
                    }
                }
                if let countdown = presentation.resetCountdownText(at: context.date) {
                    Text(countdown)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
        }
    }

    private var preferencesFooter: some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(presentation.appearanceOptions, id: \.value) { option in
                    selectionButton(option) {
                        controller.setAppearance(option.value)
                    }
                }
            } label: {
                preferenceCell(
                    symbol: "circle.lefthalf.filled",
                    summary: presentation.appearanceSummary
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity)
            .layoutPriority(1)

            Divider()
                .frame(height: 32)

            Menu {
                ForEach(presentation.languageOptions, id: \.value) { option in
                    selectionButton(option) {
                        controller.setLanguage(option.value)
                    }
                }
            } label: {
                preferenceCell(
                    symbol: "globe",
                    summary: presentation.languageSummary
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity)
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity)
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var actionsSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    Task { await controller.refresh() }
                } label: {
                    compactActionCell(
                        title: presentation.text(.refreshNow),
                        symbol: "arrow.clockwise"
                    )
                }
                .buttonStyle(.plain)
                .disabled(controller.isRefreshing)

                Divider()
                    .frame(height: 32)

                Button {
                    updater.checkForUpdates()
                } label: {
                    compactActionCell(
                        title: presentation.checkForUpdatesTitle,
                        symbol: "arrow.down.circle",
                        titleColor: presentation.hasAvailableUpdate ? .green : .primary
                    )
                }
                .buttonStyle(.plain)
                .disabled(!presentation.isUpdateEnabled)
            }
            .frame(maxWidth: .infinity)
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 20)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                actionRow(
                    title: presentation.text(.quit),
                    symbol: "rectangle.portrait.and.arrow.right",
                    trailing: AppVersion.current
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func preferenceCell(symbol: String, summary: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 16)
            Text(summary)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
        .frame(minHeight: 36)
        .padding(.horizontal, 8)
    }

    private func selectionButton<Value>(
        _ option: MenuOption<Value>,
        action: @escaping () -> Void
    ) -> some View where Value: Equatable & Sendable {
        Button(action: action) {
            if option.isSelected {
                Label(option.title, systemImage: "checkmark")
            } else {
                Text(option.title)
            }
        }
    }

    private func actionRow(
        title: String,
        symbol: String,
        trailing: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 14))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private func compactActionCell(
        title: String, symbol: String, titleColor: Color = .primary
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(titleColor)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, minHeight: 36)
        .padding(.horizontal, 8)
    }

}

private struct PopoverAppearanceBridge: NSViewRepresentable {
    let appearanceName: String

    func makeNSView(context: Context) -> PopoverAppearanceView {
        PopoverAppearanceView(appearanceName: appearanceName)
    }

    func updateNSView(_ nsView: PopoverAppearanceView, context: Context) {
        nsView.appearanceName = appearanceName
    }
}

private final class PopoverAppearanceView: NSView {
    private var isPositioning = false
    private var updatePending = false
    var appearanceName: String {
        didSet { applyAppearance() }
    }

    init(appearanceName: String) {
        self.appearanceName = appearanceName
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
        if let window {
            // Ancestor origins can settle after the surface's own frame. Those
            // changes also affect its screen position and native mask bounds.
            for view in sequence(first: self as NSView, next: { $0.superview }) {
                view.postsFrameChangedNotifications = true
                view.postsBoundsChangedNotifications = true
                for name in [NSView.frameDidChangeNotification, NSView.boundsDidChangeNotification] {
                    NotificationCenter.default.addObserver(
                        self, selector: #selector(surfaceDidChange), name: name, object: view
                    )
                }
            }
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidResize),
                name: NSWindow.didResizeNotification, object: window
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidMove),
                name: NSWindow.didMoveNotification, object: window
            )
        }
        applyAppearance()
    }

    override func layout() {
        super.layout()
        updateWindowMask()
        scheduleWindowUpdate()
    }

    private func applyAppearance() {
        // Clip native material to the actual SwiftUI surface. MenuBarExtra can
        // add padding outside that surface, so window bounds are not its bounds.
        window?.isOpaque = false
        window?.backgroundColor = .clear
        updateWindowMask()
        window?.appearance = NSAppearance(
            named: NSAppearance.Name(rawValue: appearanceName)
        )
        scheduleWindowUpdate()
    }

    @objc private func windowDidResize(_ notification: Notification) {
        updateWindowMask()
        scheduleWindowUpdate()
    }

    @objc private func windowDidMove(_ notification: Notification) {
        scheduleWindowUpdate()
    }

    private func scheduleWindowUpdate() {
        guard !updatePending else { return }
        updatePending = true
        // Window resize notifications can precede the hosting view's final
        // frame. Reapply the mask and anchor after that geometry has settled.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updatePending = false
            self.updateWindowMask()
            self.alignVisibleSurface()
        }
    }

    @objc private func surfaceDidChange(_ notification: Notification) {
        scheduleWindowUpdate()
    }

    private func alignVisibleSurface() {
        guard !isPositioning, !bounds.isEmpty, let window,
              let statusWindow = NSApp.windows.first(where: {
                  $0 !== window && $0.isVisible && $0.screen == window.screen
                      && $0.contentView.map(containsStatusButton) == true
              }) else { return }
        // Native MenuBarExtra padding remains part of the window even after
        // masking it away. Anchor the visible surface, not that invisible frame.
        let surface = window.convertToScreen(convert(bounds, to: nil))
        let delta = statusWindow.frame.minY - 2 - surface.maxY
        guard abs(delta) > 0.5 else { return }
        isPositioning = true
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: window.frame.minY + delta))
        isPositioning = false
    }

    private func containsStatusButton(_ view: NSView) -> Bool {
        view is NSStatusBarButton || view.subviews.contains(where: containsStatusButton)
    }

    private func updateWindowMask() {
        guard let frameView = window?.contentView?.superview,
              !bounds.isEmpty else { return }
        let surface = convert(bounds, to: frameView)
            .offsetBy(dx: -frameView.bounds.minX, dy: -frameView.bounds.minY)
        frameView.wantsLayer = true
        let mask = CAShapeLayer()
        mask.frame = frameView.bounds
        mask.path = CGPath(
            roundedRect: surface,
            cornerWidth: 14, cornerHeight: 14, transform: nil
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frameView.layer?.mask = mask
        CATransaction.commit()
        window?.invalidateShadow()
    }
}
