import SwiftUI
import UIKit
import MapKit
import CoreLocation

// MARK: - Main App View

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var showFavorites = false
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Map
            MapView()
                .ignoresSafeArea()

            // Top overlay
            VStack(spacing: 8) {
                SearchBarOverlay()
                StatusPill()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                Spacer()
            }

            // Bottom card
            ControlCard(
                onFavorites: { showFavorites = true },
                onSettings: { showSettings = true }
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .sheet(isPresented: $showFavorites) {
            FavoritesSheet().environmentObject(state)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet().environmentObject(state)
        }
        .alert("Location Spoofer Pro", isPresented: $state.showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.alertMessage)
        }
    }
}

// MARK: - Map View Wrapper

struct MapView: UIViewRepresentable {
    @EnvironmentObject var state: AppState

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.setRegion(state.region, animated: false)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTap(_:)))
        map.addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        map.addGestureRecognizer(longPress)

        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        if map.mapType != state.mapType { map.mapType = state.mapType }

        let existing = map.annotations.filter { !($0 is MKUserLocation) }
        if let pin = existing.first as? SpoofPin {
            if pin.coordinate.latitude != state.selectedCoordinate.latitude ||
               pin.coordinate.longitude != state.selectedCoordinate.longitude {
                map.removeAnnotation(pin)
                let newPin = SpoofPin(coordinate: state.selectedCoordinate)
                newPin.isSpoofing = state.isSpoofing
                map.addAnnotation(newPin)
            } else {
                pin.isSpoofing = state.isSpoofing
                if let view = map.view(for: pin) as? MKMarkerAnnotationView {
                    view.markerTintColor = state.isSpoofing ? .systemGreen : .systemBlue
                }
            }
        } else {
            map.removeAnnotations(existing)
            let pin = SpoofPin(coordinate: state.selectedCoordinate)
            pin.isSpoofing = state.isSpoofing
            map.addAnnotation(pin)
        }

        if !context.coordinator.userPanning {
            let center = map.region.center
            let dx = abs(center.latitude - state.selectedCoordinate.latitude)
            let dy = abs(center.longitude - state.selectedCoordinate.longitude)
            if dx > 0.001 || dy > 0.001 {
                map.setCenter(state.selectedCoordinate, animated: true)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    class Coordinator: NSObject, MKMapViewDelegate {
        var state: AppState
        var userPanning = false

        init(state: AppState) { self.state = state }

        @objc func didTap(_ g: UITapGestureRecognizer) {
            guard let map = g.view as? MKMapView else { return }
            let coord = map.convert(g.location(in: map), toCoordinateFrom: map)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            state.select(coordinate: coord)
        }

        @objc func didLongPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let map = g.view as? MKMapView else { return }
            let coord = map.convert(g.location(in: map), toCoordinateFrom: map)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            state.select(coordinate: coord)
        }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? SpoofPin else { return nil }
            let id = "SpoofPin"
            let view = (map.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView) ?? MKMarkerAnnotationView(annotation: pin, reuseIdentifier: id)
            view.annotation = pin
            view.markerTintColor = pin.isSpoofing ? .systemGreen : .systemBlue
            view.glyphImage = UIImage(systemName: "location.fill")
            view.isDraggable = true
            return view
        }

        func mapView(_ map: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState: MKAnnotationView.DragState) {
            if newState == .ending, let coord = view.annotation?.coordinate {
                state.select(coordinate: coord)
            }
        }

        func mapViewWillStartLocatingUser(_ map: MKMapView) {}
        func mapView(_ map: MKMapView, regionWillChangeAnimated animated: Bool) { userPanning = true }
        func mapView(_ map: MKMapView, regionDidChangeAnimated animated: Bool) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.userPanning = false }
        }
    }
}

class SpoofPin: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    var isSpoofing: Bool = false

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}
