import Foundation
import HealthKit

public enum HealthKitError: Error {
    case notAvailable
    case permissionDenied
    case dataNotFound
    case queryFailed(Error)
}

public final class HealthKitManager {
    private let healthStore = HKHealthStore()
}
