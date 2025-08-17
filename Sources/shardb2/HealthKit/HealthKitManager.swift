import Foundation
import HealthKit

public enum HealthKitError: Error {
    case notAvailable
    case permissionDenied
    case dataNotFound
    case queryFailed(Error)
}

public final class HealthKitManager {
    private let authManager = HealthKitAuthManager()
    private let stepCountManager = StepCountDataManager()
    
    public init() {}
    
    // Authorization methods
    public func getAuthorizationStatus(for type: HKQuantityTypeIdentifier) -> HKAuthorizationStatus {
        return authManager.getAuthorizationStatus(for: type)
    }
    
    public func isHealthDataAvailable() -> Bool {
        return authManager.isHealthDataAvailable()
    }
    
    // Step count data methods
    public func fetchLatestStepCount() async throws -> (stepCount: Int, date: Date) {
        return try await stepCountManager.fetchLatestStepCount()
    }
    
    public func fetchStepCountLast7Days() async throws -> [(date: Date, stepCount: Int)] {
        return try await stepCountManager.fetchStepCountLast7Days()
    }
}
