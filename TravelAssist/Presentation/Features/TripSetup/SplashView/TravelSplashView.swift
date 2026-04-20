//
//  TravelSplashView.swift
//  TravelAssist
//
//  Created by Rajesh Mani on 12/04/26.
//
import SwiftUI
import Foundation
import MapKit

struct TravelSplashView: View {

    @State private var offsetX: CGFloat = 0
    @State private var offsetY: CGFloat = 0
    @State private var showPins = false
    @ObservedObject var viewModel: TravelSplashViewModel

    var body: some View {
        ZStack {

            // 🌅 Gradient Background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "#FF9933"),
                    Color(hex: "#FF6A00")
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // 🗺 MapKit Background (blended)
            MapReader { proxy in
                Map(position: $viewModel.cameraPosition, interactionModes: []) { }
                .ignoresSafeArea()
                .opacity(0.4)
                .blendMode(.overlay)
                .saturation(1.2)
                .contrast(1.1)
                .overlay {
                    GeometryReader { geo in
                        if showPins {
                            ForEach(viewModel.pins) { pin in
                                if let point = proxy.convert(pin.coordinate, to: .local),
                                   point.x.isFinite,
                                   point.y.isFinite,
                                   point.x >= 0,
                                   point.y >= 0,
                                   point.x <= geo.size.width,
                                   point.y <= geo.size.height {
                                    WeatherPinView(
                                        symbolName: pin.symbolName ?? "cloud.fill",
                                        title: pin.name,
                                        temperatureText: pin.temperatureText
                                    )
                                    .opacity(pin.temperatureText == nil ? 0.9 : 1)
                                    .scaleEffect(pin.kind == .currentLocation ? 1.08 : 1)
                                    .position(point)
                                    .allowsHitTesting(false)
                                }
                            }
                        }
                    }
                }
            }

            // 🗺 Parallax Map Layers
            GeometryReader { geo in
                ZStack {

                    // Layer 1 (far - light roads)
                    Path { path in
                        path.move(to: CGPoint(x: 20, y: geo.size.height * 0.7))
                        path.addCurve(
                            to: CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.3),
                            control1: CGPoint(x: geo.size.width * 0.2, y: geo.size.height),
                            control2: CGPoint(x: geo.size.width * 0.3, y: 0)
                        )
                    }
                    .stroke(Color.white.opacity(0.08), lineWidth: 8)
                    .offset(x: offsetX * 0.2, y: offsetY * 0.2)

                    // Layer 2 (mid)
                    Path { path in
                        path.move(to: CGPoint(x: 40, y: geo.size.height * 0.8))
                        path.addCurve(
                            to: CGPoint(x: geo.size.width - 40, y: geo.size.height * 0.4),
                            control1: CGPoint(x: geo.size.width * 0.3, y: geo.size.height),
                            control2: CGPoint(x: geo.size.width * 0.7, y: 0)
                        )
                    }
                    .stroke(Color.white.opacity(0.12), lineWidth: 6)
                    .offset(x: offsetX * 0.4, y: offsetY * 0.4)

                    // Layer 3 (near - main route)
                    RouteShape()
                        .trim(from: 0, to: 1)
                        .stroke(
                            LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .offset(x: offsetX * 0.8, y: offsetY * 0.8)
                }
                .onAppear {
                    animateParallax()
                }
            }

            // ✈️ Foreground Content
            VStack(spacing: 20) {
                
                AnimatedTransportIcon()
                    .shadow(color: .red, radius: 4, x: 1, y: 0.8)
                    .padding(.top, 20)

                Text("TravelerX")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .red, radius: 4, x: 1, y: 0.8)

                Text("Your journey begins here")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
                    .shadow(color: .red, radius: 4, x: 1, y: 0.8)
            }
            .frame(width: 260, height: 240, alignment: .init(horizontal: .center, vertical: .top))
            .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.3))
            )
            .shadow(color: .orange, radius: 4, x: 1, y: 0.8)

        }
        .onAppear {
            viewModel.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.spring(response: 0.6)) {
                    showPins = true
                }
            }
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    private func animateParallax() {
        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
            offsetX = 20
            offsetY = -20
        }
    }
}


#Preview {
    TravelSplashView(viewModel: TravelSplashViewModel(locationService: CoreLocationService()))
}
