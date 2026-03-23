# TravelAssist (SwiftUI) Blueprint
<img width="360" height="760" alt="Simulator Screenshot - iPhone 17 Pro - 2026-03-22 at 18 45 30" src="https://github.com/user-attachments/assets/b23c2578-2196-4416-bab1-9bb68cf3efb5" />
<img width="360" height="760" alt="Simulator Screenshot - iPhone 17 Pro - 2026-03-22 at 18 46 08" src="https://github.com/user-attachments/assets/67c16c82-4a2c-4ff4-b97b-5b20d80e0f31" />
<img width="360" height="760" alt="Simulator Screenshot - iPhone 17 Pro - 2026-03-22 at 18 46 19" src="https://github.com/user-attachments/assets/0fee76a1-540a-4bbf-82f3-a12e217bc888" />
<img width="360" height="760" alt="Simulator Screenshot - iPhone 17 Pro - 2026-03-22 at 18 46 30" src="https://github.com/user-attachments/assets/ced847dd-d0f5-4b43-90b8-6b36bb3a4b5c" />
<img width="360" height="760" alt="Simulator Screenshot - iPhone 17 Pro - 2026-03-22 at 18 46 59" src="https://github.com/user-attachments/assets/606359a4-8ce0-4e6d-9320-f5e1a1bacffc" />
<img width="360" height="760" alt="Simulator Screenshot - iPhone 17 Pro - 2026-03-22 at 18 44 34" src="https://github.com/user-attachments/assets/76babf6b-4f71-4334-bb26-9494edc6613b" />

This is a production-oriented starter architecture for your app idea:

- User sets destination + lead time (5/10/20/30/custom minutes)
- App tracks live location in foreground/background
- ETA is recalculated from location updates
- ETA is also recalculated on a 60-second interval while active
- When ETA is below lead time, app triggers a fake-call style alert
- Latest travel state is synced to shared storage for lock-screen widgets

## Architecture

- `Presentation` (SwiftUI Views + ViewModels)
- `Domain` (Entities + UseCases + Repository contracts)
- `Data` (Repository implementation + services)
- `App` (DI container + app delegate bootstrap)

Design follows MVVM + SOLID + Clean Architecture:
- ViewModels depend on UseCases, not concrete services
- Domain defines protocol boundaries
- Data layer implements domain contracts
- Cross-cutting concerns are injected

## Important iOS Reality

- iOS does **not** allow guaranteed arbitrary interval execution when fully terminated.
- Reliable triggers in background/terminated-by-system:
  - Significant location changes
  - Region monitoring (geofence)
  - Background app refresh (best effort, not exact timing)
- If user force-quits the app from app switcher, background relaunch is generally blocked.

Because of this, implementation combines:
- `startUpdatingLocation` (active session)
- `startMonitoringSignificantLocationChanges`
- destination geofence monitoring
- `BGAppRefreshTask` scheduling for opportunistic refresh

## Xcode Setup Checklist

1. Generate project (recommended):
   - Install [XcodeGen](https://github.com/yonaskolb/XcodeGen)
   - Run `cd TravelAssistBlueprint && xcodegen generate`
   - Open `TravelAssist.xcodeproj`
2. If you create targets manually in Xcode, copy files into app/widget targets.
3. Add capabilities:
   - Background Modes:
     - Location updates
     - Background fetch
   - App Groups (for widget sharing), e.g. `group.com.yourcompany.travelassist`
4. Add Info.plist keys:
   - `NSLocationWhenInUseUsageDescription`
   - `NSLocationAlwaysAndWhenInUseUsageDescription`
   - `UIBackgroundModes` includes `location`, `fetch`
   - `BGTaskSchedulerPermittedIdentifiers` includes `com.yourcompany.travelassist.refresh`
5. Add notification permission request flow (already scaffolded).
6. Add a custom sound file if you want ringtone-like alerts.

## App Store Policy Note

If you use actual CallKit incoming-call UI for non-VoIP fake calls, review risk is high.
This scaffold uses local notifications + in-app call-like UI model to stay safer.
