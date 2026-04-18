//
//  RouteShape.swift
//  TravelAssist
//
//  Created by Rajesh Mani on 12/04/26.
//
import SwiftUI
import Foundation


struct RouteShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: 20, y: rect.height * 0.7))

        path.addCurve(
            to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.3),
            control1: CGPoint(x: rect.width * 0.2, y: rect.height),
            control2: CGPoint(x: rect.width * 0.3, y: 0)
        )

        path.addCurve(
            to: CGPoint(x: rect.width - 20, y: rect.height * 0.5),
            control1: CGPoint(x: rect.width * 0.7, y: rect.height * 0.6),
            control2: CGPoint(x: rect.width * 0.8, y: rect.height * 0.2)
        )

        return path
    }
}
