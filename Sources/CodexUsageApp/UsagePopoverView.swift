import AppKit
import CodexUsageCore
import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var controller: UsageController
    @ObservedObject var updater: UpdateCoordinator
    @Environment(\.openURL) private var openURL

    private var presentation: MenuPresentation {
        MenuPresentation(snapshot: controller.snapshot, isRefreshing: controller.isRefreshing,
                         error: controller.displayError, appearance: controller.appearance,
                         language: controller.language, canCheckForUpdates: updater.canCheckForUpdates,
                         hasAvailableUpdate: updater.hasAvailableUpdate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            allowance
            if presentation.availableResetsText != nil {
                Divider()
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    HStack(alignment: .center, spacing: 12) {
                        Label(LocalizationCatalog.format(
                            (controller.snapshot?.availableResetCount ?? 0) == 1 ? .resetCreditCount : .resetCreditsCount,
                            language: controller.language, controller.snapshot?.availableResetCount ?? 0),
                              systemImage: "ticket")
                        if let expiry = presentation.resetCreditExpiryText(at: context.date) {
                            Divider().frame(height: 24)
                            Label(LocalizationCatalog.format(.nextCreditExpiry, language: controller.language, expiry),
                                  systemImage: "calendar")
                        }
                    }
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            newsSection
        }
        .padding(20)
        .frame(width: 400)
        .background(controller.appearance == .dark ? Color(nsColor: .windowBackgroundColor) : .white)
        .environment(\.colorScheme, controller.appearance == .dark ? .dark : .light)
        .background(PopoverAppearanceBridge(
            appearanceName: controller.appearance.nativeAppearancePolicy.popoverName))
        .background(UpdateMenuAppearance(
            title: presentation.checkForUpdatesTitle,
            hasAvailableUpdate: updater.hasAvailableUpdate))
        .onAppear {
            updater.checkForUpdateInformation()
            Task { await controller.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
            controller.notifySystemLocaleChanged()
        }
    }

    private var header: some View {
        HStack {
            Text("Codex").font(.system(size: 23, weight: .bold))
            Spacer()
            Button {
                Task { await controller.refresh(forceNews: true) }
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 19))
            }
            .buttonStyle(.plain)
            .disabled(controller.isRefreshing)
            .help(presentation.text(.refreshNow))
            .accessibilityLabel(presentation.text(.refreshNow))
            Divider().frame(height: 22).padding(.horizontal, 8)
            Menu {
                Menu(presentation.text(.appearance)) {
                    ForEach(presentation.appearanceOptions, id: \.value) { option in
                        selectionButton(option) { controller.setAppearance(option.value) }
                    }
                }
                Menu(presentation.text(.language)) {
                    ForEach(presentation.languageOptions, id: \.value) { option in
                        selectionButton(option) { controller.setLanguage(option.value) }
                    }
                }
                Divider()
                Button(presentation.checkForUpdatesTitle) { updater.checkForUpdates() }
                    .disabled(!presentation.isUpdateEnabled)
                Button(presentation.text(.feedback)) { openURL(presentation.feedbackURL) }
                Divider()
                Button(presentation.text(.quit) + (AppVersion.current.map { " · " + $0 } ?? "")) {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "gearshape")
                    .resizable().scaledToFit().frame(width: 21, height: 21)
            }
            .menuStyle(.borderlessButton)
            .controlSize(.large)
            .menuIndicator(.hidden)
            .fixedSize()
            // The native Menu recolors its label. Draw the status icon above it
            // while leaving clicks and accessibility on the original menu.
            .overlay {
                Image(systemName: "gearshape")
                    .resizable().scaledToFit().frame(width: 21, height: 21)
                    .foregroundStyle(updater.hasAvailableUpdate ? .green : .secondary)
                    .background(controller.appearance == .dark ? Color(nsColor: .windowBackgroundColor) : .white)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .help(presentation.text(.settings))
            .accessibilityLabel(presentation.text(.settings))
        }
    }

    private var allowance: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let remaining = presentation.remainingPercent {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(remaining)%")
                        .font(.system(size: 42, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.blue)
                    Text(presentation.text(.remainingAllowance))
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(Color.blue)
                            .frame(width: geometry.size.width * Double(remaining) / 100)
                    }
                }
                .frame(height: 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(presentation.text(.remainingAllowance))
                .accessibilityValue("\(remaining)%")
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: 12) {
                        if let reset = presentation.nextResetDateText {
                            metadataRow(symbol: "clock", title: presentation.text(.allowanceRecovery)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(reset)
                                    if let countdown = presentation.resetCountdownText(at: context.date) {
                                        Text(countdown).font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        metadataRow(symbol: "chart.bar.fill", title: presentation.text(.fiveHourRemaining)) {
                            Text(presentation.fiveHourRemainingPercent.map { "\($0)%" }
                                 ?? presentation.text(.unlimited))
                        }
                    }
                }
            } else {
                HStack {
                    if let error = presentation.errorText {
                        Text(error).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    } else {
                        if controller.isRefreshing { ProgressView().controlSize(.small) }
                        Text(presentation.text(.loading)).foregroundStyle(.secondary)
                    }
                }.frame(minHeight: 70)
            }
            if presentation.remainingPercent != nil, let error = presentation.errorText {
                Text(error).font(.footnote).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
    }

    private var newsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(presentation.text(.resetNews)).font(.system(size: 16, weight: .semibold))
                Spacer()
                Link("divin.cc ↗", destination: ResetNews.sourceURL)
                    .font(.system(size: 13))
            }
            if let news = controller.resetNews {
                metadataRow(symbol: "globe", title: presentation.text(.lastGlobalReset)) {
                    Text(news.completedAt.map {
                        LocalizationCatalog.dateTime($0, language: controller.language)
                    } ?? presentation.text(.newsEmpty))
                }
                metadataRow(symbol: "clock", title: presentation.text(.latestForecast)) {
                    if let forecast = news.forecast {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(news.forecastText(language: controller.language))
                                    .foregroundStyle(.orange)
                                Text(forecast.statusText(language: controller.language, now: context.date))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.10), in: Capsule())
                            }
                        }
                    } else {
                        Text(presentation.text(.newsNoForecast)).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(presentation.text(controller.newsFailed ? .newsUnavailable : .newsLoading))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if controller.newsFailed && controller.resetNews != nil {
                Text(presentation.text(.newsStale)).font(.system(size: 11)).foregroundStyle(.orange)
            }
            Divider()
            Text(presentation.text(.newsSourceNote))
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metadataRow<Content: View>(symbol: String, title: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15)).frame(width: 18)
                .foregroundStyle(.secondary)
            Text(title).foregroundStyle(.secondary).frame(width: 112, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12.5))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func selectionButton<Value>(_ option: MenuOption<Value>, action: @escaping () -> Void) -> some View
    where Value: Equatable & Sendable {
        Button(action: action) {
            if option.isSelected { Label(option.title, systemImage: "checkmark") }
            else { Text(option.title) }
        }
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
