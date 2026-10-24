import Foundation

struct GPXVertex: Identifiable, Equatable {
    let id: UUID
    var coordinate: Coordinate
    let sourceIndex: Int?

    init(coordinate: Coordinate, sourceIndex: Int? = nil) {
        id = UUID()
        self.coordinate = coordinate
        self.sourceIndex = sourceIndex
    }
}

struct GPXDocument {
    private let source: Data
    var vertices: [GPXVertex]
    var track: Track { Track(points: vertices.map(\.coordinate)) }
    var isClosed: Bool { vertices.count > 2 && vertices.first?.coordinate == vertices.last?.coordinate }

    init() {
        source = Data("<gpx xmlns=\"http://www.topografix.com/GPX/1/1\" version=\"1.1\" creator=\"RunnerDonner\"><trk><trkseg/></trk></gpx>".utf8)
        vertices = []
    }

    init(data: Data) throws {
        let xml = try XMLDocument(data: data, options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever])
        guard xml.dtd == nil, let root = xml.rootElement(), root.localName == "gpx" else {
            throw Failure("GPX 格式无效或包含不支持的文档类型。")
        }
        let containers = Self.containers(in: root)
        let populated = containers.filter { !Self.points(in: $0).isEmpty }
        guard populated.count == 1, let container = populated.first else {
            throw Failure("请选择只包含一条连续轨迹的 GPX；多段文件请先合并。")
        }
        let elements = Self.points(in: container)
        guard (2...20000).contains(elements.count) else { throw Failure("GPX 需要 2 至 20000 个轨迹点。") }
        vertices = try elements.enumerated().map { index, element in
            guard let lat = element.attribute(forName: "lat")?.stringValue.flatMap(Double.init),
                  let lon = element.attribute(forName: "lon")?.stringValue.flatMap(Double.init),
                  lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180 else {
                throw Failure("GPX 中含有无效坐标。")
            }
            return GPXVertex(coordinate: Coordinate(latitude: lat, longitude: lon), sourceIndex: index)
        }
        source = data
    }

    private static func containers(in root: XMLElement) -> [XMLElement] {
        (root.children ?? []).compactMap { $0 as? XMLElement }.flatMap { element -> [XMLElement] in
            guard element.uri == root.uri else { return [] }
            if element.localName == "rte" { return [element] }
            guard element.localName == "trk" else { return [] }
            return (element.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.localName == "trkseg" && $0.uri == root.uri }
        }
    }

    private static func points(in container: XMLElement) -> [XMLElement] {
        let name = container.localName == "rte" ? "rtept" : "trkpt"
        return (container.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.localName == name && $0.uri == container.uri }
    }

    func encoded() throws -> Data {
        guard (2...20000).contains(vertices.count), track.meters >= 1 else {
            throw Failure("保存需要 2 至 20000 个点，且路线长度至少为 1 米。")
        }
        guard vertices.allSatisfy({ $0.coordinate.isValid }) else { throw Failure("路线包含无效坐标。") }
        let xml = try XMLDocument(data: source, options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever])
        guard let root = xml.rootElement() else { throw Failure("GPX 缺少根元素。") }
        let containers = Self.containers(in: root)
        guard let container = containers.first(where: { !Self.points(in: $0).isEmpty }) ?? containers.first else {
            throw Failure("GPX 缺少轨迹容器。")
        }
        let originals = Self.points(in: container)
        let insertion = originals.first?.index ?? container.childCount
        let prefix = container.prefix.flatMap { $0.isEmpty ? nil : $0 + ":" } ?? ""
        let name = prefix + (container.localName == "rte" ? "rtept" : "trkpt")
        let updated = vertices.map { vertex -> XMLElement in
            let node: XMLElement
            if let index = vertex.sourceIndex, originals.indices.contains(index) {
                node = originals[index].copy() as! XMLElement
            } else {
                node = XMLElement(name: name, uri: container.uri)
            }
            for (key, value) in [("lat", vertex.coordinate.latitude), ("lon", vertex.coordinate.longitude)] {
                node.removeAttribute(forName: key)
                node.addAttribute(XMLNode.attribute(withName: key, stringValue: String(value)) as! XMLNode)
            }
            return node
        }
        for element in originals { element.detach() }
        for (offset, element) in updated.enumerated() { container.insertChild(element, at: insertion + offset) }
        let bounds = try root.nodes(forXPath: "./*[local-name()='bounds'] | ./*[local-name()='metadata']/*[local-name()='bounds']")
        for case let element as XMLElement in bounds {
            let points = track.points
            let values = [("minlat", points.map(\.latitude).min()!), ("maxlat", points.map(\.latitude).max()!),
                          ("minlon", points.map(\.longitude).min()!), ("maxlon", points.map(\.longitude).max()!)]
            for (key, value) in values {
                element.removeAttribute(forName: key)
                element.addAttribute(XMLNode.attribute(withName: key, stringValue: String(value)) as! XMLNode)
            }
        }
        return xml.xmlData(options: [.nodePrettyPrint])
    }

    func perturbed(radius: Double, seed: UInt64) throws -> GPXDocument {
        guard radius.isFinite, (0...10).contains(radius) else { throw Failure("扰动幅度应为 0 至 10 米。") }
        guard vertices.count >= 2, track.meters >= 1 else { throw Failure("请先绘制至少 1 米的路线。") }
        if radius == 0 { return self }
        var generator = GPXRandom(seed: seed)
        let total = track.meters
        let intervals = max(2, min(20000, Int(ceil(total / 40))))
        var offsets = (0...intervals).map { _ -> (Double, Double) in
            let angle = generator.unit() * 2 * Double.pi
            let length = sqrt(generator.unit()) * radius
            return (cos(angle) * length, sin(angle) * length)
        }
        if isClosed { offsets[intervals] = offsets[0] }
        else { offsets[0] = (0, 0); offsets[intervals] = (0, 0) }
        var output = self
        var meters = 0.0
        for index in vertices.indices {
            if index > 0 { meters += vertices[index - 1].coordinate.distance(to: vertices[index].coordinate) }
            let phase = min(Double(intervals), meters / total * Double(intervals))
            let slot = min(intervals - 1, Int(phase))
            let t = phase - Double(slot)
            let weight = t * t * (3 - 2 * t)
            let x = offsets[slot].0 * (1 - weight) + offsets[slot + 1].0 * weight
            let y = offsets[slot].1 * (1 - weight) + offsets[slot + 1].1 * weight
            let distance = hypot(x, y) / 6371008.8
            let bearing = atan2(x, y)
            let lat = vertices[index].coordinate.latitude * .pi / 180
            let lon = vertices[index].coordinate.longitude * .pi / 180
            let shiftedLat = asin(max(-1, min(1, sin(lat) * cos(distance) + cos(lat) * sin(distance) * cos(bearing))))
            let shiftedLon = lon + atan2(sin(bearing) * sin(distance) * cos(lat), cos(distance) - sin(lat) * sin(shiftedLat))
            output.vertices[index].coordinate = Coordinate(latitude: shiftedLat * 180 / .pi, longitude: (shiftedLon * 180 / .pi + 540).truncatingRemainder(dividingBy: 360) - 180)
        }
        if isClosed { output.vertices[vertices.count - 1].coordinate = output.vertices[0].coordinate }
        else {
            output.vertices[0].coordinate = vertices[0].coordinate
            output.vertices[vertices.count - 1].coordinate = vertices[vertices.count - 1].coordinate
        }
        return output
    }
}

private struct GPXRandom {
    var seed: UInt64

    mutating func unit() -> Double {
        seed &+= 0x9E3779B97F4A7C15
        var value = seed
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return Double((value ^ (value >> 31)) >> 11) / 9007199254740992
    }
}
