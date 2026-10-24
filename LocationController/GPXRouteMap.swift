import SwiftUI
import MapKit
import AppKit

struct GPXRouteMap: NSViewRepresentable {
    @ObservedObject var model: GPXEditorModel
    let center: Coordinate?
    let adding: Bool
    let fitRequest: Int

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        MapPresentation.configure(map)
        map.delegate = context.coordinator
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        click.buttonMask = 1
        map.addGestureRecognizer(click)
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.adding = adding
        let document = model.visibleDocument
        let coordinates = document.track.points
        if coordinator.coordinates != coordinates {
            coordinator.coordinates = coordinates
            map.removeOverlays(map.overlays)
            if coordinates.count >= 2 {
                var points = coordinates.map { MapCoordinate(wgs84: $0).mapKit }
                map.addOverlay(MKPolyline(coordinates: &points, count: points.count))
            }
        }
        if coordinator.fitRequest != fitRequest {
            coordinator.fitRequest = fitRequest
            if let overlay = map.overlays.first {
                map.setVisibleMapRect(overlay.boundingMapRect, edgePadding: NSEdgeInsets(top: 45, left: 45, bottom: 45, right: 45), animated: false)
            } else if let first = coordinates.first {
                map.setRegion(MKCoordinateRegion(center: MapCoordinate(wgs84: first).mapKit, latitudinalMeters: 700, longitudinalMeters: 700), animated: false)
            }
        }
        if center != coordinator.center {
            coordinator.center = center
            if let center = center {
                map.setRegion(MKCoordinateRegion(center: MapCoordinate(wgs84: center).mapKit, latitudinalMeters: 700, longitudinalMeters: 700), animated: false)
            }
        }
        coordinator.refreshHandles(map)
    }

    final class VertexAnnotation: NSObject, MKAnnotation {
        let id: UUID
        @objc dynamic var coordinate: CLLocationCoordinate2D
        init(vertex: GPXVertex) { id = vertex.id; coordinate = MapCoordinate(wgs84: vertex.coordinate).mapKit }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let model: GPXEditorModel
        var coordinates: [Coordinate] = []
        var center: Coordinate?
        var adding = false
        var fitRequest = -1
        var dragging = false

        init(model: GPXEditorModel) { self.model = model }

        func refreshHandles(_ map: MKMapView) {
            guard !dragging else { return }
            guard model.preview == nil else { map.removeAnnotations(map.annotations); return }
            var visible = model.document.vertices.filter { map.visibleMapRect.contains(MKMapPoint(MapCoordinate(wgs84: $0.coordinate).mapKit)) }
            if model.document.isClosed { visible.removeAll { $0.id == model.document.vertices.last?.id } }
            let strideSize = max(1, Int(ceil(Double(visible.count) / 400)))
            let vertices = visible.enumerated().filter {
                $0.offset % strideSize == 0 || $0.element.id == model.selected || $0.element.id == model.document.vertices.first?.id || $0.element.id == model.document.vertices.last?.id
            }.map(\.element)
            let desired = Set(vertices.map(\.id))
            let existing = Dictionary(uniqueKeysWithValues: map.annotations.compactMap { $0 as? VertexAnnotation }.map { ($0.id, $0) })
            map.removeAnnotations(existing.values.filter { !desired.contains($0.id) })
            for vertex in vertices {
                if let annotation = existing[vertex.id] {
                    if MapCoordinate(mapKit: annotation.coordinate) != MapCoordinate(wgs84: vertex.coordinate) { annotation.coordinate = MapCoordinate(wgs84: vertex.coordinate).mapKit }
                    if let view = map.view(for: annotation) { style(view, point: annotation) }
                } else { map.addAnnotation(VertexAnnotation(vertex: vertex)) }
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) { refreshHandles(mapView) }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = model.preview == nil ? .systemBlue : .systemOrange
            renderer.lineWidth = 3
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let point = annotation as? VertexAnnotation else { return nil }
            let view = MKAnnotationView(annotation: point, reuseIdentifier: nil)
            style(view, point: point)
            view.isDraggable = true
            view.canShowCallout = false
            return view
        }

        func style(_ view: MKAnnotationView, point: VertexAnnotation) {
            let selected = point.id == model.selected
            let first = point.id == model.document.vertices.first?.id
            let last = point.id == model.document.vertices.last?.id
            let label = first ? (model.document.isClosed ? "起终" : "起") : last ? "终" : ""
            let size: CGFloat = label.isEmpty ? (selected ? 16 : 10) : 28
            view.image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
                (selected ? NSColor.systemOrange : first ? .systemGreen : last ? .systemRed : .white).setFill()
                let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
                path.fill()
                NSColor.systemBlue.setStroke()
                path.lineWidth = 2
                path.stroke()
                if !label.isEmpty {
                    let text = NSAttributedString(string: label, attributes: [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.white])
                    let bounds = text.size()
                    text.draw(at: NSPoint(x: (size - bounds.width) / 2, y: (size - bounds.height) / 2))
                }
                return true
            }
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let point = view.annotation as? VertexAnnotation { model.selected = point.id }
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            switch newState {
            case .starting: dragging = true; view.dragState = .dragging
            case .ending:
                if let point = view.annotation as? VertexAnnotation { model.move(point.id, to: MapCoordinate(mapKit: point.coordinate).wgs84) }
                dragging = false
                view.dragState = .none
                refreshHandles(mapView)
            case .canceling:
                dragging = false
                view.dragState = .none
                refreshHandles(mapView)
            default: break
            }
        }

        @objc func clicked(_ gesture: NSClickGestureRecognizer) {
            guard !dragging, model.preview == nil, let map = gesture.view as? MKMapView else { return }
            let location = gesture.location(in: map)
            let nearest = map.annotations.compactMap { $0 as? VertexAnnotation }.min { a, b in
                let p = map.convert(a.coordinate, toPointTo: map)
                let q = map.convert(b.coordinate, toPointTo: map)
                return hypot(p.x - location.x, p.y - location.y) < hypot(q.x - location.x, q.y - location.y)
            }
            if let nearest = nearest {
                let p = map.convert(nearest.coordinate, toPointTo: map)
                if hypot(p.x - location.x, p.y - location.y) <= 12 { model.selected = nearest.id; return }
            }
            if adding { model.insert(MapCoordinate(mapKit: map.convert(location, toCoordinateFrom: map)).wgs84) }
            else { model.selected = nil }
        }
    }
}
