//
//  MapRouteAnimationView.swift
//  TravelAssist
//
//  Created by Rajesh Mani on 12/04/26.
//


import SwiftUI

struct MapRouteAnimationView: View {

    @State private var progress: CGFloat = 0
    @State private var showPin = false

    var body: some View {
        ZStack {

            // 🟠 Route Path
            RouteShape()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [Color.orange, Color.red],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(height: 200)

            // 🔵 Moving Dot
            MovingDot(progress: progress)

            // 📍 Destination Pin
            if showPin {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.red)
                    .scaleEffect(showPin ? 1 : 0.5)
                    .opacity(showPin ? 1 : 0)
                    .offset(x: 120, y: -20)
                    .animation(.spring(response: 0.5), value: showPin)
            }
        }
        .onAppear {
            animateRoute()
        }
    }

    private func animateRoute() {
        withAnimation(.easeInOut(duration: 2.5)) {
            progress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            showPin = true
        }
    }
}


#Preview {
    MapRouteAnimationView()
}
