//
//  MovingDot.swift
//  TravelAssist
//
//  Created by Rajesh Mani on 12/04/26.
//
import SwiftUI
import Foundation

struct MovingDot: View {

    var progress: CGFloat

    var body: some View {
        GeometryReader { geo in
            let path = RouteShape().path(in: geo.frame(in: .local))
            let trimmed = path.trimmedPath(from: 0, to: progress)

            let point = trimmed.currentPoint ?? CGPoint(x: 0, y: 0)

            Circle()
                .fill(Color.blue)
                .frame(width: 14, height: 14)
                .position(point)
        }
    }
}

#Preview {
        MovingDot(progress: 0.6)
}
