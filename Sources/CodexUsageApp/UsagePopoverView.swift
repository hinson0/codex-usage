import AppKit
import CodexUsageCore
import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var controller: UsageController
    @State private var showsResetConfirmation = false

    private var presentation: MenuPresentation {
        MenuPresentation(
            snapshot: controller.snapshot,
            lastReset: controller.lastReset,
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
        .frame(width: 432)
        .preferredColorScheme(controller.appearance.colorScheme)
        .onAppear {
            applyAppearance()
            Task { await controller.refresh() }
        }
        .onChange(of: controller.appearance) { _ in
            applyAppearance()
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
        VStack(alignment: .leading, spacing: 14) {
            if let remaining = presentation.remainingPercent {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(presentation.text(.codexRemaining))
                        .font(.system(size: 20, weight: .semibold))
                    Spacer(minLength: 16)
                    Text("\(remaining)%")
                        .font(.system(size: 26, weight: .bold))
                        .monospacedDigit()
                }

                ProgressView(value: Double(remaining), total: 100)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .scaleEffect(x: 1, y: 1.65, anchor: .center)
                    .padding(.vertical, 2)

                if let nextReset = presentation.nextResetText {
                    Text(nextReset)
                        .font(.system(size: 14))
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
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private var resetSection: some View {
        if presentation.isResetEnabled || controller.isRedeeming {
            VStack(alignment: .leading, spacing: 12) {
                if let count = presentation.availableResetsText {
                    Text(count)
                        .font(.system(size: 17, weight: .semibold))
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

                Text(presentation.lastResetText)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
        } else {
            VStack(spacing: 10) {
                Text(presentation.resetActionTitle)
                    .font(.system(size: 17, weight: .semibold))
                Text(presentation.lastResetText)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 34)
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
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
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
                    symbol: "rectangle.portrait.and.arrow.right"
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
                .font(.body)
                .frame(width: 18)
            Text(summary)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 6)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, minHeight: 40)
        .padding(.horizontal, 10)
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

    private func actionRow(title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 16))
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
    }

    private func applyAppearance() {
        guard let rawName = controller.appearance.nativeAppearanceName else {
            NSApplication.shared.appearance = nil
            return
        }
        NSApplication.shared.appearance = NSAppearance(
            named: NSAppearance.Name(rawValue: rawName)
        )
    }
}

private extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
