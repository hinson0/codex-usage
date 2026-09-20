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
            errorMessage: controller.errorMessage,
            appearance: controller.appearance,
            language: controller.language
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            usageSection
            Divider()
            resetSection
            Divider()
            settingsSection
        }
        .frame(width: 340)
        .preferredColorScheme(controller.appearance.colorScheme)
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
        VStack(alignment: .leading, spacing: 10) {
            if let remaining = presentation.remainingPercent {
                HStack(alignment: .firstTextBaseline) {
                    Text(presentation.text(.codexRemaining))
                        .font(.headline)
                    Spacer()
                    Text("\(remaining)%")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                }
                ProgressView(value: Double(remaining), total: 100)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                if let nextReset = presentation.nextResetText {
                    Text(nextReset)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(presentation.text(.loading))
                        .foregroundStyle(.secondary)
                }
            }

            if let snapshot = controller.snapshot, !snapshot.additionalBuckets.isEmpty {
                Text(presentation.text(.additionalLimits))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(snapshot.additionalBuckets, id: \.limitId) { bucket in
                    HStack {
                        Text(bucket.limitName ?? bucket.limitId)
                            .lineLimit(1)
                        Spacer()
                        Text(bucketRemaining(bucket))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }

            if let error = presentation.errorText {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if let refreshed = presentation.lastRefreshText {
                Text(refreshed)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
    }

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let count = presentation.availableResetsText {
                Text(count)
                    .font(.subheadline.weight(.medium))
            }

            if presentation.isResetEnabled {
                Button {
                    showsResetConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Text(presentation.resetActionTitle)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                HStack(spacing: 8) {
                    if controller.isRedeeming {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(presentation.resetActionTitle)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Text(presentation.lastResetText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private var settingsSection: some View {
        VStack(spacing: 0) {
            Menu {
                ForEach(presentation.appearanceOptions, id: \.value) { option in
                    Button {
                        controller.setAppearance(option.value)
                    } label: {
                        if option.isSelected {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                settingsRow(
                    title: presentation.text(.appearance),
                    value: selectedAppearanceTitle,
                    symbol: "circle.lefthalf.filled"
                )
            }
            .menuStyle(.borderlessButton)

            Menu {
                ForEach(presentation.languageOptions, id: \.value) { option in
                    Button {
                        controller.setLanguage(option.value)
                    } label: {
                        if option.isSelected {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                settingsRow(
                    title: presentation.text(.language),
                    value: selectedLanguageTitle,
                    symbol: "globe"
                )
            }
            .menuStyle(.borderlessButton)

            Divider()
                .padding(.vertical, 4)

            Button {
                Task { await controller.refresh() }
            } label: {
                settingsRow(
                    title: presentation.text(.refreshNow),
                    value: nil,
                    symbol: "arrow.clockwise"
                )
            }
            .buttonStyle(.plain)
            .disabled(controller.isRefreshing || controller.isRedeeming)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                settingsRow(
                    title: presentation.text(.quit),
                    value: nil,
                    symbol: "rectangle.portrait.and.arrow.right"
                )
            }
            .buttonStyle(.plain)
        }
        .padding(8)
    }

    private var selectedAppearanceTitle: String? {
        presentation.appearanceOptions.first(where: \.isSelected)?.title
    }

    private var selectedLanguageTitle: String? {
        presentation.languageOptions.first(where: \.isSelected)?.title
    }

    private func settingsRow(title: String, value: String?, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer()
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    private func bucketRemaining(_ bucket: RateLimitBucket) -> String {
        guard let remaining = UsageFormatting.remainingPercent(
            usedPercent: bucket.primary?.usedPercent
        ) else { return "--%" }
        return "\(remaining)%"
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
