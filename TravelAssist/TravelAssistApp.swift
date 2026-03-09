import SwiftUI

@main
struct TravelAssistApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container = AppContainer()

    var body: some Scene {
        WindowGroup {
            TripSetupView(
                viewModel: container.makeTripSetupViewModel(),
                monitoringViewModelBuilder: container.makeMonitoringViewModel
            )
            .onAppear {
                container.registerBackgroundTasks()
            }
        }
    }
}

