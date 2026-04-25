import SwiftUI

struct AppRootView: View {
    let tripSetupViewModel: TripSetupViewModel
    let monitoringViewModelBuilder: () -> MonitoringViewModel
    let splashViewModel: TravelSplashViewModel

    @State private var showsSplash: Bool = true
    @State private var startedTimeout: Bool = false
    @State private var jailbreakDetected: Bool = JailbreakDetector.isJailbroken()

    var body: some View {
        ZStack {
            if showsSplash {
                TravelSplashView(viewModel: splashViewModel)
                    .transition(.opacity)
            } else {
                TripSetupView(
                    viewModel: tripSetupViewModel,
                    monitoringViewModelBuilder: monitoringViewModelBuilder
                )
                .transition(.opacity)
            }

            if jailbreakDetected {
                JailbreakBlockedView()
                    .transition(.opacity)
            }
        }
        .task {
            jailbreakDetected = JailbreakDetector.isJailbroken()
        }
        .onChange(of: splashViewModel.isReadyToProceed) { _, ready in
            guard showsSplash, ready else { return }
            transitionToHome()
        }
        .task {
            guard showsSplash else { return }
            guard !startedTimeout else { return }
            startedTimeout = true

            // Safety timeout: don't block the app forever if WeatherKit / network is unavailable.
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard showsSplash else { return }
            transitionToHome()
        }
    }

    private func transitionToHome() {
        withAnimation(.easeOut(duration: 0.35)) {
            showsSplash = false
        }
    }
}

private struct JailbreakBlockedView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Security Check Failed")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("This device appears to be jailbroken. For your safety, Travel Assist won't run on modified devices.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 28)
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 18)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 24)
        }
        .accessibilityAddTraits(.isModal)
    }
}
