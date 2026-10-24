import Foundation

@main struct DeviceProtocolChecks {
    static func main() throws {
        precondition(Capabilities().canConnect)
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        let snapshots = try JSONDecoder().decode([SessionSnapshot].self, from: Data(contentsOf: fixture))
        guard let fixed = snapshots.first(where: { $0.state == .fixed }),
              let paused = snapshots.first(where: { $0.state == .paused }),
              let resumed = snapshots.last(where: { $0.state == .running }),
              let cleared = snapshots.last else { preconditionFailure("Incomplete fixture") }
        precondition(fixed.position == Coordinate(latitude: 32, longitude: 118))
        precondition(!fixed.hasRoute && fixed.meters == 0 && fixed.total == 0)
        precondition(paused.capabilities.canResume && paused.capabilities.canEditPace)
        precondition(!paused.capabilities.canChooseTrack && !paused.capabilities.canStart)
        precondition(resumed.meters > paused.meters && resumed.pace! >= 285 && resumed.pace! <= 315)
        precondition(cleared.state == .ready && cleared.position == nil && cleared.total == 0)
        let directory = URL(fileURLWithPath: CommandLine.arguments[2])
        let tracks = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "gpx" }
        precondition(tracks.count == 1)
        for file in tracks {
            let track = try GPXDocument(data: Data(contentsOf: file)).track
            precondition(track.points.count == 5 && track.meters > 2400)
            precondition(track.points.first == track.points.last)
        }
        print("PASS: native decoding of real session snapshots and GPX origin parsing")
    }
}
