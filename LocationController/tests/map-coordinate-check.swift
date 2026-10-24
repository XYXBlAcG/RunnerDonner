import Foundation
import CoreLocation

@main struct MapCoordinateChecks {
    @MainActor static func main() throws {
        let fixtures = [
            (31.1774276, 121.5272106, 31.17530398364597, 121.531541859215),
            (22.543847, 113.912316, 22.540796131694766, 113.9171764808363),
            (39.911954, 116.377817, 39.91334545536069, 116.38404722455657)
        ]
        for (lat, lon, displayLat, displayLon) in fixtures {
            let point = Coordinate(latitude: lat, longitude: lon)
            let projected = MapCoordinate(wgs84: point)
            precondition(abs(projected.mapKit.latitude - displayLat) < 0.00001)
            precondition(abs(projected.mapKit.longitude - displayLon) < 0.00001)
            precondition(projected.wgs84.distance(to: point) < 0.001)
        }
        for point in [Coordinate(latitude: 37.7749, longitude: -122.4194), Coordinate(latitude: 35.6762, longitude: 139.6503), Coordinate(latitude: -33.8688, longitude: 151.2093)] {
            let display = MapCoordinate(wgs84: point)
            precondition(display.mapKit.latitude == point.latitude && display.mapKit.longitude == point.longitude)
            precondition(display.wgs84 == point)
        }
        let origin = Coordinate(latitude: 32.0594066195, longitude: 118.7732314197)
        let projected = MapCoordinate(wgs84: origin)
        precondition(projected.mapKit.longitude > origin.longitude && projected.mapKit.latitude < origin.latitude)
        let offset = origin.distance(to: Coordinate(latitude: projected.mapKit.latitude, longitude: projected.mapKit.longitude))
        precondition(offset > 300 && offset < 800)
        precondition(MapCoordinate(mapKit: projected.mapKit).wgs84.distance(to: origin) < 0.001)
        for name in try FileManager.default.contentsOfDirectory(atPath: "LocationController/tests/fixtures") where name.hasSuffix(".gpx") {
            let url = URL(fileURLWithPath: "LocationController/tests/fixtures").appendingPathComponent(name)
            let bytes = try Data(contentsOf: url)
            let document = try GPXDocument(data: bytes)
            let model = GPXEditorModel(document: document)
            let points = model.document.track.points
            let displayed = points.map { MapCoordinate(wgs84: $0) }
            for (point, map) in zip(points, displayed) { precondition(map.wgs84.distance(to: point) < 0.001) }
            let afterDisplay = try GPXDocument(data: model.document.encoded())
            precondition(afterDisplay.track.points == points && !model.hasChanges)
            let unchanged = try Data(contentsOf: url)
            precondition(unchanged == bytes)
            let id = model.document.vertices[0].id
            let target = MapCoordinate(mapKit: CLLocationCoordinate2D(latitude: displayed[0].mapKit.latitude + 0.00001, longitude: displayed[0].mapKit.longitude)).wgs84
            model.move(id, to: target)
            precondition(model.document.isClosed)
            precondition(model.document.vertices[0].coordinate.distance(to: points[0]) > 0.5)
            precondition(model.document.vertices[0].coordinate.distance(to: points[0]) < 2)
            let reopened = try GPXDocument(data: model.document.encoded())
            precondition(reopened.track.points == model.document.track.points)
            precondition(MapCoordinate(wgs84: reopened.vertices[0].coordinate).mapKit.latitude.distance(to: displayed[0].mapKit.latitude + 0.00001).magnitude < 0.00000001)
            model.undo()
            precondition(model.document.track.points == points)
        }
        print("PASS: reference conversions, submillimeter roundtrips, overseas coordinates, unchanged GPX and map edits")
    }
}
