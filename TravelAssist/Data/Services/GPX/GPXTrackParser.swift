import CoreLocation
import Foundation

struct GPXTrack {
    let coordinates: [CLLocationCoordinate2D]
}

enum GPXTrackParser {
    static func parse(data: Data) -> GPXTrack {
        let parser = XMLParser(data: data)
        let delegate = GPXXMLDelegate()
        parser.delegate = delegate
        parser.parse()
        return GPXTrack(coordinates: delegate.coordinates)
    }
}

private final class GPXXMLDelegate: NSObject, XMLParserDelegate {
    var coordinates: [CLLocationCoordinate2D] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        // Track points (trkpt) or route points (rtept)
        guard elementName == "trkpt" || elementName == "rtept" else { return }
        guard let latString = attributeDict["lat"],
              let lonString = attributeDict["lon"],
              let lat = Double(latString),
              let lon = Double(lonString) else {
            return
        }
        coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }
}

