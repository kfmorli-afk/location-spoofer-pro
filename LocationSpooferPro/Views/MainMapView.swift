import SwiftUI
import MapKit
import CoreLocation

public struct MainMapView: View {
    @EnvironmentObject var mapViewModel: MapViewModel
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    @StateObject private var searchViewModel = SearchViewModel()
    
    @State private var showFavoritesSheet: Bool = false
    @State private var showSettingsSheet: Bool = false
    @State private var showMapTypePicker: Bool = false
    @State private var isSearchFocused: Bool = false
    
    public var body: some View {
        ZStack(alignment: .top) {
            // MARK: - Native Apple Maps View
            NativeMapViewRepresentable(
                region: $mapViewModel.region,
                selectedCoordinate: $mapViewModel.selectedCoordinate,
                mapType: mapViewModel.mapType,
                isSpoofingActive: mapViewModel.simulationClient.isSpoofingActive,
                onCoordinateSelected: { coord in
                    mapViewModel.selectCoordinate(coord, animated: true)
                }
            )
            .ignoresSafeArea()
            
            // MARK: - Top Overlay: Search Bar, Status Pill, Search Results
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    SearchBarView(
                        text: $searchViewModel.searchQuery,
                        isSearching: $searchViewModel.isSearching,
                        onCommit: {
                            Task {
                                if let coord = await searchViewModel.searchDirectQuery(searchViewModel.searchQuery) {
                                    mapViewModel.selectCoordinate(coord, animated: true)
                                    searchViewModel.searchQuery = ""
                                }
                            }
                        },
                        onClear: {
                            searchViewModel.searchQuery = ""
                        }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                // Status Pill below search bar
                HStack {
                    StatusIndicatorView(
                        status: mapViewModel.simulationClient.connectionStatus,
                        isPairingValid: settingsViewModel.pairingService.hasValidPairing,
                        onTap: {
                            showSettingsSheet = true
                        }
                    )
                    Spacer()
                }
                .padding(.horizontal, 20)
                
                // Autocomplete Results Dropdown
                if !searchViewModel.completions.isEmpty && !searchViewModel.searchQuery.isEmpty {
                    SearchResultsView(
                        completions: searchViewModel.completions,
                        onSelect: { completion in
                            Task {
                                if let coord = await searchViewModel.selectCompletion(completion) {
                                    mapViewModel.selectCoordinate(coord, animated: true)
                                    searchViewModel.searchQuery = ""
                                }
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Spacer()
            }
            
            // MARK: - Right Floating Map Tools
            VStack(spacing: 12) {
                Spacer()
                
                // Map Type Switcher
                Button(action: {
                    cycleMapType()
                }) {
                    Image(systemName: mapTypeIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                
                // Jump to Selected Pin
                Button(action: {
                    mapViewModel.selectCoordinate(mapViewModel.selectedCoordinate, animated: true)
                }) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.blue)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                
                // Real GPS Location Button
                Button(action: {
                    mapViewModel.jumpToUserRealLocation()
                }) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                
                // Spacing above the bottom card
                Spacer().frame(height: mapViewModel.isJoystickActive ? 280 : 190)
            }
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, alignment: .trailing)
            
            // MARK: - Bottom Overlay: Joystick and Location Card
            VStack(spacing: 12) {
                Spacer()
                
                // Virtual Joystick if enabled
                if mapViewModel.isJoystickActive {
                    JoystickOverlayView(
                        movementSimulator: mapViewModel.movementSimulator,
                        currentCoordinate: mapViewModel.selectedCoordinate,
                        onCoordinateChange: { newCoord in
                            mapViewModel.selectedCoordinate = newCoord
                            mapViewModel.region.center = newCoord
                        },
                        onClose: {
                            mapViewModel.isJoystickActive = false
                            mapViewModel.movementSimulator.stopJoystickMovement()
                        }
                    )
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Location Action Card
                LocationControlCard(
                    onSpoof: {
                        mapViewModel.triggerSpoof()
                    },
                    onReset: {
                        mapViewModel.triggerReset()
                    },
                    onToggleFavorites: {
                        showFavoritesSheet = true
                    },
                    onToggleSettings: {
                        showSettingsSheet = true
                    },
                    onToggleJoystick: {
                        withAnimation(.spring()) {
                            mapViewModel.isJoystickActive.toggle()
                        }
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showFavoritesSheet) {
            FavoritesSheetView()
                .environmentObject(mapViewModel)
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsSheetView()
                .environmentObject(settingsViewModel)
        }
        .alert(isPresented: $mapViewModel.showAlert) {
            Alert(
                title: Text("Location Spoofer"),
                message: Text(mapViewModel.alertMessage ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private var mapTypeIcon: String {
        switch mapViewModel.mapType {
        case .standard: return "map"
        case .satellite: return "globe.europe.africa.fill"
        case .hybrid: return "square.2.layers.3d"
        default: return "map"
        }
    }
    
    private func cycleMapType() {
        switch mapViewModel.mapType {
        case .standard: mapViewModel.mapType = .hybrid
        case .hybrid: mapViewModel.mapType = .satellite
        case .satellite: mapViewModel.mapType = .standard
        default: mapViewModel.mapType = .standard
        }
    }
}

// MARK: - Native MKMapView Wrapper for full gesture support

struct NativeMapViewRepresentable: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var selectedCoordinate: CLLocationCoordinate2D
    var mapType: MKMapType
    var isSpoofingActive: Bool
    var onCoordinateSelected: (CLLocationCoordinate2D) -> Void
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.mapType = mapType
        mapView.setRegion(region, animated: false)
        
        // Single tap gesture to select point anywhere
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tapGesture)
        
        // Long press gesture
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        mapView.addGestureRecognizer(longPress)
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if uiView.mapType != mapType {
            uiView.mapType = mapType
        }
        
        // Update pin annotation
        let existingAnnotations = uiView.annotations.filter { !($0 is MKUserLocation) }
        
        var pinAnnotation: SpoofPinAnnotation?
        if let existing = existingAnnotations.first as? SpoofPinAnnotation {
            pinAnnotation = existing
            if pinAnnotation?.coordinate.latitude != selectedCoordinate.latitude || pinAnnotation?.coordinate.longitude != selectedCoordinate.longitude {
                UIView.animate(withDuration: 0.2) {
                    pinAnnotation?.coordinate = selectedCoordinate
                }
            }
        } else {
            uiView.removeAnnotations(existingAnnotations)
            let newPin = SpoofPinAnnotation(coordinate: selectedCoordinate, title: "Zielort")
            uiView.addAnnotation(newPin)
        }
        
        // Center smoothly if coordinate changed significantly from region center
        let center = uiView.region.center
        let distance = sqrt(pow(center.latitude - selectedCoordinate.latitude, 2) + pow(center.longitude - selectedCoordinate.longitude, 2))
        if distance > 0.0001 && !context.coordinator.isUserInteracting {
            uiView.setCenter(selectedCoordinate, animated: true)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NativeMapViewRepresentable
        var isUserInteracting: Bool = false
        
        init(_ parent: NativeMapViewRepresentable) {
            self.parent = parent
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            
            parent.onCoordinateSelected(coordinate)
        }
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()
            
            parent.onCoordinateSelected(coordinate)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            
            let identifier = "SpoofPinIdentifier"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            
            if view == nil {
                view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view?.canShowCallout = false
                view?.isDraggable = true
            } else {
                view?.annotation = annotation
            }
            
            view?.markerTintColor = parent.isSpoofingActive ? .systemGreen : .systemBlue
            view?.glyphImage = UIImage(systemName: "location.fill")
            view?.displayPriority = .required
            
            return view
        }
        
        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            if newState == .ending, let newCoord = view.annotation?.coordinate {
                parent.onCoordinateSelected(newCoord)
            }
        }
        
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            isUserInteracting = true
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            isUserInteracting = false
        }
    }
}

class SpoofPinAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    var title: String?
    
    init(coordinate: CLLocationCoordinate2D, title: String? = nil) {
        self.coordinate = coordinate
        self.title = title
    }
}
