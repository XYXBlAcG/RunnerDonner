import MapKit

struct MapCoordinate: Equatable {
    private let latitude: Double
    private let longitude: Double

    init(wgs84 point: Coordinate) {
        let converted = LocationTransform.wgs2gcj(wgsLat: point.latitude, wgsLng: point.longitude)
        latitude = converted.gcjLat
        longitude = converted.gcjLng
    }

    init(mapKit point: CLLocationCoordinate2D) {
        latitude = point.latitude
        longitude = point.longitude
    }

    var mapKit: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var wgs84: Coordinate {
        let converted = LocationTransform.gcj2wgs_exact(gcjLat: latitude, gcjLng: longitude)
        return Coordinate(latitude: converted.wgsLat, longitude: converted.wgsLng)
    }
}

enum MapPresentation {
    static func configure(_ map: MKMapView) {
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        map.showsZoomControls = true
        map.showsUserLocation = false
    }
}
