import AppKit
import SwiftUI

struct OnboardingView: View {
    private let accessibility = AccessibilityManager.shared
    @ObservedObject private var preferences = PreferencesStore.shared

    var body: some View {
        VStack(spacing: 20) {
            Text("How to Use Sniq")
                .font(.title2)
                .fontWeight(.semibold)

            GroupBox("How to use") {
                VStack(alignment: .leading, spacing: 10) {
                    HowToRow(
                        icon: "arrow.up.and.down.and.arrow.left.and.right",
                        text: "Hold Grip (\(preferences.bindings.grip.formatted)) and drag anywhere on a window"
                    )
                    HowToRow(
                        icon: "grid",
                        text: "A grid overlay appears on screen"
                    )
                    HowToRow(
                        icon: "rectangle.2.swap",
                        text: "Add Flip (\(preferences.bindings.flip.formatted)) to switch to the Secondary layout"
                    )
                    HowToRow(
                        icon: "arrow.up.left.and.arrow.down.right",
                        text: "Add Stretch (\(preferences.bindings.stretch.formatted)) to select a multi-cell region"
                    )
                    HowToRow(
                        icon: "arrow.down.to.line",
                        text: "Release to snap the window to the highlighted cell"
                    )
                    HowToRow(
                        icon: "escape",
                        text: "Release Grip to cancel"
                    )
                }
                .padding(.vertical, 4)
            }

            OnboardingProgressView(steps: [
                .init(title: "Accessibility", completed: accessibility.isTrusted),
                .init(title: "Input Monitoring", completed: accessibility.canListenEvents)
            ])
            .padding(.horizontal, 12)

            VStack(spacing: 10) {
                PermissionCardView(
                    icon: "accessibility",
                    title: "Accessibility",
                    description: "Required to move and resize windows",
                    granted: accessibility.isTrusted,
                    primaryAction: { accessibility.requestPermission() },
                    fallbackAction: { accessibility.openAccessibilitySettings() }
                )
                PermissionCardView(
                    icon: "keyboard",
                    title: "Input Monitoring",
                    description: "Required to detect the Grip-drag gesture",
                    granted: accessibility.canListenEvents,
                    primaryAction: { accessibility.openInputMonitoringSettings() },
                    fallbackAction: nil
                )
            }

            if preferences.onboardingCompleted {
                Button("Close") { completeOnboarding() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Get Started") { completeOnboarding() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!accessibility.allPermissionsGranted)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            accessibility.checkPermission()
            accessibility.startPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibility.checkPermission()
        }
    }

    private func completeOnboarding() {
        preferences.onboardingCompleted = true
        NSApp.keyWindow?.close()
    }
}
