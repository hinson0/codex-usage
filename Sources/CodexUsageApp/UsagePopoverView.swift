import AppKit
import CodexUsageCore
import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var controller: UsageController
    @State private var showsResetConfirmation = false

    private var presentation: MenuPresentation {
        MenuPresentation(
            snapshot: controller.snapshot,
            lastReset: nil,
            resetHistory: controller.resetHistory,
            isRefreshing: controller.isRefreshing,
            isRedeeming: controller.isRedeeming,
            error: controller.displayError,
            appearance: controller.appearance,
            language: controller.language
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            usageSection
            Divider()
                .padding(.horizontal, 20)
            resetSection
            Divider()
                .padding(.horizontal, 20)
            preferencesFooter
            Divider()
                .padding(.horizontal, 20)
            actionsSection
        }
        .frame(width: 348)
        .environment(\.colorScheme, controller.appearance == .dark ? .dark : .light)
        .background(
            PopoverAppearanceBridge(
                appearanceName: controller.appearance.nativeAppearancePolicy.popoverName
            )
            .frame(width: 0, height: 0)
        )
        .onAppear {
            Task { await controller.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSLocale.currentLocaleDidChangeNotification
        )) { _ in
            controller.notifySystemLocaleChanged()
        }
        .alert(presentation.text(.confirmResetTitle), isPresented: $showsResetConfirmation) {
            Button(presentation.text(.cancel), role: .cancel) {}
            Button(presentation.text(.confirm), role: .destructive) {
                Task { await controller.redeemReset() }
            }
        } message: {
            Text(presentation.text(.confirmResetMessage))
        }
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let remaining = presentation.remainingPercent {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(presentation.text(.codexRemaining))
                        .font(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 16)
                    Text("\(remaining)%")
                        .font(.system(size: 23, weight: .bold))
                        .monospacedDigit()
                }

                ProgressView(value: Double(remaining), total: 100)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .scaleEffect(x: 1, y: 1.4, anchor: .center)
                    .padding(.vertical, 2)

                if let nextReset = presentation.nextResetText {
                    Text(nextReset)
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
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var resetSection: some View {
        if presentation.isResetEnabled || controller.isRedeeming {
            VStack(alignment: .leading, spacing: 12) {
                if let count = presentation.availableResetsText {
                    Text(count)
                        .font(.system(size: 15, weight: .semibold))
                }

                Button {
                    showsResetConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        if controller.isRedeeming {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(presentation.resetActionTitle)
                        Spacer()
                    }
                    .frame(minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!presentation.isResetEnabled)

                resetHistoryView
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        } else {
            VStack(spacing: 10) {
                Text(presentation.resetActionTitle)
                    .font(.system(size: 15, weight: .semibold))
                resetHistoryView
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
    }

    private var resetHistoryView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if presentation.resetHistoryTexts.isEmpty {
                Text(presentation.text(.noResetHistory))
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text(presentation.text(.resetHistory))
                    .font(.system(size: 11.5, weight: .semibold))
                    .textCase(.uppercase)

                ForEach(Array(presentation.resetHistoryTexts.enumerated()), id: \.offset) { _, row in
                    Text(row)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(.vertical, 12)
    }

    private var actionsSection: some View {
        VStack(spacing: 2) {
            Button {
                Task { await controller.refresh() }
            } label: {
                actionRow(
                    title: presentation.text(.refreshNow),
                    symbol: "arrow.clockwise"
                )
            }
            .buttonStyle(.plain)
            .disabled(controller.isRefreshing || controller.isRedeeming)

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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func preferenceCell(symbol: String, summary: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 16)
            Text(summary)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 6)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, minHeight: 36)
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
        applyAppearance()
    }

    private func applyAppearance() {
        window?.appearance = NSAppearance(
            named: NSAppearance.Name(rawValue: appearanceName)
        )
    }
}
