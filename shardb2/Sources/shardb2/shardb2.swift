import Foundation
import SwiftData
import HealthKit

public final class HealthStatsLibrary {
    private let healthKitManager = HealthKitManager()
    private let modelContext: ModelContext
    
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    public func sampleAndStoreLatestStepCount() async throws -> StepCountRecord {
        let (stepCount, date) = try await healthKitManager.fetchLatestStepCount()
        
        let record = StepCountRecord(stepCount: stepCount, date: date)
        modelContext.insert(record)
        
        try modelContext.save()
        
        return record
    }
    
    public func getAllStepCountRecords() throws -> [StepCountRecord] {
        let descriptor = FetchDescriptor<StepCountRecord>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    public func getLatestStepCountRecord() throws -> StepCountRecord? {
        var descriptor = FetchDescriptor<StepCountRecord>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
    
    // User management methods
    public func createUser(birthdate: Date, usesMetric: Bool = true) throws -> User {
        let user = User(birthdate: birthdate, usesMetric: usesMetric)
        modelContext.insert(user)
        try modelContext.save()
        return user
    }
    
    public func getUser(by userID: UUID) throws -> User? {
        var descriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.userID == userID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
    
    public func getAllUsers() throws -> [User] {
        let descriptor = FetchDescriptor<User>(
            sortBy: [SortDescriptor(\.firstInit, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    public func updateUser(_ user: User) throws {
        try modelContext.save()
    }
    
    public func deleteUser(_ user: User) throws {
        modelContext.delete(user)
        try modelContext.save()
    }
    
    // HealthKit authorization status
    public func getHealthKitAuthorizationStatus(for type: HKQuantityTypeIdentifier = .stepCount) -> HKAuthorizationStatus {
        return healthKitManager.getAuthorizationStatus(for: type)
    }
    
    // Fetch and store last 7 days of step count data
    public func fetchAndStoreLast7DaysStepCount() async throws -> [StepCountRecord] {
        let dailyStepData = try await healthKitManager.fetchStepCountLast7Days()
        
        var records: [StepCountRecord] = []
        
        for dayData in dailyStepData {
            let record = StepCountRecord(stepCount: dayData.stepCount, date: dayData.date)
            modelContext.insert(record)
            records.append(record)
        }
        
        try modelContext.save()
        return records
    }
}
