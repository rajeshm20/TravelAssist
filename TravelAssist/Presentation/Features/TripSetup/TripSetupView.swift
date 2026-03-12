import SwiftUI
import MapKit
import Combine
import AVFoundation
import AudioToolbox

struct TripSetupView: View {
    @ObservedObject var viewModel: TripSetupViewModel
    @StateObject private var monitoringViewModel: MonitoringViewModel
    @StateObject private var fakeCallSpeaker = FakeCallSpeaker()
    @StateObject private var fakeCallFeedback = FakeIncomingCallFeedback()
    @State private var isDestinationPickerPresented = false
    @State private var isHistoryPresented = false
    @State private var isLeadTimePickerExpanded = false
    @State private var isRoutePreviewExpanded = false
    @State private var isFakeCallPresented = false
    @State private var isFakeCallSpeaking = false
    @State private var activeFakeCallCallerName = "Travel Assist"
    @State private var activeFakeCallMessage = AppConstants.fakeCallNotificationMessage
    @StateObject private var routePreviewViewModel = RoutePreviewViewModel()

    init(
        viewModel: TripSetupViewModel,
        monitoringViewModelBuilder: @escaping () -> MonitoringViewModel
    ) {
        self.viewModel = viewModel
        _monitoringViewModel = StateObject(wrappedValue: monitoringViewModelBuilder())
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color(red: 0.93, green: 0.94, blue: 0.97),
                        Color(red: 0.90, green: 0.91, blue: 0.95)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Home")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.black.opacity(0.82))

                            Spacer()

                            Text(Self.headerDateFormatter.string(from: Date()))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hi Traveler,")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(greetingTitle)
                                .font(.title2.weight(.bold))
                                .fontDesign(.rounded)
                                .foregroundStyle(.black.opacity(0.9))
                        }

                        ZStack(alignment: .trailing) {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.99, green: 0.43, blue: 0.23), Color(red: 0.99, green: 0.57, blue: 0.21)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Trip Monitoring")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.85))

                                Text(monitoringViewModel.isMonitoring ? monitoringViewModel.statusText : "No active trip session")
                                    .font(.title3.weight(.bold))
                                    .fontDesign(.rounded)
                                    .foregroundStyle(.white)
                                    .lineLimit(2)

                                HStack(spacing: 8) {
                                    metricPill(
                                        title: "Distance",
                                        value: monitoringViewModel.isMonitoring ? monitoringViewModel.distanceText : "--",
                                        icon: "location.fill"
                                    )
                                    metricPill(
                                        title: "ETA",
                                        value: monitoringViewModel.isMonitoring ? monitoringViewModel.etaText : "--",
                                        icon: "clock.fill"
                                    )
                                }

                                if monitoringViewModel.isLoadingInitialSnapshot {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .tint(.white)
                                        Text("Getting live updates...")
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.85))
                                    }
                                }

                                Button(monitoringViewModel.isMonitoring ? monitoringViewModel.stopButtonTitle : "Start Monitoring") {
                                    if monitoringViewModel.isMonitoring {
                                        monitoringViewModel.stopMonitoring()
                                    } else {
                                        viewModel.startMonitoring()
                                    }
                                }
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.95), in: Capsule())
                                .foregroundStyle(statusAccentColor)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: monitoringViewModel.selectedJourneyModeSymbol)
                                .font(.system(size: 74, weight: .medium))
                                .foregroundStyle(.white.opacity(0.28))
                                .padding(.trailing, 14)
                        }
                        .frame(minHeight: 180)

                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }

                        softCard {
                            HStack {
                                Label("Destination", systemImage: "mappin.and.ellipse")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.black.opacity(0.85))
                                Spacer()
                                Button("Pick") {
                                    isDestinationPickerPresented = true
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color(red: 0.91, green: 0.93, blue: 0.98), in: Capsule())
                            }

                            if let selectedDestinationName = viewModel.selectedDestinationName {
                                Text(selectedDestinationName)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.black.opacity(0.82))
                                    .lineLimit(2)
                            } else {
                                Text("Select destination from Apple Maps")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            if let latitude = Double(viewModel.destinationLatitudeText),
                               let longitude = Double(viewModel.destinationLongitudeText) {
                                Text(String(format: "%.5f, %.5f", latitude, longitude))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        softCard {
                            HStack {
                                Label("Trip Details", systemImage: "list.bullet.rectangle.portrait")
                                    .font(.headline.weight(.semibold))
                                Spacer()
                                if monitoringViewModel.isMonitoring {
                                    Text("Live")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.18), in: Capsule())
                                        .foregroundStyle(Color.green.opacity(0.9))
                                }
                            }

                            detailRow(title: "Distance", value: monitoringViewModel.isMonitoring ? monitoringViewModel.distanceText : "--")
                            detailRow(title: "ETA (Hour/Min)", value: monitoringViewModel.isMonitoring ? monitoringViewModel.etaText : "--")
                            detailRow(title: "Status", value: monitoringViewModel.statusText)
                            detailIconRow(
                                title: "Journey",
                                symbol: monitoringViewModel.selectedJourneyModeSymbol,
                                value: monitoringViewModel.selectedJourneyModeText
                            )
                            detailIconRow(
                                title: "Detected",
                                symbol: monitoringViewModel.detectedModeSymbol,
                                value: monitoringViewModel.detectedModeText
                            )
                        }

                        HStack(spacing: 12) {
                            softCard {
                                Label("Journey Mode", systemImage: viewModel.selectedJourneyMode.symbolName)
                                    .font(.headline.weight(.semibold))
                                Text(viewModel.selectedJourneyMode.title)
                                    .font(.title3.weight(.bold))
                                    .fontDesign(.rounded)
                                Picker("Mode", selection: $viewModel.selectedJourneyMode) {
                                    ForEach(JourneyMode.allCases) { mode in
                                        Label(mode.title, systemImage: mode.symbolName).tag(mode)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                            .frame(maxWidth: .infinity)

                            softCard {
                                Label("Lead Time", systemImage: "clock.badge.checkmark")
                                    .font(.headline.weight(.semibold))
                                Text(viewModel.leadTimeFormatted)
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                Button("Change HH:mm") {
                                    isLeadTimePickerExpanded = true
                                }
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color(red: 0.94, green: 0.95, blue: 1.0), in: Capsule())
                            }
                            .frame(maxWidth: .infinity)
                        }

                        softCard {
                            HStack {
                                Label("Route Preview", systemImage: "map.fill")
                                    .font(.headline.weight(.semibold))
                            }

                            RoutePreviewMapView(
                                viewModel: routePreviewViewModel,
                                isMonitoringActive: monitoringViewModel.isMonitoring,
                                onExpand: {
                                    isRoutePreviewExpanded = true
                                },
                                shouldFollowUserWhenMoving: false
                            )
                            .frame(height: 185)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .onAppear {
                                syncRoutePreviewDestination()
                            }
                            .onChange(of: viewModel.destinationLatitudeText) { _, _ in
                                syncRoutePreviewDestination()
                            }
                            .onChange(of: viewModel.destinationLongitudeText) { _, _ in
                                syncRoutePreviewDestination()
                            }
                            .onChange(of: monitoringViewModel.activeSession?.id) { _, _ in
                                syncRoutePreviewDestination()
                            }

                            if let routeStatusMessage = routePreviewViewModel.routeStatusMessage {
                                Text(routeStatusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }

                        softCard {
                            HStack {
                                Label("Session History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                    .font(.headline.weight(.semibold))
                                Spacer()
                                Text("\(monitoringViewModel.historySessions.count)")
                                    .font(.title2.weight(.bold))
                                    .fontDesign(.rounded)
                            }

                            if let latest = monitoringViewModel.historySessions.first {
                                Text("Latest session: \(Self.historyDateTimeFormatter.string(from: latest.startedAt))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("No monitoring history yet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Button("Open History") {
                                isHistoryPresented = true
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.91, green: 0.93, blue: 0.98), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                viewModel.onAppear()
                routePreviewViewModel.onAppear()
            }
            .onDisappear {
                routePreviewViewModel.onDisappear()
            }
            .onChange(of: viewModel.selectedJourneyMode) { _, _ in
                viewModel.applySelectedJourneyModeToActiveSession()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fakeCallPresentationRequested)) { notification in
                guard let request = FakeCallPresentationRequest.from(userInfo: notification.userInfo) else {
                    return
                }
                presentIncomingFakeCall(
                    callerName: request.callerName,
                    message: request.message
                )
            }
            .sheet(isPresented: $isDestinationPickerPresented) {
                DestinationSearchSheet { name, coordinate in
                    viewModel.applyDestinationFromAppleMaps(name: name, coordinate: coordinate)
                }
            }
            .sheet(isPresented: $isHistoryPresented) {
                MonitoringHistoryBottomSheet(sessions: monitoringViewModel.historySessions)
                    .presentationDetents([.fraction(0.25), .medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isLeadTimePickerExpanded) {
                LeadTimePickerSheet(viewModel: viewModel)
            }
            .fullScreenCover(isPresented: $isFakeCallPresented) {
                FakeIncomingCallView(
                    callerName: activeFakeCallCallerName,
                    isSpeakingPrompt: isFakeCallSpeaking,
                    onDecline: {
                        fakeCallFeedback.stop()
                        fakeCallSpeaker.stop()
                        isFakeCallSpeaking = false
                        isFakeCallPresented = false
                    },
                    onAccept: {
                        guard !isFakeCallSpeaking else { return }
                        fakeCallFeedback.stop()
                        isFakeCallSpeaking = true
                        fakeCallSpeaker.speak(activeFakeCallMessage) {
                            isFakeCallSpeaking = false
                            isFakeCallPresented = false
                        }
                    }
                )
                .interactiveDismissDisabled(true)
                .onAppear {
                    fakeCallFeedback.start()
                }
                .onChange(of: isFakeCallSpeaking) { _, isSpeaking in
                    if isSpeaking {
                        fakeCallFeedback.stop()
                    } else {
                        fakeCallFeedback.start()
                    }
                }
                .onDisappear {
                    fakeCallFeedback.stop()
                }
            }
            .fullScreenCover(isPresented: $isRoutePreviewExpanded) {
                RoutePreviewFullscreenView(
                    viewModel: routePreviewViewModel,
                    monitoringViewModel: monitoringViewModel
                )
            }
        }
    }

    private var statusAccentColor: Color {
        monitoringViewModel.isMonitoring ? Color(red: 0.90, green: 0.20, blue: 0.30) : Color(red: 0.19, green: 0.45, blue: 0.93)
    }

    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return (6..<20).contains(hour) ? "Stay On Route" : "Sleep Well"
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title).fontWeight(.semibold)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    @ViewBuilder
    private func detailIconRow(title: String, symbol: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title).fontWeight(.semibold)
            Spacer()
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    @ViewBuilder
    private func softCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
    }

    @ViewBuilder
    private func metricPill(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.78))
                Text(value)
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.18), in: Capsule())
    }

    private func syncRoutePreviewDestination() {
        if let sessionDestination = monitoringViewModel.activeSession?.destinationCoordinate {
            routePreviewViewModel.updateDestination(coordinate: sessionDestination)
            return
        }

        routePreviewViewModel.updateDestination(
            latitudeText: viewModel.destinationLatitudeText,
            longitudeText: viewModel.destinationLongitudeText
        )
    }

    private func presentIncomingFakeCall(callerName: String, message: String) {
        guard !isFakeCallPresented else { return }
        activeFakeCallCallerName = callerName
        activeFakeCallMessage = message
        isFakeCallSpeaking = false
        isFakeCallPresented = true
    }

    private static let historyDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let headerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d"
        return formatter
    }()
}

@MainActor
private final class FakeCallSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        self.completion = completion
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.48
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    func stop() {
        completion = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let finished = completion
        completion = nil
        finished?()
    }
}

private struct FakeIncomingCallView: View {
    let callerName: String
    let isSpeakingPrompt: Bool
    let onDecline: () -> Void
    let onAccept: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.10, green: 0.12, blue: 0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer(minLength: 40)

                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.white.opacity(0.92))

                Text(callerName)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(isSpeakingPrompt ? "Connected..." : "\(callerName) calling...")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))

                if isSpeakingPrompt {
                    ProgressView("Playing voice prompt...")
                        .foregroundStyle(.white.opacity(0.9))
                        .tint(.white)
                        .padding(.top, 8)
                }

                Spacer()

                HStack(spacing: 44) {
                    Button(action: onDecline) {
                        VStack(spacing: 8) {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 74, height: 74)
                                .background(Color.red, in: Circle())
                            Text("Decline")
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    .buttonStyle(.plain)

                    Button(action: onAccept) {
                        VStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 74, height: 74)
                                .background(Color.green, in: Circle())
                            Text("Accept")
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isSpeakingPrompt)
                }
                .padding(.bottom, 38)
            }
            .padding(.horizontal, 24)
        }
    }
}

@MainActor
private final class FakeIncomingCallFeedback: ObservableObject {
    private var ringTimer: Timer?
    private var vibrationTimer: Timer?
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true

        playRingtoneBurst()
        vibrate()

        ringTimer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: true) { [weak self] _ in
            self?.playRingtoneBurst()
        }
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    func stop() {
        isRunning = false
        ringTimer?.invalidate()
        vibrationTimer?.invalidate()
        ringTimer = nil
        vibrationTimer = nil
    }

    private func playRingtoneBurst() {
        // Lightweight ringtone-like tone sequence while fake call is incoming.
        AudioServicesPlaySystemSound(1003)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            AudioServicesPlaySystemSound(1003)
        }
    }

    private func vibrate() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
}

private struct DestinationSearchSheet: View {
    let onSelect: (String, CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = DestinationSearchViewModel()
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.recentDestinations.isEmpty {
                    Section {
                        ForEach(viewModel.recentDestinations) { destination in
                            Button {
                                let coordinate = CLLocationCoordinate2D(
                                    latitude: destination.latitude,
                                    longitude: destination.longitude
                                )
                                onSelect(destination.title, coordinate)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(destination.title)
                                        .font(.body)
                                    if let subtitle = destination.subtitle, !subtitle.isEmpty {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text("Recent")
                            Spacer()
                            Button("Clear") {
                                viewModel.clearRecentDestinations()
                            }
                            .font(.caption)
                        }
                    }
                }

                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Search for a place or address")
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(viewModel.results.enumerated()), id: \.offset) { _, completion in
                    Button {
                        Task {
                            if let item = await viewModel.resolve(completion) {
                                let name = item.name ?? completion.title
                                viewModel.saveRecentDestination(
                                    title: name,
                                    subtitle: completion.subtitle,
                                    coordinate: item.placemark.coordinate
                                )
                                onSelect(name, item.placemark.coordinate)
                                dismiss()
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(completion.title)
                                .font(.body)
                            if !completion.subtitle.isEmpty {
                                Text(completion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Fetching location...")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .searchable(text: $query, prompt: "Search Apple Maps")
            .onChange(of: query) { value in
                viewModel.updateQuery(value)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .navigationTitle("Destination")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(.background)
                }
            }
        }
    }
}

private struct LeadTimePickerSheet: View {
    @ObservedObject var viewModel: TripSetupViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                DatePicker(
                    "Lead Time",
                    selection: Binding(
                        get: { viewModel.leadTimePickerDate },
                        set: { viewModel.updateLeadTime(from: $0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .environment(\.locale, Locale(identifier: "en_GB"))
                .labelsHidden()

                Text("Selected: \(viewModel.leadTimeFormatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Lead Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.35), .medium])
        .presentationDragIndicator(.visible)
    }
}

private struct MonitoringHistoryBottomSheet: View {
    let sessions: [TripHistorySession]
    @State private var expandedSessions = Set<UUID>()

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    Text("No monitoring history yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions) { session in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedSessions.contains(session.id) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedSessions.insert(session.id)
                                    } else {
                                        expandedSessions.remove(session.id)
                                    }
                                }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                historyRow(title: "Started", value: Self.dateTimeFormatter.string(from: session.startedAt))
                                historyRow(title: "Ended", value: Self.dateTimeFormatter.string(from: session.endedAt))
                                historyRow(title: "Duration", value: Self.durationText(session.duration))
                                historyRow(title: "Route points", value: "\(session.pointsCount)")
                                historyRow(
                                    title: "Destination",
                                    value: String(format: "%.5f, %.5f", session.destinationLatitude, session.destinationLongitude)
                                )
                                historyRow(title: "Status", value: session.completionStatus.title)
                                iconHistoryRow(
                                    title: "Selected mode",
                                    symbol: session.selectedJourneyMode.symbolName,
                                    value: session.selectedJourneyMode.title
                                )
                                iconHistoryRow(
                                    title: "Detected mode",
                                    symbol: session.finalDetectedActivity.symbolName,
                                    value: session.finalDetectedActivity.title
                                )
                                if !session.activityEvents.isEmpty {
                                    DisclosureGroup("Activity Flow (\(session.activityEvents.count) events)") {
                                        ActivityFlowTimelineView(events: session.activityEvents)
                                            .padding(.top, 4)
                                    }
                                }
                                if !session.gpxFilePath.isEmpty {
                                    historyRow(title: "GPX file", value: session.gpxFilePath)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Self.dateTimeFormatter.string(from: session.startedAt))
                                    .font(.subheadline.weight(.semibold))
                                Text(session.gpxFileName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Session History")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func historyRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .fontWeight(.semibold)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func iconHistoryRow(title: String, symbol: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .fontWeight(.semibold)
            Spacer(minLength: 12)
            Image(systemName: symbol)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}

private struct ActivityFlowTimelineView: View {
    let events: [TripActivityEvent]

    private var sortedEvents: [TripActivityEvent] {
        events.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sortedEvents.enumerated()), id: \.element.id) { index, event in
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 9, height: 9)

                        if index < sortedEvents.count - 1 {
                            Rectangle()
                                .fill(Color.orange.opacity(0.45))
                                .frame(width: 2, height: 34)
                                .padding(.top, 2)
                        }
                    }
                    .frame(width: 12)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.status)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(Self.eventTimeFormatter.string(from: event.timestamp))
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let lat = event.latitude, let lon = event.longitude {
                            Text(String(format: "%.5f, %.5f", lat, lon))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Location unavailable")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.bottom, index < sortedEvents.count - 1 ? 2 : 0)
            }
        }
    }

    private static let eventTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

private final class DestinationSearchViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var recentDestinations: [RecentDestination] = []

    private let completer = MKLocalSearchCompleter()
    private let defaults = UserDefaults.standard
    private let recentDestinationsKey = "tripsetup.recent.destinations"
    private let maxRecentCount = 8

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        loadRecentDestinations()
    }

    func updateQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            results = []
            errorMessage = nil
            return
        }
        completer.queryFragment = trimmed
    }

    @MainActor
    func resolve(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let request = MKLocalSearch.Request(completion: completion)
            let response = try await MKLocalSearch(request: request).start()
            guard let mapItem = response.mapItems.first else {
                errorMessage = "Could not resolve this place. Try another result."
                return nil
            }
            return mapItem
        } catch {
            errorMessage = "Unable to fetch location from Apple Maps."
            return nil
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async { [weak self] in
            self?.results = completer.results
            self?.errorMessage = nil
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.results = []
            self?.errorMessage = "Search failed. Check network and try again."
        }
    }

    func saveRecentDestination(title: String, subtitle: String?, coordinate: CLLocationCoordinate2D) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let newDestination = RecentDestination(
            title: trimmedTitle,
            subtitle: subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        var updated = recentDestinations.filter { existing in
            let isSamePlace = abs(existing.latitude - newDestination.latitude) < 0.00001 &&
                abs(existing.longitude - newDestination.longitude) < 0.00001
            return !isSamePlace
        }
        updated.insert(newDestination, at: 0)
        if updated.count > maxRecentCount {
            updated = Array(updated.prefix(maxRecentCount))
        }
        recentDestinations = updated
        persistRecentDestinations(updated)
    }

    func clearRecentDestinations() {
        recentDestinations = []
        defaults.removeObject(forKey: recentDestinationsKey)
    }

    private func loadRecentDestinations() {
        guard let data = defaults.data(forKey: recentDestinationsKey),
              let decoded = try? JSONDecoder().decode([RecentDestination].self, from: data) else {
            recentDestinations = []
            return
        }
        recentDestinations = decoded
    }

    private func persistRecentDestinations(_ destinations: [RecentDestination]) {
        guard let data = try? JSONEncoder().encode(destinations) else { return }
        defaults.set(data, forKey: recentDestinationsKey)
    }
}

private struct RecentDestination: Codable, Identifiable {
    let id: UUID
    let title: String
    let subtitle: String?
    let latitude: Double
    let longitude: Double

    init(id: UUID = UUID(), title: String, subtitle: String?, latitude: Double, longitude: Double) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
    }
}

private struct RoutePreviewMapView: View {
    @ObservedObject var viewModel: RoutePreviewViewModel
    let isMonitoringActive: Bool
    let onExpand: (() -> Void)?
    let shouldFollowUserWhenMoving: Bool

    var body: some View {
        ZStack {
            RoutePreviewUIKitMap(
                currentCoordinate: viewModel.currentCoordinate,
                destinationCoordinate: viewModel.destinationCoordinate,
                routePolyline: viewModel.route?.polyline,
                shouldFollowUserWhenMoving: shouldFollowUserWhenMoving
            )

            if let onExpand {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onExpand) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(10)
            }

            if viewModel.isLoadingRoute {
                ProgressView("Loading route...")
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            } else if viewModel.destinationCoordinate == nil && !isMonitoringActive {
                Text("Select destination to preview route")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

private struct RoutePreviewFullscreenView: View {
    @ObservedObject var viewModel: RoutePreviewViewModel
    @ObservedObject var monitoringViewModel: MonitoringViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            RoutePreviewMapView(
                viewModel: viewModel,
                isMonitoringActive: monitoringViewModel.isMonitoring,
                onExpand: nil,
                shouldFollowUserWhenMoving: monitoringViewModel.isMonitoring
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                monitoringDetailsCard
                    .padding(.horizontal, 16)

                Spacer()
            }
        }
    }

    private var monitoringDetailsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trip Monitoring")
                .font(.headline)
                .foregroundStyle(.white)

            if monitoringViewModel.isMonitoring {
                detailRow(title: "Distance", value: monitoringViewModel.distanceText)
                detailRow(title: "ETA", value: monitoringViewModel.etaText)
                detailRow(title: "Status", value: monitoringViewModel.statusText)
                iconDetailRow(
                    title: "Journey",
                    symbol: monitoringViewModel.selectedJourneyModeSymbol,
                    value: monitoringViewModel.selectedJourneyModeText
                )
                iconDetailRow(
                    title: "Detected",
                    symbol: monitoringViewModel.detectedModeSymbol,
                    value: monitoringViewModel.detectedModeText
                )

                if monitoringViewModel.isLoadingInitialSnapshot {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Getting live updates...")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                        Spacer()
                    }
                }
            } else {
                Text("No active trip session")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                if let message = viewModel.routeStatusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.darkGray).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
            Spacer(minLength: 10)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func iconDetailRow(title: String, symbol: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .fontWeight(.semibold)
            Spacer(minLength: 10)
            Image(systemName: symbol)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .foregroundStyle(.white)
    }
}

private struct RoutePreviewUIKitMap: UIViewRepresentable {
    let currentCoordinate: CLLocationCoordinate2D?
    let destinationCoordinate: CLLocationCoordinate2D?
    let routePolyline: MKPolyline?
    let shouldFollowUserWhenMoving: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.isRotateEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.pointOfInterestFilter = .includingAll
        if #available(iOS 16.0, *) {
            mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic)
        }
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.update(
            mapView: mapView,
            currentCoordinate: currentCoordinate,
            destinationCoordinate: destinationCoordinate,
            routePolyline: routePolyline,
            shouldFollowUserWhenMoving: shouldFollowUserWhenMoving
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var lastFollowLocation: CLLocation?

        func update(
            mapView: MKMapView,
            currentCoordinate: CLLocationCoordinate2D?,
            destinationCoordinate: CLLocationCoordinate2D?,
            routePolyline: MKPolyline?,
            shouldFollowUserWhenMoving: Bool
        ) {
            mapView.removeAnnotations(mapView.annotations)
            mapView.removeOverlays(mapView.overlays)

            var mapRectToFit: MKMapRect?
            func mergeIntoVisibleRect(_ newRect: MKMapRect) {
                if let existingRect = mapRectToFit {
                    mapRectToFit = existingRect.union(newRect)
                } else {
                    mapRectToFit = newRect
                }
            }

            if let currentCoordinate {
                let annotation = MKPointAnnotation()
                annotation.coordinate = currentCoordinate
                annotation.title = "Current"
                mapView.addAnnotation(annotation)
                mergeIntoVisibleRect(MKMapRect(
                    origin: MKMapPoint(currentCoordinate),
                    size: MKMapSize(width: 0, height: 0)
                ))
            }

            if let destinationCoordinate {
                let annotation = MKPointAnnotation()
                annotation.coordinate = destinationCoordinate
                annotation.title = "Destination"
                mapView.addAnnotation(annotation)
                mergeIntoVisibleRect(MKMapRect(
                    origin: MKMapPoint(destinationCoordinate),
                    size: MKMapSize(width: 0, height: 0)
                ))
            }

            if let routePolyline {
                let splitOverlays = segmentedPolylines(
                    routePolyline: routePolyline,
                    currentCoordinate: currentCoordinate
                )
                splitOverlays.forEach { overlay in
                    mapView.addOverlay(overlay, level: .aboveRoads)
                    mergeIntoVisibleRect(overlay.boundingMapRect)
                }
            }

            if shouldFollowUserWhenMoving, let currentCoordinate {
                let currentLocation = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
                let movedEnough: Bool
                if let lastFollowLocation {
                    movedEnough = currentLocation.distance(from: lastFollowLocation) >= 4
                } else {
                    movedEnough = true
                }
                if movedEnough {
                    lastFollowLocation = currentLocation
                    let region = MKCoordinateRegion(
                        center: currentCoordinate,
                        latitudinalMeters: 900,
                        longitudinalMeters: 900
                    )
                    mapView.setRegion(region, animated: true)
                }
                return
            } else {
                lastFollowLocation = nil
            }

            guard let mapRectToFit, !mapRectToFit.isNull, !mapRectToFit.isEmpty else { return }
            let paddedRect = mapRectToFit.insetBy(
                dx: -max(mapRectToFit.size.width * 0.25, 180),
                dy: -max(mapRectToFit.size.height * 0.30, 180)
            )
            mapView.setVisibleMapRect(
                paddedRect,
                edgePadding: UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18),
                animated: true
            )
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            if polyline.title == "completed" {
                renderer.strokeColor = UIColor.systemGreen
            } else {
                renderer.strokeColor = UIColor.systemOrange
            }
            renderer.lineWidth = 6.5
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        private func segmentedPolylines(
            routePolyline: MKPolyline,
            currentCoordinate: CLLocationCoordinate2D?
        ) -> [MKPolyline] {
            let coordinates = coordinates(for: routePolyline)
            guard coordinates.count >= 2 else {
                return [routePolyline]
            }

            guard let currentCoordinate else {
                let full = MKPolyline(coordinates: coordinates, count: coordinates.count)
                full.title = "remaining"
                return [full]
            }

            let currentLocation = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
            let nearestIndex = coordinates.enumerated().min { lhs, rhs in
                let lhsDistance = CLLocation(latitude: lhs.element.latitude, longitude: lhs.element.longitude).distance(from: currentLocation)
                let rhsDistance = CLLocation(latitude: rhs.element.latitude, longitude: rhs.element.longitude).distance(from: currentLocation)
                return lhsDistance < rhsDistance
            }?.offset ?? 0

            var overlays: [MKPolyline] = []

            if nearestIndex > 0 {
                let completedCoords = Array(coordinates[0...nearestIndex])
                if completedCoords.count >= 2 {
                    let completed = MKPolyline(coordinates: completedCoords, count: completedCoords.count)
                    completed.title = "completed"
                    overlays.append(completed)
                }
            }

            let remainingCoords = Array(coordinates[max(nearestIndex, 0)...])
            if remainingCoords.count >= 2 {
                let remaining = MKPolyline(coordinates: remainingCoords, count: remainingCoords.count)
                remaining.title = "remaining"
                overlays.append(remaining)
            }

            if overlays.isEmpty {
                let fallback = MKPolyline(coordinates: coordinates, count: coordinates.count)
                fallback.title = "remaining"
                overlays.append(fallback)
            }

            return overlays
        }

        private func coordinates(for polyline: MKPolyline) -> [CLLocationCoordinate2D] {
            let count = polyline.pointCount
            var coordinates = Array(
                repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                count: count
            )
            polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: count))
            return coordinates
        }
    }
}

@MainActor
private final class RoutePreviewViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentCoordinate: CLLocationCoordinate2D?
    @Published var destinationCoordinate: CLLocationCoordinate2D?
    @Published var route: MKRoute?
    @Published var isLoadingRoute = false
    @Published var routeStatusMessage: String?

    private let locationManager = CLLocationManager()
    private var routeTask: Task<Void, Never>?
    private var lastAcceptedLocation: CLLocation?

    private let maximumHorizontalAccuracyMeters: CLLocationAccuracy = 80
    private let maximumLocationAgeSeconds: TimeInterval = 20

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    func onAppear() {
        locationManager.requestWhenInUseAuthorization()
        if locationManager.authorizationStatus == .authorizedWhenInUse ||
            locationManager.authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
            locationManager.requestLocation()
            if locationManager.accuracyAuthorization == .reducedAccuracy {
                routeStatusMessage = "Approximate location enabled. Turn on Precise Location for accurate map route."
            }
        } else {
            routeStatusMessage = "Allow location access to preview route from current location."
        }
    }

    func onDisappear() {
        locationManager.stopUpdatingLocation()
        routeTask?.cancel()
    }

    func updateDestination(latitudeText: String, longitudeText: String) {
        guard let latitude = Double(latitudeText),
              let longitude = Double(longitudeText) else {
            destinationCoordinate = nil
            route = nil
            if !latitudeText.isEmpty || !longitudeText.isEmpty {
                routeStatusMessage = "Enter valid destination coordinates to preview route."
            } else {
                routeStatusMessage = nil
            }
            return
        }

        destinationCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        routeStatusMessage = nil
        refreshRouteIfPossible()
    }

    func updateDestination(coordinate: CLLocationCoordinate2D) {
        destinationCoordinate = coordinate
        routeStatusMessage = nil
        refreshRouteIfPossible()
    }

    private func refreshRouteIfPossible() {
        guard let currentCoordinate, let destinationCoordinate else {
            route = nil
            if destinationCoordinate != nil {
                routeStatusMessage = "Waiting for current location..."
            }
            return
        }

        routeTask?.cancel()
        isLoadingRoute = true

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destinationCoordinate))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        routeTask = Task { [weak self] in
            do {
                let response = try await MKDirections(request: request).calculate()
                guard !Task.isCancelled else { return }
                await self?.applyRouteResponse(response)
            } catch {
                guard !Task.isCancelled else { return }
                await self?.applyRouteError(error)
            }
        }
    }

    private func applyRouteResponse(_ response: MKDirections.Response) {
        isLoadingRoute = false
        guard let firstRoute = response.routes.first else {
            route = nil
            routeStatusMessage = "No drivable route found for this destination."
            return
        }
        route = firstRoute
        routeStatusMessage = "Route preview is ready."
    }

    private func applyRouteError(_ error: Error) {
        isLoadingRoute = false
        route = nil
        routeStatusMessage = "Unable to load route preview right now."
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
            manager.requestLocation()
            if manager.accuracyAuthorization == .reducedAccuracy {
                routeStatusMessage = "Approximate location enabled. Turn on Precise Location for better accuracy."
            }
            refreshRouteIfPossible()
        } else if status == .denied || status == .restricted {
            routeStatusMessage = "Location access denied. Enable it to preview route."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = bestAcceptableLocation(from: locations) else {
            routeStatusMessage = "Waiting for accurate GPS fix..."
            return
        }

        if let previous = lastAcceptedLocation {
            let movedMeters = location.distance(from: previous)
            let jitterThreshold = max(6, min(25, location.horizontalAccuracy * 0.5))
            let speed = max(location.speed, 0)
            if movedMeters < jitterThreshold && speed < 0.8 {
                return
            }
        }

        lastAcceptedLocation = location
        currentCoordinate = location.coordinate
        if manager.accuracyAuthorization != .reducedAccuracy {
            routeStatusMessage = nil
        }
        refreshRouteIfPossible()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        routeStatusMessage = "Could not read current location for route preview."
    }

    private func bestAcceptableLocation(from locations: [CLLocation]) -> CLLocation? {
        let now = Date()
        return locations
            .filter { location in
                location.horizontalAccuracy >= 0 &&
                location.horizontalAccuracy <= maximumHorizontalAccuracyMeters &&
                abs(location.timestamp.timeIntervalSince(now)) <= maximumLocationAgeSeconds
            }
            .min { lhs, rhs in
                if lhs.horizontalAccuracy == rhs.horizontalAccuracy {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.horizontalAccuracy < rhs.horizontalAccuracy
            }
    }
}
