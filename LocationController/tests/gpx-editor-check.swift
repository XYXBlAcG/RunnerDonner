import Foundation

@main struct GPXEditorChecks {
    @MainActor static func main() throws {
        let xml = """
        <gpx xmlns="http://www.topografix.com/GPX/1/1" xmlns:test="urn:test" version="1.1" creator="fixture"><metadata><name>Original</name><bounds minlat="0" maxlat="0" minlon="0" maxlon="0"/></metadata><trk><name>Loop</name><trkseg><trkpt lat="32" lon="118"><ele>20</ele><time>2026-10-24T00:00:00Z</time><extensions><test:value>retained</test:value></extensions></trkpt><trkpt lat="32.001" lon="118.001"><ele>21</ele></trkpt><trkpt lat="32.002" lon="118"/><trkpt lat="32" lon="118"/></trkseg><extensions><test:track>yes</test:track></extensions></trk></gpx>
        """
        let original = try GPXDocument(data: Data(xml.utf8))
        let model = GPXEditorModel(document: original)
        let first = model.document.vertices[0].id
        model.move(first, to: Coordinate(latitude: 32.00001, longitude: 118))
        precondition(model.document.track.points.first == model.document.track.points.last)
        model.undo()
        precondition(model.document.track.points == original.track.points)
        model.redo()
        precondition(model.document.track.points != original.track.points)
        let saved = try model.document.encoded()
        let parsed = try GPXDocument(data: saved)
        precondition(parsed.track.points == model.document.track.points)
        let result = String(decoding: saved, as: UTF8.self)
        for text in ["Original", "2026-10-24T00:00:00Z", "retained", "test:track", "<ele>20</ele>"] {
            precondition(result.contains(text), text)
        }
        model.selected = model.document.vertices[1].id
        model.insert(Coordinate(latitude: 32.0012, longitude: 118.0012))
        precondition(model.document.vertices.count == 5)
        precondition(model.document.vertices[2].coordinate.latitude == 32.0012)
        model.deleteSelection()
        precondition(model.document.vertices.count == 4)
        model.selected = first
        model.deleteSelection()
        precondition(model.document.track.points.first == model.document.track.points.last)
        precondition(model.document.vertices.last?.sourceIndex == nil)
        model.undo()
        precondition(model.document.vertices.count == 4)
        let a = try original.perturbed(radius: 2, seed: 42)
        let b = try original.perturbed(radius: 2, seed: 42)
        let c = try original.perturbed(radius: 2, seed: 43)
        precondition(a.track.points == b.track.points && a.track.points != c.track.points)
        precondition(a.track.points.first == a.track.points.last)
        for (p, q) in zip(original.track.points, a.track.points) {
            precondition(Track(points: [p, q]).meters <= 2.01)
        }
        model.previewPerturbation(radius: 1, seed: 1)
        let preview = model.visibleDocument.track.points
        model.previewPerturbation(radius: 1, seed: 2)
        precondition(model.document.track.points != preview)
        model.cancelPreview()
        precondition(model.visibleDocument.track.points == model.document.track.points)
        model.previewPerturbation(radius: 1, seed: 1)
        model.applyPreview()
        precondition(model.document.track.points == preview)
        model.undo()
        precondition(model.document.track.points != preview)
        let empty = GPXEditorModel(document: GPXDocument())
        empty.insert(Coordinate(latitude: 32, longitude: 118))
        empty.insert(Coordinate(latitude: 32.001, longitude: 118))
        let created = try GPXDocument(data: empty.document.encoded())
        precondition(created.vertices.count == 2)
        do { _ = try GPXDocument().encoded(); preconditionFailure("Empty saved") } catch {}
        do { _ = try GPXDocument(data: Data("<gpx><trk><trkseg><trkpt lat='nan' lon='0'/></trkseg></trk></gpx>".utf8)); preconditionFailure("Invalid parsed") } catch {}
        do { _ = try original.perturbed(radius: .infinity, seed: 1); preconditionFailure("Invalid radius") } catch {}
        for name in try FileManager.default.contentsOfDirectory(atPath: "gpx-variants") where name.hasSuffix(".gpx") {
            let url = URL(fileURLWithPath: "gpx-variants").appendingPathComponent(name)
            let doc = try GPXDocument(data: Data(contentsOf: url))
            let shuffled = try doc.perturbed(radius: 1, seed: 23)
            let roundtrip = try GPXDocument(data: shuffled.encoded())
            precondition(roundtrip.vertices.count == 512 && roundtrip.track.meters > 2400)
            precondition(roundtrip.track.points.first == roundtrip.track.points.last)
        }
        let boundsXML = try XMLDocument(data: saved)
        let bounds = try boundsXML.nodes(forXPath: "//*[local-name()='bounds']").first as! XMLElement
        precondition(Double(bounds.attribute(forName: "maxlat")!.stringValue!) == 32.002)
        let prefixed = Data("<g:gpx xmlns:g='http://www.topografix.com/GPX/1/1' version='1.1'><g:rte><g:name>route</g:name><g:rtept lat='32' lon='118'/><g:rtept lat='32.001' lon='118'/></g:rte></g:gpx>".utf8)
        let routeModel = GPXEditorModel(document: try GPXDocument(data: prefixed))
        routeModel.insert(Coordinate(latitude: 32.002, longitude: 118))
        let routeSaved = try routeModel.document.encoded()
        let routeRead = try GPXDocument(data: routeSaved)
        precondition(routeRead.vertices.count == 3)
        let routeXML = try XMLDocument(data: routeSaved)
        let routeNodes = try routeXML.nodes(forXPath: "//*[local-name()='rtept']")
        precondition(routeNodes.allSatisfy { $0.uri == "http://www.topografix.com/GPX/1/1" })
        let history = GPXEditorModel(document: original)
        for index in 0...101 { history.move(first, to: Coordinate(latitude: 32 + Double(index + 1) * 0.000001, longitude: 118)) }
        while history.canUndo { history.undo() }
        precondition(history.hasChanges)
        var dense = GPXDocument()
        dense.vertices = (0...100).map { GPXVertex(coordinate: Coordinate(latitude: 32 + Double($0) * 0.00001, longitude: 118)) }
        let smooth = try dense.perturbed(radius: 2, seed: 500)
        precondition(smooth.track.points.first == dense.track.points.first && smooth.track.points.last == dense.track.points.last)
        for index in 1..<dense.vertices.count {
            let before = dense.vertices[index - 1].coordinate.distance(to: dense.vertices[index].coordinate)
            let after = smooth.vertices[index - 1].coordinate.distance(to: smooth.vertices[index].coordinate)
            precondition(abs(before - after) < 0.2)
        }
        do {
            _ = try GPXDocument(data: Data("<gpx><trk><trkseg><trkpt lat='32' lon='118'/><trkpt lat='33' lon='118'/></trkseg><trkseg><trkpt lat='34' lon='118'/></trkseg></trk></gpx>".utf8))
            preconditionFailure("Multiple segments accepted")
        } catch {}
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gpx")
        defer { try? FileManager.default.removeItem(at: temp) }
        try routeSaved.write(to: temp, options: .atomic)
        let disk = try GPXDocument(data: Data(contentsOf: temp))
        precondition(disk.track.points == routeRead.track.points)
        print("PASS: GPX XML preservation, edits, history, perturbation and real file roundtrips")
    }
}
