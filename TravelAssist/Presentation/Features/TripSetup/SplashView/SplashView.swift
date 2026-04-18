//
//  SplashView.swift
//  TravelAssist
//
//  Created by Rajesh Mani on 12/04/26.
//


import SwiftUI
import Foundation

struct SplashView: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "#FF9933"),
                    Color(hex: "#FF6A00")
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {

                // Animation
                AnimatedTransportIcon()

                // Title
                Text("TravelAssist")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .offset(y: animate ? 0 : 40)
                    .opacity(animate ? 1 : 0)
                    .animation(.easeOut(duration: 0.8).delay(0.3), value: animate)

                // Subtitle
                Text("Your journey begins here")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
                    .offset(y: animate ? 0 : 40)
                    .opacity(animate ? 1 : 0)
                    .animation(.easeOut(duration: 0.8).delay(0.5), value: animate)
            }
            // ✨ Subtle floating effect
            .offset(y: animate ? -10 : 0)
            .animation(
                .easeInOut(duration: 2)
                .repeatForever(autoreverses: true)
                .delay(1),
                value: animate
            )
        }
        .onAppear {
            animate = true
        }
    }
}

#Preview {
    SplashView()
}
