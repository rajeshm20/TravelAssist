//
//  AnimatedTransportIcon.swift
//  TravelAssist
//
//  Created by Rajesh Mani on 12/04/26.
//
import Foundation
import SwiftUI


struct AnimatedTransportIcon: View {

    let icons = [
        "figure.walk",
        "bicycle",
        "car.fill",
        "bus.fill",
        "motorcycle",
        "airplane"
    ]

    @State private var currentIcon = "airplane"
    @State private var animate = false
    @State private var timer: Timer?
    @State private var showNext = false
    @State private var isRunning = false

    var body: some View {
        Image(systemName: currentIcon)
            .font(.system(size: 60))
            .foregroundColor(.white)

            // ✨ Entrance animation
            .scaleEffect(animate ? 1.0 : 0.5)
            .offset(y: animate ? 0 : -60)
            .opacity(animate ? 1 : 0)
            .rotationEffect(.degrees(showNext ? 5 : -5))
            .animation(.easeInOut(duration: 0.6), value: showNext)
            .blur(radius: showNext ? 2 : 0)
            // 🔁 Smooth transition between icons
            .contentTransition(.symbolEffect(.replace))
            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: currentIcon)

            // 🌊 Continuous subtle motion
            .modifier(ConditionalSymbolEffect(currentIcon: currentIcon))

            .onAppear {
                startAnimation()
            }
            .onDisappear {
                stopAnimation()
            }
    }

    // 🔄 Random icon switch loop
    private func startAnimation() {
        animate = true

        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            currentIcon = icons.randomElement()!
        }
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }
}

struct ConditionalSymbolEffect: ViewModifier {
    let currentIcon: String
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.symbolEffect(.bounce, options: .repeat(.continuous))
        } else {
            // Continuous bounce is only available from iOS 18.
            // This will fall back to a one-time bounce on earlier versions.
            content.symbolEffect(.bounce)
        }
    }
}
