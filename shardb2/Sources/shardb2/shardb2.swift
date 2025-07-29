import Foundation
import SwiftData
import HealthKit

public final class HealthStatsLibrary {
    private let healthKitManager = HealthKitManager()
    private let modelContext: ModelContext
    private let databaseInitializer: DatabaseInitializer
    private let dataUpdater: DataUpdater
    
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.databaseInitializer = DatabaseInitializer(modelContext: modelContext)
        self.dataUpdater = DataUpdater(modelContext: modelContext)
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
    
    // Database initialization with progress streaming
    public func initializeDatabase(for user: User) -> AsyncStream<InitializationProgress> {
        return databaseInitializer.initializeDatabase(for: user)
    }
    
    // Incremental data updates with progress streaming
    public func updateMissingData(for user: User) -> AsyncStream<InitializationProgress> {
        return dataUpdater.updateMissingData(for: user)
    }
    
    // MARK: - Daily Analytics Queries
    
    public func getDailyAnalytics(for date: Date) throws -> DailyAnalytics? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        var descriptor = FetchDescriptor<DailyAnalytics>(
            predicate: #Predicate { $0.date == startOfDay }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
    
    public func getDailyAnalytics(from startDate: Date, to endDate: Date) throws -> [DailyAnalytics] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        
        let descriptor = FetchDescriptor<DailyAnalytics>(
            predicate: #Predicate { analytics in
                analytics.date >= start && analytics.date <= end
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    public func getAllDailyAnalytics() throws -> [DailyAnalytics] {
        let descriptor = FetchDescriptor<DailyAnalytics>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    public func getLatestDailyAnalytics() throws -> DailyAnalytics? {
        var descriptor = FetchDescriptor<DailyAnalytics>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
    
    // MARK: - Weekly Analytics Queries
    
    public func getWeeklyAnalytics(for date: Date) throws -> WeeklyAnalytics? {
        let calendar = Calendar.current
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date) else { return nil }
        
        let descriptor = FetchDescriptor<WeeklyAnalytics>(
            predicate: #Predicate { analytics in
                analytics.startDate <= weekInterval.start && analytics.endDate >= weekInterval.start
            }
        )
        return try modelContext.fetch(descriptor).first
    }
    
    public func getWeeklyAnalytics(from startDate: Date, to endDate: Date) throws -> [WeeklyAnalytics] {
        let descriptor = FetchDescriptor<WeeklyAnalytics>(
            predicate: #Predicate { analytics in
                analytics.startDate >= startDate && analytics.endDate <= endDate
            },
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    public func getAllWeeklyAnalytics() throws -> [WeeklyAnalytics] {
        let descriptor = FetchDescriptor<WeeklyAnalytics>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    public func getLatestWeeklyAnalytics() throws -> WeeklyAnalytics? {
        var descriptor = FetchDescriptor<WeeklyAnalytics>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
    
    // MARK: - Monthly Analytics Queries
    
    public func getMonthlyAnalytics(for date: Date) throws -> MonthlyAnalytics? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else { return nil }
        
        var descriptor = FetchDescriptor<MonthlyAnalytics>(
            predicate: #Predicate { analytics in
                analytics.year == year && analytics.month == month
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
    
    public func getMonthlyAnalytics(year: Int, month: Int) throws -> MonthlyAnalytics? {
        var descriptor = FetchDescriptor<MonthlyAnalytics>(
            predicate: #Predicate { analytics in
                analytics.year == year && analytics.month == month
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
    
    public func getMonthlyAnalytics(for year: Int) throws -> [MonthlyAnalytics] {
        let descriptor = FetchDescriptor<MonthlyAnalytics>(
            predicate: #Predicate { analytics in
                analytics.year == year
            },
            sortBy: [SortDescriptor(\.month, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    public func getAllMonthlyAnalytics() throws -> [MonthlyAnalytics] {
        let descriptor = FetchDescriptor<MonthlyAnalytics>(
            sortBy: [SortDescriptor(\.year, order: .reverse), SortDescriptor(\.month, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    public func getLatestMonthlyAnalytics() throws -> MonthlyAnalytics? {
        var descriptor = FetchDescriptor<MonthlyAnalytics>(
            sortBy: [SortDescriptor(\.year, order: .reverse), SortDescriptor(\.month, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
    
    // MARK: - Yearly Analytics Queries
    
    public func getYearlyAnalytics(for date: Date) throws -> YearlyAnalytics? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        
        var descriptor = FetchDescriptor<YearlyAnalytics>(
            predicate: #Predicate { analytics in
                analytics.year == year
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
    
    public func getYearlyAnalytics(for year: Int) throws -> YearlyAnalytics? {
        var descriptor = FetchDescriptor<YearlyAnalytics>(
            predicate: #Predicate { analytics in
                analytics.year == year
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
    
    public func getAllYearlyAnalytics() throws -> [YearlyAnalytics] {
        let descriptor = FetchDescriptor<YearlyAnalytics>(
            sortBy: [SortDescriptor(\.year, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    public func getLatestYearlyAnalytics() throws -> YearlyAnalytics? {
        var descriptor = FetchDescriptor<YearlyAnalytics>(
            sortBy: [SortDescriptor(\.year, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
