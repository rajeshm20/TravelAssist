import Combine
import CoreLocation
import Foundation

protocol LocationService {
    var currentLocation: CLLocation? { get }
    var authorizationStatus: CLAuthorizationStatus { get }
    var authorizationStatusPublisher: AnyPublisher<CLAuthorizationStatus, Never> { get }
    var locationPublisher: AnyPublisher<CLLocation, Never> { get }

    func requestPermissionsIfNeeded()
    func requestOneTimeLocation()
    func startStandardUpdates()
    func stopStandardUpdates()
    func startSignificantUpdates()
    func stopUpdates()
    func startMonitoringDestination(coordinate: CLLocationCoordinate2D, radius: CLLocationDistance)
    func stopMonitoringDestination()
}
