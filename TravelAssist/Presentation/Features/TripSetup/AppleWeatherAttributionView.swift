import SwiftUI

struct AppleWeatherAttributionView: View {
    enum Style {
        case footer
        case overlay
    }

    var style: Style = .footer

    var body: some View {
        Group {
            switch style {
            case .footer:
                content
            case .overlay:
                content
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var content: some View {
        VStack(spacing: 2) {
            Text(" Weather")
                .font(.caption2.weight(.semibold))
            Link(Self.legalAttributionHostAndPath, destination: Self.legalAttributionURL)
                .font(.caption2)
                .underline()
                .accessibilityLabel("Apple Weather legal attribution")
        }
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }

    private static let legalAttributionURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
    private static let legalAttributionHostAndPath = "weatherkit.apple.com/legal-attribution.html"
}

