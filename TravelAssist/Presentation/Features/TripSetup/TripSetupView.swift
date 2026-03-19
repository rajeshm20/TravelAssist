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
    @State private var isRoutePreviewExpanded = false
    @State private var isJourneyPlanExpanded = true
    @State private var isJourneyPlanEditorPresented = false
    @State private var isFakeCallPresented = false
    @State private var isFakeCallSpeaking = false
    @State private var selectedJourneyPlanDate = Calendar.current.startOfDay(for: Date())
    @State private var pendingDestinationDecision: DestinationDraft?
    @State private var editingJourneyPlanItem: JourneyPlanItem?
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

                        softCard {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Label(journeyPlanTitle, systemImage: "calendar.badge.clock")
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(.black.opacity(0.85))
                                    Text(Self.journeyPlanDateFormatter.string(from: selectedJourneyPlanDate))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Plan") {
                                    editingJourneyPlanItem = nil
                                    isJourneyPlanEditorPresented = true
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color(red: 0.99, green: 0.94, blue: 0.90), in: Capsule())
                                .foregroundStyle(Color(red: 0.98, green: 0.47, blue: 0.22))

                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isJourneyPlanExpanded.toggle()
                                    }
                                } label: {
                                    Image(systemName: isJourneyPlanExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color(red: 0.98, green: 0.47, blue: 0.22))
                                }
                                .buttonStyle(.plain)
                            }

                            HStack(spacing: 10) {
                                DatePicker(
                                    "Journey Date",
                                    selection: selectedJourneyPlanDateBinding,
                                    displayedComponents: .date
                                )
                                .labelsHidden()
                                .datePickerStyle(.compact)

                                Spacer()

                                Text("\(journeyPlanItemsForSelectedDate.count) stop\(journeyPlanItemsForSelectedDate.count == 1 ? "" : "s")")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(red: 0.94, green: 0.95, blue: 1.0), in: Capsule())
                                    .foregroundStyle(.secondary)
                            }

                            if isJourneyPlanExpanded {
                                if journeyPlanSections.isEmpty {
                                    Text(emptyJourneyPlanMessage)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 2)
                                } else {
                                    VStack(alignment: .leading, spacing: 12) {
                                        ForEach(journeyPlanSections) { section in
                                            VStack(alignment: .leading, spacing: 10) {
                                                HStack {
                                                    Text(section.title)
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(.secondary)
                                                    Spacer()
                                                    Text("\(section.items.count)")
                                                        .font(.caption2.weight(.bold))
                                                        .foregroundStyle(.secondary)
                                                }

                                                ForEach(section.items) { item in
                                                    journeyPlanRow(item)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
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

                                Button(monitoringViewModel.isMonitoring ? monitoringViewModel.stopButtonTitle : "Start Trip") {
                                    if monitoringViewModel.isMonitoring {
                                        monitoringViewModel.stopMonitoring()
                                    } else {
                                        viewModel.startMonitoring(using: monitoringViewModel.journeyPlanItems)
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
                                Label(monitoringViewModel.isMonitoring ? "Current Trip" : "Destination & Route", systemImage: "mappin.and.ellipse")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.black.opacity(0.85))
                                Spacer()
                                if !monitoringViewModel.isMonitoring {
                                    Button(viewModel.selectedDestinationName == nil ? "Search Map" : "Change") {
                                        isDestinationPickerPresented = true
                                    }
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color(red: 0.91, green: 0.93, blue: 0.98), in: Capsule())
                                }
                            }

                            if let tripName = monitoringViewModel.isMonitoring ? currentTripName : viewModel.selectedDestinationName {
                                Text(tripName)
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
                            .onChange(of: monitoringViewModel.activeSession?.destinationCoordinate.latitude) { _, _ in
                                syncRoutePreviewDestination()
                            }
                            .onChange(of: monitoringViewModel.activeSession?.destinationCoordinate.longitude) { _, _ in
                                syncRoutePreviewDestination()
                            }

                            if let routeStatusMessage = routePreviewViewModel.routeStatusMessage {
                                Text(routeStatusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Text(
                                monitoringViewModel.isMonitoring
                                ? "Live trip preview follows your active route."
                                : "Search for a place, preview the route here, then start monitoring."
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
                DestinationMapPickerSheet(initialSelection: selectedDestinationDraft) { destination in
                    handleDestinationSelection(destination)
                }
            }
            .sheet(isPresented: $isJourneyPlanEditorPresented, onDismiss: {
                editingJourneyPlanItem = nil
            }) {
                JourneyPlanEditorSheet(
                    viewModel: viewModel,
                    existingItems: monitoringViewModel.journeyPlanItems,
                    selectedDate: selectedJourneyPlanDate,
                    editingItem: editingJourneyPlanItem
                )
            }
            .sheet(isPresented: $isHistoryPresented) {
                MonitoringHistoryBottomSheet(sessions: monitoringViewModel.historySessions)
                    .presentationDetents([.fraction(0.25), .medium, .large])
                    .presentationDragIndicator(.visible)
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
            .alert(
                "Update Current Monitoring?",
                isPresented: pendingDestinationDecisionBinding,
                presenting: pendingDestinationDecision
            ) { destination in
                Button("Change Current Trip") {
                    viewModel.changeActiveMonitoringDestination(name: destination.title, coordinate: destination.coordinate)
                }
                Button("Add To Next Plan") {
                    viewModel.addDestinationToJourneyPlan(
                        existingItems: monitoringViewModel.journeyPlanItems,
                        name: destination.title,
                        subtitle: destination.subtitle,
                        coordinate: destination.coordinate,
                        estimatedTravelDurationSeconds: destination.estimatedTravelTime
                    )
                    selectedJourneyPlanDate = Calendar.current.startOfDay(for: viewModel.plannedStartDate)
                    isJourneyPlanExpanded = true
                }
                Button("Keep Current Trip", role: .cancel) {}
            } message: { destination in
                Text("Monitoring is already running. Switch the active trip to \(destination.title), or keep the current trip and add this place to your next journey plan.")
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
    private func journeyPlanRow(_ item: JourneyPlanItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.selectedJourneyMode.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 0.98, green: 0.47, blue: 0.22))
                .frame(width: 28, height: 28)
                .background(Color(red: 0.99, green: 0.94, blue: 0.90), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.82))

                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text("Lead time \(leadTimeText(minutes: item.leadTimeMinutes))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 4) {
                Text(Self.journeyPlanTimeFormatter.string(from: item.plannedStartAt))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.76))
                Text(Self.journeyPlanTimeFormatter.string(from: item.approximateEndAt))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(journeyPlanStatusText(for: item))
                    .font(.caption2)
                    .foregroundStyle(journeyPlanStatusColor(for: item))
                if item.status != .completed {
                    Button {
                        editingJourneyPlanItem = item
                        selectedJourneyPlanDate = Calendar.current.startOfDay(for: item.plannedStartAt)
                        isJourneyPlanEditorPresented = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color(red: 0.19, green: 0.45, blue: 0.93))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(red: 0.97, green: 0.98, blue: 1.0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    private var currentTripName: String? {
        if let journeyPlanItemID = monitoringViewModel.activeSession?.journeyPlanItemID,
           let matchedItem = monitoringViewModel.journeyPlanItems.first(where: { $0.id == journeyPlanItemID }) {
            return matchedItem.title
        }
        return viewModel.selectedDestinationName
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

    private func handleDestinationSelection(_ draft: DestinationDraft) {
        guard monitoringViewModel.isMonitoring else {
            viewModel.applyDestinationFromAppleMaps(name: draft.title, coordinate: draft.coordinate)
            return
        }

        if isCurrentActiveDestination(draft.coordinate) {
            viewModel.applyDestinationFromAppleMaps(name: draft.title, coordinate: draft.coordinate)
            return
        }

        pendingDestinationDecision = draft
    }

    private func isCurrentActiveDestination(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard let activeDestination = monitoringViewModel.activeSession?.destinationCoordinate else {
            return false
        }

        return abs(activeDestination.latitude - coordinate.latitude) < 0.00001 &&
            abs(activeDestination.longitude - coordinate.longitude) < 0.00001
    }

    private func leadTimeText(minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func journeyPlanStatusText(for item: JourneyPlanItem) -> String {
        switch item.status {
        case .completed:
            return "Completed"
        case .inProgress:
            return "In Progress"
        case .started:
            return item.plannedStartAt > Date() ? "Not Started" : "Started"
        }
    }

    private func journeyPlanStatusColor(for item: JourneyPlanItem) -> Color {
        switch item.status {
        case .completed:
            return Color.green.opacity(0.85)
        case .inProgress:
            return Color(red: 0.98, green: 0.47, blue: 0.22)
        case .started:
            return item.plannedStartAt > Date()
                ? .secondary
                : Color(red: 0.19, green: 0.45, blue: 0.93)
        }
    }

    private var selectedJourneyPlanDateBinding: Binding<Date> {
        Binding(
            get: { selectedJourneyPlanDate },
            set: { selectedJourneyPlanDate = Calendar.current.startOfDay(for: $0) }
        )
    }

    private var pendingDestinationDecisionBinding: Binding<Bool> {
        Binding(
            get: { pendingDestinationDecision != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDestinationDecision = nil
                }
            }
        )
    }

    private var selectedDestinationDraft: DestinationDraft? {
        guard let selectedDestinationCoordinate else { return nil }
        return DestinationDraft(
            title: viewModel.selectedDestinationName ?? "Selected destination",
            subtitle: nil,
            coordinate: selectedDestinationCoordinate,
            estimatedTravelTime: nil
        )
    }

    private var selectedDestinationCoordinate: CLLocationCoordinate2D? {
        guard let latitude = Double(viewModel.destinationLatitudeText),
              let longitude = Double(viewModel.destinationLongitudeText) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var journeyPlanTitle: String {
        Calendar.current.isDateInToday(selectedJourneyPlanDate) ? "Today's Journey Plan" : "Journey Plan"
    }

    private var journeyPlanItemsForSelectedDate: [JourneyPlanItem] {
        monitoringViewModel.journeyPlanItems
            .filter { Calendar.current.isDate($0.plannedStartAt, inSameDayAs: selectedJourneyPlanDate) }
            .sorted { lhs, rhs in
                if lhs.plannedStartAt == rhs.plannedStartAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.plannedStartAt < rhs.plannedStartAt
            }
    }

    private var journeyPlanSections: [JourneyPlanSection] {
        JourneyPlanTimeBucket.allCases.compactMap { bucket in
            let items = journeyPlanItemsForSelectedDate.filter { bucket.contains($0.plannedStartAt) }
            guard !items.isEmpty else { return nil }
            return JourneyPlanSection(title: bucket.title, items: items)
        }
    }

    private var emptyJourneyPlanMessage: String {
        "No places planned for \(Self.journeyPlanDateFormatter.string(from: selectedJourneyPlanDate)). Add a destination while monitoring to line up your next stop."
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

    private static let journeyPlanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let journeyPlanTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

private struct JourneyPlanSection: Identifiable {
    let title: String
    let items: [JourneyPlanItem]

    var id: String { title }
}

private enum JourneyPlanTimeBucket: CaseIterable {
    case earlyMorning
    case morning
    case afternoon
    case evening
    case night

    var title: String {
        switch self {
        case .earlyMorning: return "Early Morning"
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        case .night: return "Night"
        }
    }

    func contains(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        switch self {
        case .earlyMorning:
            return (0..<6).contains(hour)
        case .morning:
            return (6..<12).contains(hour)
        case .afternoon:
            return (12..<17).contains(hour)
        case .evening:
            return (17..<21).contains(hour)
        case .night:
            return (21..<24).contains(hour)
        }
    }
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

private struct DestinationMapPickerSheet: View {
    let initialSelection: DestinationDraft?
    let onSelect: (DestinationDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchViewModel = DestinationSearchViewModel()
    @StateObject private var routePreviewViewModel = RoutePreviewViewModel()
    @State private var query = ""
    @State private var pendingSelection: DestinationDraft?
    @State private var previewTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    previewHeader
                    searchResultsContent
                }
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if searchViewModel.isLoading {
                    ProgressView("Fetching location...")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .safeAreaInset(edge: .bottom) {
                confirmSelectionBar
            }
            .searchable(text: $query, prompt: "Search Apple Maps")
            .onChange(of: query) { value in
                searchViewModel.updateQuery(value)
            }
            .onAppear {
                routePreviewViewModel.onAppear()
                if let initialSelection {
                    pendingSelection = initialSelection
                    routePreviewViewModel.updateDestination(coordinate: initialSelection.coordinate)
                }
            }
            .onDisappear {
                previewTask?.cancel()
                previewTask = nil
                routePreviewViewModel.onDisappear()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .navigationTitle("Choose Destination")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var previewHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoutePreviewMapView(
                viewModel: routePreviewViewModel,
                isMonitoringActive: false,
                onExpand: nil,
                shouldFollowUserWhenMoving: false
            )
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            selectionSummary

            if let routeStatusMessage = routePreviewViewModel.routeStatusMessage {
                Text(routeStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let errorMessage = searchViewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var selectionSummary: some View {
        if let pendingSelection {
            VStack(alignment: .leading, spacing: 4) {
                Text(pendingSelection.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let subtitle = pendingSelection.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(selectedCoordinateText(for: pendingSelection))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Search for a place, tap a result, and the route preview updates instantly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var searchResultsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            recentDestinationsSection
            emptySearchSection
            searchResultRows
            emptyResultsState
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var recentDestinationsSection: some View {
        if !searchViewModel.recentDestinations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        searchViewModel.clearRecentDestinations()
                    }
                    .font(.caption)
                }

                ForEach(searchViewModel.recentDestinations) { destination in
                    recentDestinationRow(destination)
                }
            }
        }
    }

    @ViewBuilder
    private var emptySearchSection: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Search for a place or address to drop a pin and preview the route.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.97, green: 0.98, blue: 1.0), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var searchResultRows: some View {
        ForEach(Array(searchViewModel.results.enumerated()), id: \.offset) { _, completion in
            searchResultRow(completion)
        }
    }

    @ViewBuilder
    private var emptyResultsState: some View {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           searchViewModel.results.isEmpty,
           !searchViewModel.isLoading,
           searchViewModel.errorMessage == nil {
            Text("No matching destinations found yet. Try a nearby landmark, area, or full address.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.97, green: 0.98, blue: 1.0), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var confirmSelectionBar: some View {
        VStack(spacing: 10) {
            Button {
                confirmSelection()
            } label: {
                Text(confirmSelectionButtonTitle)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(confirmSelectionBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(confirmSelectionForegroundColor)
            }
            .buttonStyle(.plain)
            .disabled(pendingSelection == nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }

    private var confirmSelectionButtonTitle: String {
        pendingSelection == nil ? "Preview a Destination" : "Use This Destination"
    }

    private var confirmSelectionBackground: Color {
        pendingSelection == nil ? Color.gray.opacity(0.18) : Color(red: 0.98, green: 0.47, blue: 0.22)
    }

    private var confirmSelectionForegroundColor: Color {
        pendingSelection == nil ? .secondary : .white
    }

    private func selectedCoordinateText(for selection: DestinationDraft) -> String {
        String(
            format: "%.5f, %.5f",
            selection.coordinate.latitude,
            selection.coordinate.longitude
        )
    }

    private func recentDestinationRow(_ destination: RecentDestination) -> some View {
        Button {
            selectRecentDestination(destination)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.title)
                        .font(.body)
                    if let subtitle = destination.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if isSelected(recentDestination: destination) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func searchResultRow(_ completion: MKLocalSearchCompletion) -> some View {
        Button {
            selectSearchCompletion(completion)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(completion.title)
                        .font(.body)
                    if !completion.subtitle.isEmpty {
                        Text(completion.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if isSelected(completion: completion) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func selectRecentDestination(_ destination: RecentDestination) {
        previewTask?.cancel()
        previewTask = nil
        let draft = DestinationDraft(
            title: destination.title,
            subtitle: destination.subtitle,
            coordinate: CLLocationCoordinate2D(
                latitude: destination.latitude,
                longitude: destination.longitude
            ),
            estimatedTravelTime: nil
        )
        applySelection(draft)
    }

    private func selectSearchCompletion(_ completion: MKLocalSearchCompletion) {
        previewTask?.cancel()
        previewTask = Task {
            defer { previewTask = nil }
            guard let item = await searchViewModel.resolve(completion) else { return }
            guard !Task.isCancelled else { return }

            let draft = DestinationDraft(
                title: item.name ?? completion.title,
                subtitle: completion.subtitle,
                coordinate: item.placemark.coordinate,
                estimatedTravelTime: nil
            )
            applySelection(draft)
        }
    }

    private func applySelection(_ pendingSelection: DestinationDraft) {
        self.pendingSelection = pendingSelection
        routePreviewViewModel.updateDestination(coordinate: pendingSelection.coordinate)
    }

    private func confirmSelection() {
        guard let pendingSelection else { return }
        let confirmedSelection = DestinationDraft(
            title: pendingSelection.title,
            subtitle: pendingSelection.subtitle,
            coordinate: pendingSelection.coordinate,
            estimatedTravelTime: routePreviewViewModel.route?.expectedTravelTime
        )
        searchViewModel.saveRecentDestination(
            title: confirmedSelection.title,
            subtitle: confirmedSelection.subtitle,
            coordinate: confirmedSelection.coordinate
        )
        onSelect(confirmedSelection)
        dismiss()
    }

    private func isSelected(recentDestination: RecentDestination) -> Bool {
        guard let pendingSelection else { return false }
        return abs(pendingSelection.coordinate.latitude - recentDestination.latitude) < 0.00001 &&
            abs(pendingSelection.coordinate.longitude - recentDestination.longitude) < 0.00001
    }

    private func isSelected(completion: MKLocalSearchCompletion) -> Bool {
        guard let pendingSelection else { return false }
        return pendingSelection.title == completion.title && pendingSelection.subtitle == completion.subtitle
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

private struct JourneyPlanDateTimeSheet: View {
    @ObservedObject var viewModel: TripSetupViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    DatePicker(
                        "Travel Date",
                        selection: Binding(
                            get: { viewModel.plannedStartDate },
                            set: { viewModel.updatePlannedStart(from: $0) }
                        ),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)

                    DatePicker(
                        "Planned Start Time",
                        selection: Binding(
                            get: { viewModel.plannedStartDate },
                            set: { viewModel.updatePlannedStart(from: $0) }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .environment(\.locale, Locale(identifier: "en_GB"))

                    Text("Selected: \(viewModel.plannedStartFormatted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Planned Start")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct JourneyPlanEditorSheet: View {
    @ObservedObject var viewModel: TripSetupViewModel
    let existingItems: [JourneyPlanItem]
    let selectedDate: Date
    let editingItem: JourneyPlanItem?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var routePreviewViewModel = RoutePreviewViewModel()
    @State private var isDestinationPickerPresented = false
    @State private var isDateTimeExpanded = false
    @State private var destinationDraft: DestinationDraft?
    @State private var plannedStartAt: Date
    @State private var estimatedTravelDurationSeconds: TimeInterval
    @State private var selectedJourneyMode: JourneyMode
    @State private var leadTimeMinutes: Int

    init(
        viewModel: TripSetupViewModel,
        existingItems: [JourneyPlanItem],
        selectedDate: Date,
        editingItem: JourneyPlanItem?
    ) {
        self.viewModel = viewModel
        self.existingItems = existingItems
        self.selectedDate = selectedDate
        self.editingItem = editingItem

        let calendar = Calendar.current
        let referenceDate = editingItem?.plannedStartAt ?? viewModel.plannedStartDate
        let baseDate = calendar.startOfDay(for: selectedDate)
        let referenceComponents = calendar.dateComponents([.hour, .minute], from: referenceDate)
        let resolvedStartAt = calendar.date(
            bySettingHour: referenceComponents.hour ?? 9,
            minute: referenceComponents.minute ?? 0,
            second: 0,
            of: baseDate
        ) ?? referenceDate

        _plannedStartAt = State(initialValue: resolvedStartAt)
        _estimatedTravelDurationSeconds = State(initialValue: editingItem?.estimatedTravelDurationSeconds ?? 0)
        _selectedJourneyMode = State(initialValue: editingItem?.selectedJourneyMode ?? viewModel.selectedJourneyMode)
        _leadTimeMinutes = State(
            initialValue: editingItem?.leadTimeMinutes ?? ((viewModel.selectedLeadHours * 60) + viewModel.selectedLeadMinutes)
        )
        _destinationDraft = State(
            initialValue: editingItem.map {
                DestinationDraft(
                    title: $0.title,
                    subtitle: $0.subtitle,
                    coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude),
                    estimatedTravelTime: $0.estimatedTravelDurationSeconds
                )
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    RoutePreviewMapView(
                        viewModel: routePreviewViewModel,
                        isMonitoringActive: false,
                        onExpand: nil,
                        shouldFollowUserWhenMoving: false
                    )
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isDateTimeExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Label("Travel Date & Time", systemImage: "calendar.badge.clock")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(Self.dateFormatter.string(from: plannedStartAt))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(Self.timeFormatter.string(from: plannedStartAt))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: isDateTimeExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color(red: 0.19, green: 0.45, blue: 0.93))
                            }
                        }
                        .buttonStyle(.plain)

                        if isDateTimeExpanded {
                            DatePicker(
                                "Travel Date",
                                selection: dateBinding,
                                in: dateSelectionRange,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.wheel)
                            .environment(\.locale, Locale(identifier: "en_GB"))
                            .labelsHidden()

                            DatePicker(
                                "Start Time",
                                selection: startTimeBinding,
                                in: timeSelectionRange,
                                displayedComponents: .hourAndMinute
                            )
                            .datePickerStyle(.wheel)
                            .environment(\.locale, Locale(identifier: "en_GB"))
                            .labelsHidden()
                        }
                    }
                    .padding(14)
                    .background(Color(red: 0.97, green: 0.98, blue: 1.0), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    HStack(spacing: 12) {
                        plannerControlCard(
                            title: "Journey Mode",
                            value: selectedJourneyMode.title,
                            systemImage: selectedJourneyMode.symbolName,
                            onPrevious: { cycleJourneyMode(by: -1) },
                            onNext: { cycleJourneyMode(by: 1) }
                        )

                        plannerControlCard(
                            title: "Lead Time",
                            value: leadTimeText,
                            systemImage: "clock.badge.checkmark",
                            onPrevious: { adjustLeadTime(by: -5) },
                            onNext: { adjustLeadTime(by: 5) }
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Destination", systemImage: "mappin.and.ellipse")
                                .font(.headline.weight(.semibold))
                            Spacer()
                            Button(destinationDraft == nil ? "Choose" : "Change") {
                                isDestinationPickerPresented = true
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(red: 0.91, green: 0.93, blue: 0.98), in: Capsule())
                        }

                        if let destinationDraft {
                            Text(destinationDraft.title)
                                .font(.body.weight(.semibold))
                            if let subtitle = destinationDraft.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Choose a destination from the map search to calculate the trip.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let routeStatusMessage = routePreviewViewModel.routeStatusMessage {
                            Text(routeStatusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Trip Timing")
                            .font(.headline.weight(.semibold))
                        timingRow(title: "Start", value: Self.timeFormatter.string(from: plannedStartAt))
                        timingRow(title: "Approx. End", value: approximateEndTimeText)
                        timingRow(title: "Journey Mode", value: selectedJourneyMode.title)
                        timingRow(title: "Lead Time", value: leadTimeText)
                    }
                    .padding(14)
                    .background(Color(red: 0.99, green: 0.94, blue: 0.90), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding()
            }
            .navigationTitle(editingItem == nil ? "Plan Journey" : "Edit Journey")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingItem == nil ? "Add" : "Save") {
                        saveJourneyPlan()
                    }
                    .disabled(destinationDraft == nil)
                }
            }
            .sheet(isPresented: $isDestinationPickerPresented) {
                DestinationMapPickerSheet(initialSelection: destinationDraft) { destination in
                    destinationDraft = destination
                    if let estimatedTravelTime = destination.estimatedTravelTime {
                        estimatedTravelDurationSeconds = estimatedTravelTime
                    }
                    routePreviewViewModel.updateDestination(coordinate: destination.coordinate)
                }
            }
            .onAppear {
                routePreviewViewModel.onAppear()
                plannedStartAt = clampedPlannedStartAt(plannedStartAt)
                if let destinationDraft {
                    routePreviewViewModel.updateDestination(coordinate: destinationDraft.coordinate)
                }
            }
            .onDisappear {
                routePreviewViewModel.onDisappear()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var startTimeBinding: Binding<Date> {
        Binding(
            get: { plannedStartAt },
            set: { newValue in
                let calendar = Calendar.current
                let day = calendar.startOfDay(for: plannedStartAt)
                let components = calendar.dateComponents([.hour, .minute], from: newValue)
                let candidate = calendar.date(
                    bySettingHour: components.hour ?? 0,
                    minute: components.minute ?? 0,
                    second: 0,
                    of: day
                ) ?? newValue
                plannedStartAt = clampedPlannedStartAt(candidate)
            }
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { plannedStartAt },
            set: { newValue in
                let calendar = Calendar.current
                let time = calendar.dateComponents([.hour, .minute], from: plannedStartAt)
                let baseDate = calendar.startOfDay(for: newValue)
                let candidate = calendar.date(
                    bySettingHour: time.hour ?? 0,
                    minute: time.minute ?? 0,
                    second: 0,
                    of: baseDate
                ) ?? newValue
                plannedStartAt = clampedPlannedStartAt(candidate)
            }
        )
    }

    private var dateSelectionRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let lowerBound = calendar.startOfDay(for: Date())
        let upperBound = calendar.date(byAdding: .year, value: 2, to: lowerBound) ?? lowerBound.addingTimeInterval(63_072_000)
        return lowerBound...upperBound
    }

    private var timeSelectionRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: plannedStartAt)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-60) ?? plannedStartAt

        if calendar.isDateInToday(plannedStartAt) {
            let minimum = max(clampedCurrentTime, dayStart)
            return minimum...max(minimum, dayEnd)
        }

        return dayStart...dayEnd
    }

    private var resolvedTravelDurationSeconds: TimeInterval {
        max(routePreviewViewModel.route?.expectedTravelTime ?? estimatedTravelDurationSeconds, 0)
    }

    private var leadTimeText: String {
        String(format: "%02d:%02d", leadTimeMinutes / 60, leadTimeMinutes % 60)
    }

    private var approximateEndTimeText: String {
        guard destinationDraft != nil else { return "--" }
        return Self.timeFormatter.string(from: plannedStartAt.addingTimeInterval(resolvedTravelDurationSeconds))
    }

    private func saveJourneyPlan() {
        guard let destinationDraft else { return }
        viewModel.saveJourneyPlanItem(
            existingItems: existingItems,
            editing: editingItem,
            title: destinationDraft.title,
            subtitle: destinationDraft.subtitle,
            coordinate: destinationDraft.coordinate,
            plannedStartAt: plannedStartAt,
            estimatedTravelDurationSeconds: resolvedTravelDurationSeconds,
            selectedJourneyMode: selectedJourneyMode,
            leadTimeMinutes: leadTimeMinutes
        )
        dismiss()
    }

    private var clampedCurrentTime: Date {
        let calendar = Calendar.current
        let now = Date()
        let roundedDown = calendar.date(
            bySettingHour: calendar.component(.hour, from: now),
            minute: calendar.component(.minute, from: now),
            second: 0,
            of: now
        ) ?? now

        if calendar.component(.second, from: now) == 0 {
            return roundedDown
        }

        return roundedDown.addingTimeInterval(60)
    }

    private func clampedPlannedStartAt(_ date: Date) -> Date {
        let calendar = Calendar.current
        guard calendar.isDateInToday(date) else { return date }
        let minimum = clampedCurrentTime
        return max(date, minimum)
    }

    private func cycleJourneyMode(by delta: Int) {
        let allModes = JourneyMode.allCases
        guard let currentIndex = allModes.firstIndex(of: selectedJourneyMode) else { return }
        let nextIndex = (currentIndex + delta + allModes.count) % allModes.count
        selectedJourneyMode = allModes[nextIndex]
    }

    private func adjustLeadTime(by deltaMinutes: Int) {
        let minimum = 5
        let maximum = (23 * 60) + 55
        leadTimeMinutes = min(max(leadTimeMinutes + deltaMinutes, minimum), maximum)
    }

    @ViewBuilder
    private func plannerControlCard(
        title: String,
        value: String,
        systemImage: String,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.9), in: Circle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)

                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.9), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.97, green: 0.98, blue: 1.0), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func timingRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
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
    private let queryDebounceNanoseconds: UInt64 = 250_000_000
    private var queryTask: Task<Void, Never>?
    private var activeResolveID: UUID?
    private var activeSearch: MKLocalSearch?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        loadRecentDestinations()
    }

    deinit {
        queryTask?.cancel()
        activeSearch?.cancel()
        completer.delegate = nil
    }

    func updateQuery(_ query: String) {
        queryTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            results = []
            errorMessage = nil
            activeSearch?.cancel()
            activeSearch = nil
            return
        }
        errorMessage = nil

        queryTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.queryDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.completer.queryFragment = trimmed
            }
        }
    }

    @MainActor
    func resolve(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        let resolveID = UUID()
        activeResolveID = resolveID
        isLoading = true
        errorMessage = nil
        activeSearch?.cancel()

        do {
            let request = MKLocalSearch.Request(completion: completion)
            let search = MKLocalSearch(request: request)
            activeSearch = search
            let response = try await search.start()
            guard activeResolveID == resolveID else { return nil }
            isLoading = false
            activeResolveID = nil
            activeSearch = nil
            guard let mapItem = response.mapItems.first else {
                errorMessage = "Could not resolve this place. Try another result."
                return nil
            }
            return mapItem
        } catch is CancellationError {
            if activeResolveID == resolveID {
                isLoading = false
                activeResolveID = nil
                activeSearch = nil
            }
            return nil
        } catch {
            guard activeResolveID == resolveID else { return nil }
            isLoading = false
            activeResolveID = nil
            activeSearch = nil
            errorMessage = "Unable to fetch location from Apple Maps."
            return nil
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor [weak self] in
            self?.results = completer.results
            self?.errorMessage = nil
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
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

private struct DestinationDraft {
    let title: String
    let subtitle: String?
    let coordinate: CLLocationCoordinate2D
    let estimatedTravelTime: TimeInterval?
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
                focusRequestToken: viewModel.focusRequestToken,
                shouldFollowUserWhenMoving: shouldFollowUserWhenMoving
            )

            VStack {
                HStack(spacing: 10) {
                    Spacer()
                    Button {
                        viewModel.focusOnCurrentRoute()
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)

                    if let onExpand {
                        Button(action: onExpand) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
            }
            .padding(10)

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
    let focusRequestToken: Int
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
            focusRequestToken: focusRequestToken,
            shouldFollowUserWhenMoving: shouldFollowUserWhenMoving
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var lastFollowLocation: CLLocation?
        private var lastFocusRequestToken = 0

        func update(
            mapView: MKMapView,
            currentCoordinate: CLLocationCoordinate2D?,
            destinationCoordinate: CLLocationCoordinate2D?,
            routePolyline: MKPolyline?,
            focusRequestToken: Int,
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

            if focusRequestToken != lastFocusRequestToken {
                lastFocusRequestToken = focusRequestToken
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
    @Published var focusRequestToken = 0

    private let locationManager = CLLocationManager()
    private var routeTask: Task<Void, Never>?
    private var activeDirections: MKDirections?
    private var lastAcceptedLocation: CLLocation?
    private var activeRouteRequestID: UUID?
    private var lastLocationRequestAt: Date?

    private let maximumHorizontalAccuracyMeters: CLLocationAccuracy = 80
    private let maximumLocationAgeSeconds: TimeInterval = 20
    private let minimumLocationRequestIntervalSeconds: TimeInterval = 2

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 25
        locationManager.pausesLocationUpdatesAutomatically = true
    }

    func onAppear() {
        locationManager.requestWhenInUseAuthorization()
        if locationManager.authorizationStatus == .authorizedWhenInUse ||
            locationManager.authorizationStatus == .authorizedAlways {
            requestCurrentLocationIfNeeded(force: true)
            if locationManager.accuracyAuthorization == .reducedAccuracy {
                routeStatusMessage = "Approximate location enabled. Turn on Precise Location for accurate map route."
            }
        } else {
            routeStatusMessage = "Allow location access to preview route from current location."
        }
    }

    func onDisappear() {
        locationManager.stopUpdatingLocation()
        cancelRouteComputation()
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

    func focusOnCurrentRoute() {
        requestCurrentLocationIfNeeded(force: true)
        focusRequestToken += 1
    }

    private func refreshRouteIfPossible() {
        guard let currentCoordinate, let destinationCoordinate else {
            cancelRouteComputation()
            route = nil
            if destinationCoordinate != nil {
                routeStatusMessage = "Waiting for current location..."
                requestCurrentLocationIfNeeded()
            }
            return
        }

        cancelRouteComputation()
        isLoadingRoute = true

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destinationCoordinate))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        let directions = MKDirections(request: request)
        let requestID = UUID()
        activeDirections = directions
        activeRouteRequestID = requestID

        routeTask = Task { [weak self] in
            do {
                let response = try await directions.calculate()
                guard !Task.isCancelled else { return }
                await self?.applyRouteResponse(response, requestID: requestID)
            } catch is CancellationError {
                await self?.handleCancelledRoute(requestID: requestID)
            } catch {
                guard !Task.isCancelled else { return }
                await self?.applyRouteError(error, requestID: requestID)
            }
        }
    }

    private func applyRouteResponse(_ response: MKDirections.Response, requestID: UUID) {
        guard activeRouteRequestID == requestID else { return }
        finishRouteRequest()
        isLoadingRoute = false
        guard let firstRoute = response.routes.first else {
            route = nil
            routeStatusMessage = "No drivable route found for this destination."
            return
        }
        route = firstRoute
        routeStatusMessage = "Route preview is ready."
    }

    private func applyRouteError(_ error: Error, requestID: UUID) {
        guard activeRouteRequestID == requestID else { return }
        finishRouteRequest()
        isLoadingRoute = false
        route = nil
        routeStatusMessage = "Unable to load route preview right now."
    }

    private func handleCancelledRoute(requestID: UUID) {
        guard activeRouteRequestID == requestID else { return }
        finishRouteRequest()
        isLoadingRoute = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            requestCurrentLocationIfNeeded(force: true)
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

    private func requestCurrentLocationIfNeeded(force: Bool = false) {
        let now = Date()
        if !force,
           let lastLocationRequestAt,
           now.timeIntervalSince(lastLocationRequestAt) < minimumLocationRequestIntervalSeconds {
            return
        }
        lastLocationRequestAt = now
        locationManager.requestLocation()
    }

    private func cancelRouteComputation() {
        routeTask?.cancel()
        routeTask = nil
        activeDirections?.cancel()
        activeDirections = nil
        activeRouteRequestID = nil
        isLoadingRoute = false
    }

    private func finishRouteRequest() {
        routeTask = nil
        activeDirections = nil
        activeRouteRequestID = nil
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
