import Foundation
import Combine

@MainActor final class GPXEditorModel: ObservableObject {
    @Published private(set) var document: GPXDocument
    @Published private(set) var preview: GPXDocument?
    @Published var selected: UUID?
    @Published var message = ""
    private let initialVertices: [GPXVertex]
    private var past: [GPXDocument] = []
    private var future: [GPXDocument] = []
    var visibleDocument: GPXDocument { preview ?? document }
    var canUndo: Bool { !past.isEmpty && preview == nil }
    var canRedo: Bool { !future.isEmpty && preview == nil }
    var hasChanges: Bool { document.vertices != initialVertices || preview != nil }

    init(document: GPXDocument) { self.document = document; initialVertices = document.vertices }

    private func commit(_ next: GPXDocument) {
        past.append(document)
        if past.count > 100 { past.removeFirst() }
        future.removeAll()
        preview = nil
        document = next
    }

    func insert(_ point: Coordinate) {
        guard point.isValid, preview == nil, document.vertices.count < 20000 else { return }
        var next = document
        let selectedIndex = selected.flatMap { id in next.vertices.firstIndex { $0.id == id } }
        let index = selectedIndex.map { min($0 + 1, next.isClosed ? next.vertices.count - 1 : next.vertices.count) }
            ?? (next.isClosed ? next.vertices.count - 1 : next.vertices.count)
        let vertex = GPXVertex(coordinate: point)
        next.vertices.insert(vertex, at: max(0, index))
        commit(next)
        selected = vertex.id
    }

    func move(_ id: UUID, to point: Coordinate) {
        guard point.isValid, preview == nil, let index = document.vertices.firstIndex(where: { $0.id == id }), document.vertices[index].coordinate != point else { return }
        var next = document
        if document.isClosed && (index == 0 || index == document.vertices.count - 1) {
            next.vertices[0].coordinate = point
            next.vertices[next.vertices.count - 1].coordinate = point
        } else { next.vertices[index].coordinate = point }
        commit(next)
        selected = id
    }

    func deleteSelection() {
        guard preview == nil, let selected = selected, let index = document.vertices.firstIndex(where: { $0.id == selected }) else { return }
        var next = document
        if document.isClosed && (index == 0 || index == document.vertices.count - 1) {
            next.vertices.removeLast()
            next.vertices.removeFirst()
            if next.vertices.count >= 2 {
                next.vertices.append(GPXVertex(coordinate: next.vertices[0].coordinate))
            }
        } else { next.vertices.remove(at: index) }
        commit(next)
        self.selected = nil
    }

    func undo() {
        guard canUndo, let previous = past.popLast() else { return }
        future.append(document)
        document = previous
        selected = nil
    }

    func redo() {
        guard canRedo, let next = future.popLast() else { return }
        past.append(document)
        document = next
        selected = nil
    }

    func previewPerturbation(radius: Double, seed: UInt64) {
        do { preview = try document.perturbed(radius: radius, seed: seed); selected = nil; message = "" }
        catch { message = error.localizedDescription }
    }

    func applyPreview() {
        if let preview = preview { commit(preview) }
    }

    func cancelPreview() { preview = nil }
}
