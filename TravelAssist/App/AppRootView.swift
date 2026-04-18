import SwiftUI

struct AppRootView: View {
    let tripSetupViewModel: TripSetupViewModel
    let monitoringViewModelBuilder: () -> MonitoringViewModel
    let splashViewModel: TravelSplashViewModel

    @State private var showsSplash: Bool = true
    @State private var startedTimeout: Bool = false

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
