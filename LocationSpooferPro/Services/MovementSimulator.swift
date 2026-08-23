import Foundation
import CoreLocation
import Combine
import CoreGraphics
import UIKit

public class MovementSimulator: ObservableObject {
    public static let shared = MovementSimulator()
    
    @Published public var isMoving: Bool = false
    @Published public var speedPreset: SpeedPreset = .walk
    @Published public var currentBearing: Double = 0.0 // 0 = North, 90 = East, 180 = South, 270 = West
    @Published public var joystickVelocity: CGPoint = .zero // -1.0 ... +1.0
    
    private var timer: Timer?
    private let simulationClient = LocationSimulationClient.shared
    
    public init() {}
    
    public func startJoystickMovement(from startCoordinate: CLLocationCoordinate2D, onUpdate: @escaping (CLLocationCoordinate2D) -> Void) {
        guard timer == nil else { return }
        
        var currentCoord = startCoordinate
        isMoving = true
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.isMoving else { return }
            
            let vx = self.joystickVelocity.x
            let vy = self.joystickVelocity.y
            
            let magnitude = sqrt(vx * vx + vy * vy)
            guard magnitude > 0.05 else { return } // deadzone
            
            // Calculate angle in radians
            // In screen coordinates: +x is right (East), +y is down (South)
            // So: angle 0 = East, angle -pi/2 = North (screen up is negative y)
            let angle = atan2(-vy, vx) // mathematical angle where +x=0, +y=pi/2
            // Convert to compass bearing (0 = North, 90 = East, 180 = South, 270 = West)
            var bearing = (90.0 - (angle * 180.0 / .pi))
            if bearing < 0 { bearing += 360.0 }
            self.currentBearing = bearing
            
            // Distance traveled in 0.5 seconds
            let speedMps = self.speedPreset.metersPerSecond * Double(min(magnitude, 1.0))
            let distanceMeters = speedMps * 0.5
            
            // Calculate new coordinate using geodesic formula
            currentCoord = self.calculateDestination(from: currentCoord, distanceMeters: distanceMeters, bearingDegrees: bearing)
            
            onUpdate(currentCoord)
            
            // Send to lockdownd
            Task {
                try? await self.simulationClient.spoofLocation(coordinate: currentCoord)
            }
        }
    }
    
    public func stopJoystickMovement() {
        isMoving = false
        timer?.invalidate()
        timer = nil
        joystickVelocity = .zero
    }
    
    public func updateJoystick(x: CGFloat, y: CGFloat) {
        self.joystickVelocity = CGPoint(x: max(-1.0, min(1.0, x)), y: max(-1.0, min(1.0, y)))
    }
    
    /// Geodesic destination point calculation on WGS84 sphere
    private func calculateDestination(from origin: CLLocationCoordinate2D, distanceMeters: Double, bearingDegrees: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6371000.0 // meters
        let angularDistance = distanceMeters / earthRadius
        let bearingRad = bearingDegrees * .pi / 180.0
        
        let lat1 = origin.latitude * .pi / 180.0
        let lon1 = origin.longitude * .pi / 180.0
        
        let lat2 = asin(sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(bearingRad))
        let lon2 = lon1 + atan2(sin(bearingRad) * sin(angularDistance) * cos(lat1), cos(angularDistance) - sin(lat1) * sin(lat2))
        
        let newLat = lat2 * 180.0 / .pi
        let newLon = lon2 * 180.0 / .pi
        
        return CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
    }
}
