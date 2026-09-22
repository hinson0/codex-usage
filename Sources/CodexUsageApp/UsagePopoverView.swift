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
            .frame(width: 0, height: 0)
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
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
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
        if let window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidResize),
                name: NSWindow.didResizeNotification, object: window
            )
        }
        applyAppearance()
    }

    private func applyAppearance() {
        // SwiftUI supplies an opaque rectangular fill. A single mask clips the
        // complete native frame, including MenuBarExtra's system material.
        window?.isOpaque = false
        window?.backgroundColor = .clear
        updateWindowMask()
        window?.appearance = NSAppearance(
            named: NSAppearance.Name(rawValue: appearanceName)
        )
    }

    @objc private func windowDidResize(_ notification: Notification) {
        updateWindowMask()
    }

    private func updateWindowMask() {
        guard let frameView = window?.contentView?.superview else { return }
        frameView.wantsLayer = true
        let mask = CAShapeLayer()
        mask.frame = frameView.bounds
        mask.path = CGPath(
            roundedRect: CGRect(origin: .zero, size: frameView.bounds.size),
            cornerWidth: 14, cornerHeight: 14, transform: nil
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frameView.layer?.mask = mask
        CATransaction.commit()
        window?.invalidateShadow()
    }
}
