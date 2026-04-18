import SwiftUI

@main
@MainActor
struct TravelAssistApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: AppContainer
    private let tripSetupViewModel: TripSetupViewModel
    private let splashViewModel: TravelSplashViewModel

    init() {
        let container = AppContainer()
        self.container = container
        self.tripSetupViewModel = container.makeTripSetupViewModel()
        self.splashViewModel = container.makeSplashViewModel()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(
                tripSetupViewModel: tripSetupViewModel,
                monitoringViewModelBuilder: container.makeMonitoringViewModel,
                splashViewModel: splashViewModel
            )
            .onAppear {
                container.registerBackgroundTasks()
            }
        }
    }
}
