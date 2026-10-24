import SwiftUI
import MapKit
import AppKit

struct MapPointPicker: View {
    let onConfirm: (Coordinate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var center: Coordinate?
    @State private var selection: Coordinate?

    init(initialCenter: Coordinate?, onConfirm: @escaping (Coordinate) -> Void) {
        _center = State(initialValue: initialCenter)
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MapLocationSearch(center: center) { point in center = point; selection = nil }
            MapCanvas(center: center, selection: $selection).frame(height: 340)
            HStack {
                Text(selection == nil ? "点击地图选择位置" : "已选定位置").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }
                Button("定位到此处") {
                    if let selection = selection { onConfirm(selection); dismiss() }
                }.buttonStyle(.borderedProminent).disabled(selection == nil)
            }
        }.padding(20).frame(width: 650)
    }
}

struct MapLocationSearch: View {
    let center: Coordinate?
    let onSelect: (Coordinate) -> Void
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var message = ""
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("搜索地点", text: $query).onSubmit { search() }
                Button("搜索") { search() }.disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !results.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                            Button {
                                onSelect(MapCoordinate(mapKit: item.placemark.coordinate).wgs84)
                                results = []
                                message = ""
                            } label: {
                                Text(item.name ?? item.placemark.title ?? "地点").frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxHeight: 80)
            }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.onDisappear { searchTask?.cancel() }
    }

    func search() {
        guard !searching else { return }
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searching = true
        searchTask = Task { @MainActor in
            defer { searching = false }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            if let center = center {
                request.region = MKCoordinateRegion(center: MapCoordinate(wgs84: center).mapKit, latitudinalMeters: 30000, longitudinalMeters: 30000)
            }
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                results = response.mapItems
                message = results.isEmpty ? "未找到地点" : "请选择搜索结果，再在地图上点选"
            } catch {
                guard !Task.isCancelled else { return }
                message = "搜索失败，请检查网络后重试"
            }
        }
    }
}

struct MapCanvas: NSViewRepresentable {
    let center: Coordinate?
    @Binding var selection: Coordinate?

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        MapPresentation.configure(map)
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.selectPoint(_:)))
        click.buttonMask = 1
        map.addGestureRecognizer(click)
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        context.coordinator.selection = $selection
        if center != context.coordinator.center {
            context.coordinator.center = center
            if let center = center {
                map.setRegion(MKCoordinateRegion(center: MapCoordinate(wgs84: center).mapKit, latitudinalMeters: 700, longitudinalMeters: 700), animated: false)
            }
        }
        if context.coordinator.annotationPoint != selection {
            if let annotation = context.coordinator.annotation { map.removeAnnotation(annotation) }
            context.coordinator.annotation = nil
            context.coordinator.annotationPoint = selection
            if let selection = selection {
                let annotation = MKPointAnnotation()
                annotation.coordinate = MapCoordinate(wgs84: selection).mapKit
                annotation.title = "选定位置"
                map.addAnnotation(annotation)
                context.coordinator.annotation = annotation
            }
        }
    }

    final class Coordinator: NSObject {
        var selection: Binding<Coordinate?>
        var center: Coordinate?
        var annotationPoint: Coordinate?
        var annotation: MKPointAnnotation?

        init(selection: Binding<Coordinate?>) { self.selection = selection }

        @objc func selectPoint(_ gesture: NSClickGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let coordinate = map.convert(gesture.location(in: map), toCoordinateFrom: map)
            guard CLLocationCoordinate2DIsValid(coordinate) else { return }
            selection.wrappedValue = MapCoordinate(mapKit: coordinate).wgs84
        }
    }
}
