//
//  WeatherPinView.swift
//  TravelAssist
//
//  Created by Rajesh Mani on 12/04/26.
//
import SwiftUI

struct WeatherPinView: View {
    let symbolName: String
    let title: String
    let temperatureText: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.yellow.opacity(0.95))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(temperatureText ?? "—")
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.72),
                            Color.black.opacity(0.42)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 8)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        WeatherPinView(symbolName: "cloud.sun.fill", title: "Marina Beach", temperatureText: "28°")
    }
}
