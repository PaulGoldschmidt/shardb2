import Foundation
import SwiftData
import HealthKit

public final class HealthStatsLibrary {
    private let healthKitManager = HealthKitManager()
    private let healthDataAggregator = HealthDataAggregator()
    private let modelContext: ModelContext
    private let databaseInitializer: DatabaseInitializer
    private let dataUpdater: DataUpdater
    
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.databaseInitializer = DatabaseInitializer(modelContext: modelContext)
        self.dataUpdater = DataUpdater(modelContext: modelContext)
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
    
    public func setUserFirstHealthKitRecord(_ user: User) throws {
        let earliestDate = try healthDataAggregator.findEarliestHealthKitSample()
        user.firstHealthKitRecord = earliestDate
        try updateUser(user)
    }
    
    public func deleteUser(_ user: User) throws {
        modelContext.delete(user)
        try modelContext.save()
    }
    
    // MARK: - Database Management
    
    public func clearDatabaseExceptUser(_ user: User) throws {
        // Clear all analytics but keep user data
        let dailyAnalytics = try getAllDailyAnalytics()
        let weeklyAnalytics = try getAllWeeklyAnalytics()
        let monthlyAnalytics = try getAllMonthlyAnalytics()
        let yearlyAnalytics = try getAllYearlyAnalytics()
        
        // Delete analytics records
        for record in dailyAnalytics { modelContext.delete(record) }
        for record in weeklyAnalytics { modelContext.delete(record) }
        for record in monthlyAnalytics { modelContext.delete(record) }
        for record in yearlyAnalytics { modelContext.delete(record) }
        
        try modelContext.save()
        
        // Reset user's lastProcessedAt to force full reprocessing and update firstHealthKitRecord
        let resetDate = DateComponents(calendar: Calendar.current, year: 1999, month: 1, day: 1).date!
        user.lastProcessedAt = resetDate
        // Re-detect the actual first HealthKit record
        try setUserFirstHealthKitRecord(user)
    }
    
    // HealthKit authorization status
    public func getHealthKitAuthorizationStatus(for type: HKQuantityTypeIdentifier = .stepCount) -> HKAuthorizationStatus {
        return healthKitManager.getAuthorizationStatus(for: type)
    }
    
    
    // Database initialization with progress callback
    public func initializeDatabase(for user: User, progressCallback: @escaping (InitializationProgress) -> Void) throws {
        try databaseInitializer.initializeDatabase(for: user, progressCallback: progressCallback)
    }
    
    // Incremental data updates with progress callback
    public func updateMissingData(for user: User, progressCallback: @escaping (InitializationProgress) -> Void) throws {
        try dataUpdater.updateMissingData(for: user, progressCallback: progressCallback)
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
