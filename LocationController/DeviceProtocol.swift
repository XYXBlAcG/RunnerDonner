import Foundation

enum DeviceCommand: String, Codable {
    case devices
    case connect
    case locate
    case start
    case pause
    case resume
    case restart
    case clear
    case status
    case shutdown
}

enum SessionState: String, Codable {
    case disconnected
    case connecting
    case ready
    case fixed
    case running
    case paused
    case completed
    case reconnecting
    case interrupted
}

struct Coordinate: Codable, Equatable {
    var latitude: Double
    var longitude: Double
}

struct Capabilities: Codable {
    var canConnect: Bool = true
    var canStart: Bool = false
    var canLocate: Bool = false
    var canPause: Bool = false
    var canResume: Bool = false
    var canRestart: Bool = false
    var canClear: Bool = false
    var canChooseTrack: Bool = true
    var canEditPace: Bool = true
    var needsWakeLock: Bool = false
}

struct SessionSnapshot: Codable {
    var state: SessionState
    var capabilities: Capabilities
    var meters: Double
    var total: Double
    var pace: Double?
    var position: Coordinate?
    var reconnects: Int
    var hasRoute: Bool
}
