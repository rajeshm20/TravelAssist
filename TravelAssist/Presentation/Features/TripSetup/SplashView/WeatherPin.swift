//
//  WeatherPin.swift
//  TravelAssist
//
//  Created by Rajesh Mani on 12/04/26.
//
import Foundation

struct WeatherPin: Identifiable {
    let id = UUID()
    var position: CGPoint
    var opacity: Double = 0
    var scale: CGFloat = 0.5
}
