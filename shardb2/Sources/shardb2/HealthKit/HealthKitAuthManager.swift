import Foundation
import HealthKit

public final class HealthKitAuthManager {
    private let healthStore = HKHealthStore()
    
    public init() {}
    
    public func getAuthorizationStatus(for type: HKQuantityTypeIdentifier) -> HKAuthorizationStatus {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: type) else {
            return .notDetermined
        }
        return healthStore.authorizationStatus(for: quantityType)
    }
    
    public func isHealthDataAvailable() -> Bool {
        return HKHealthStore.isHealthDataAvailable()
    }
}