import CoreLocation
import Foundation

protocol CurrentLocationProvider {
    var currentCoordinate: CLLocationCoordinate2D? { get }
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestAccessIfNeeded()
    func startSampling()
}
