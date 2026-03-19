import SwiftUI

struct MonitoringView: View {
    @ObservedObject var viewModel: MonitoringViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Trip Monitoring")
                .font(.title2.bold())

            VStack(spacing: 10) {
                keyValueRow(title: "Distance", value: viewModel.distanceText)
                keyValueRow(title: "ETA (Hour/Min)", value: viewModel.etaText)
                keyValueRow(title: "Status", value: viewModel.statusText)
                iconValueRow(title: "Journey", symbol: viewModel.selectedJourneyModeSymbol, value: viewModel.selectedJourneyModeText)
                iconValueRow(title: "Detected", symbol: viewModel.detectedModeSymbol, value: viewModel.detectedModeText)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button(viewModel.stopButtonTitle) {
                viewModel.stopMonitoring()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func keyValueRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
            Spacer()
            Text(value)
        }
    }

    @ViewBuilder
    private func iconValueRow(title: String, symbol: String, value: String) -> some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
            Spacer()
            Image(systemName: symbol)
            Text(value)
        }
    }
}
