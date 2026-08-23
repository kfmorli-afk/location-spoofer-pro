import Foundation
import MapKit
import Combine

public class SearchViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published public var searchQuery: String = ""
    @Published public var completions: [MKLocalSearchCompletion] = []
    @Published public var isSearching: Bool = false
    @Published public var errorMessage: String?
    
    private let completer: MKLocalSearchCompleter
    private var cancellables = Set<AnyCancellable>()
    
    public override init() {
        self.completer = MKLocalSearchCompleter()
        super.init()
        self.completer.delegate = self
        self.completer.resultTypes = [.address, .pointOfInterest]
        
        $searchQuery
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self = self else { return }
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.completions = []
                    self.isSearching = false
                } else {
                    self.isSearching = true
                    self.completer.queryFragment = query
                }
            }
            .store(in: &cancellables)
    }
    
    public func setRegion(_ region: MKCoordinateRegion) {
        completer.region = region
    }
    
    // MARK: - Selection & Geocoding
    
    public func selectCompletion(_ completion: MKLocalSearchCompletion) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        
        do {
            let response = try await search.start()
            if let firstItem = response.mapItems.first {
                return firstItem.placemark.coordinate
            }
        } catch {
            print("[SearchViewModel] Fehler beim Auflösen der Suchergänzung: \(error.localizedDescription)")
        }
        return nil
    }
    
    public func searchDirectQuery(_ query: String) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let search = MKLocalSearch(request: request)
        
        do {
            let response = try await search.start()
            if let firstItem = response.mapItems.first {
                return firstItem.placemark.coordinate
            }
        } catch {
            print("[SearchViewModel] Fehler bei Direktsuche: \(error.localizedDescription)")
        }
        return nil
    }
    
    // MARK: - MKLocalSearchCompleterDelegate
    
    public func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.completions = completer.results
            self.isSearching = false
        }
    }
    
    public func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
            self.isSearching = false
        }
    }
}
