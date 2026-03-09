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
                keyValueRow(title: "ETA", value: viewModel.etaText)
                keyValueRow(title: "Status", value: viewModel.statusText)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button("Stop Monitoring") {
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
}

