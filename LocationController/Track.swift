import Foundation

extension Coordinate {
    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
    }

    func distance(to other: Coordinate) -> Double {
        let x = latitude * Double.pi / 180
        let y = other.latitude * Double.pi / 180
        let latTerm = sin((y - x) / 2)
        let lonTerm = sin((other.longitude - longitude) * Double.pi / 360)
        let h = latTerm * latTerm + cos(x) * cos(y) * lonTerm * lonTerm
        return 12742017.6 * asin(sqrt(min(1, h)))
    }
}

struct Track {
    let points: [Coordinate]
    var meters: Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }
}
