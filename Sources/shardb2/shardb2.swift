import Foundation
import SwiftData
import HealthKit
import SwiftUI
import Combine

/// UI-ready health metric for display in the app
public struct CardioMetric: Identifiable {
    public let id = UUID()
    public let title: String
    public let value: String
    public let unit: String
    public let icon: String
    public let color: Color
    
    public init(title: String, value: String, unit: String, icon: String, color: Color) {
        self.title = title
        self.value = value
        self.unit = unit
        self.icon = icon
        self.color = color
    }
}

/// Data point for time series charts
public struct TimeSeriesDataPoint: Identifiable, Equatable {
    public let id = UUID()
    public let date: Date
    public let value: Double
    public let formattedValue: String
    public let unit: String
    
    public init(date: Date, value: Double, formattedValue: String, unit: String) {
        self.date = date
        self.value = value
        self.formattedValue = formattedValue
        self.unit = unit
    }
    
    public static func == (lhs: TimeSeriesDataPoint, rhs: TimeSeriesDataPoint) -> Bool {
        return lhs.id == rhs.id &&
               lhs.date == rhs.date &&
               lhs.value == rhs.value &&
               lhs.formattedValue == rhs.formattedValue &&
               lhs.unit == rhs.unit
    }
}

/// Complete time series data for charts
public struct TimeSeriesData {
    public let dataPoints: [TimeSeriesDataPoint]
    public let metricTitle: String
    public let metricIcon: String
    public let metricColor: Color
    public let metricUnit: String
    
    public init(dataPoints: [TimeSeriesDataPoint], metricTitle: String, metricIcon: String, metricColor: Color, metricUnit: String) {
        self.dataPoints = dataPoints
        self.metricTitle = metricTitle
        self.metricIcon = metricIcon
        self.metricColor = metricColor
        self.metricUnit = metricUnit
    }
}


/// Main interface for health statistics tracking and analytics
/// Combines HealthKit data fetching with SwiftData persistence
public final class HealthStatsLibrary: ObservableObject {
    // Core managers for different aspects of health data handling
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
    
    
    // MARK: - User Management
    // Basic CRUD operations for user data
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
    
    /// Finds the user's earliest HealthKit sample and updates their record
    /// This is important for knowing how far back we can process data
    public func setUserFirstHealthKitRecord(_ user: User) async throws {
        let earliestDate = try await healthDataAggregator.findEarliestHealthKitSample()
        user.firstHealthKitRecord = earliestDate
        try updateUser(user)
    }
    
    public func deleteUser(_ user: User) throws {
        modelContext.delete(user)
        try modelContext.save()
    }
    
    // MARK: - Database Management
    // Heavy lifting operations for data processing
    
    /// Nuclear option - wipes all analytics but keeps user data
    /// Useful for debugging or when something goes wrong with data processing
    public func clearDatabaseExceptUser(_ user: User) async throws {
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
        // Re-detect the actual first HealthKit record so we know our data boundaries
        try await setUserFirstHealthKitRecord(user)
    }
    
    // MARK: - HealthKit Authorization
    // Simple status checks for HealthKit permissions
    public func getHealthKitAuthorizationStatus(for type: HKQuantityTypeIdentifier = .stepCount) -> HKAuthorizationStatus {
        return healthKitManager.getAuthorizationStatus(for: type)
    }
    
    /// Checks current HealthKit status and updates user model if it changed
    /// Returns the current authorization state
    public func updateUserHealthKitAuthorizationStatus(for user: User) throws -> Bool {
        let authStatus = healthKitManager.getAuthorizationStatus(for: .stepCount)
        let isAuthorized = authStatus == .sharingAuthorized
        let previousAuthStatus = user.healthkitAuthorized
        
        user.healthkitAuthorized = isAuthorized
        
        // Only hit the database if something actually changed
        if previousAuthStatus != isAuthorized {
            try modelContext.save()
        }
        
        return isAuthorized
    }
    
    
    /// Full database initialization - this is the big one that processes everything
    /// Use this for first-time setup or complete rebuilds
    public func initializeDatabase(for user: User, progressCallback: @escaping (InitializationProgress) -> Void) async throws {
        try await databaseInitializer.initializeDatabase(for: user, progressCallback: progressCallback)
    }
    
    /// Incremental updates based on user's last processed timestamp
    /// More efficient than full initialization for regular updates
    public func updateMissingData(for user: User, progressCallback: @escaping (InitializationProgress) -> Void) async throws {
        try await dataUpdater.updateMissingData(for: user, healthKitManager: healthKitManager, progressCallback: progressCallback)
    }
    
    /// Quick refresh of just today's data - useful for real-time updates
    /// Much faster than full refresh when you just need current day
    public func refreshCurrentDay(for user: User, progressCallback: @escaping (InitializationProgress) -> Void) async throws {
        try await dataUpdater.refreshCurrentDay(for: user, healthKitManager: healthKitManager, progressCallback: progressCallback)
    }
    
    // MARK: - Daily Analytics Queries
    // All the ways to slice and dice daily health data
    
    public func getDailyAnalytics(for date: Date) throws -> DailyAnalytics? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date) // Normalize to beginning of day
        
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
    // Week-based aggregations - useful for trends
    
    public func getWeeklyAnalytics(for date: Date) throws -> WeeklyAnalytics? {
        let calendar = Calendar.current
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date) else { return nil } // Handle edge cases
        
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
    // Monthly views - good for longer-term patterns
    
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
    // The big picture view of health data
    
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
    
    // MARK: - Comprehensive Data Refresh
    // The smart refresh that only updates what's needed
    
    public func refreshAllData(for user: User, progressCallback: @escaping (InitializationProgress) -> Void) async throws {
        let now = Date()
        let lastRefresh = user.lastProcessedAt
        let lastHighscoreUpdate = user.highscoresLastUpdated
        
        progressCallback(InitializationProgress(percentage: 0.0, currentTask: "Starting data refresh..."))
        
        // Phase 1: Get any new HealthKit data we haven't processed yet (0-30%)
        try await dataUpdater.updateMissingData(for: user, healthKitManager: healthKitManager) { progress in
            let adjustedProgress = InitializationProgress(
                percentage: progress.percentage * 0.3, // Scale to 30%
                currentTask: progress.currentTask
            )
            progressCallback(adjustedProgress)
        }
        
        // Phase 2: Update current week analytics (30-50%)
        // We need to refresh current periods since they're still changing
        progressCallback(InitializationProgress(percentage: 30.0, currentTask: "Refreshing current week..."))
        try refreshCurrentPeriodAnalytics(from: lastRefresh, to: now, progressCallback: { progress in
            let adjustedProgress = 30.0 + (progress * 20.0) // 30-50%
            progressCallback(InitializationProgress(percentage: adjustedProgress, currentTask: "Refreshing current period analytics..."))
        })
        
        // Phase 3: Check if any new personal records were set (50-80%)
        progressCallback(InitializationProgress(percentage: 50.0, currentTask: "Updating personal records..."))
        try refreshHighscoresIncremental(from: lastHighscoreUpdate, to: now, progressCallback: { progress in
            let adjustedProgress = 50.0 + (progress * 30.0) // 50-80%
            progressCallback(InitializationProgress(percentage: adjustedProgress, currentTask: "Checking personal records..."))
        })
        
        // Phase 4: Update user timestamps (80-100%)
        progressCallback(InitializationProgress(percentage: 80.0, currentTask: "Finalizing refresh..."))
        user.lastProcessedAt = now
        user.highscoresLastUpdated = now
        try updateUser(user)
        
        progressCallback(InitializationProgress(percentage: 100.0, currentTask: "Data refresh completed!"))
    }
    
    // MARK: - Highscore Management
    // Personal records and achievements tracking
    
    public func getHighscoreRecord() throws -> HighscoreRecord? {
        var descriptor = FetchDescriptor<HighscoreRecord>()
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
    
    
    /// Scans through all daily data to find personal bests
    /// This is expensive but thorough - only run when needed
    private func updateHighscoresFromDailyAnalytics(_ highscore: HighscoreRecord) throws {
        // Get all daily analytics to analyze
        let allDailyAnalytics = try getAllDailyAnalytics()
        
        // Process each day to find records
        for daily in allDailyAnalytics {
            // Check daily activity records against current bests
            if daily.steps > highscore.mostStepsInADay {
                highscore.mostStepsInADay = daily.steps
                highscore.mostStepsInADayDate = daily.date
            }
            
            let totalCalories = daily.energyActive + daily.energyResting
            if totalCalories > highscore.mostCaloriesInADay {
                highscore.mostCaloriesInADay = totalCalories
                highscore.mostCaloriesInADayDate = daily.date
            }
            
            if daily.exerciseMinutes > highscore.mostExerciseMinutesInADay {
                highscore.mostExerciseMinutesInADay = daily.exerciseMinutes
                highscore.mostExerciseMinutesInADayDate = daily.date
            }
            
            // Distance records - these might be cumulative daily totals, not single activities
            if daily.walkingDistance > highscore.longestWalk {
                highscore.longestWalk = daily.walkingDistance
                highscore.longestWalkDate = daily.date
            }
            
            if daily.cyclingDistance > highscore.longestBikeRide {
                highscore.longestBikeRide = daily.cyclingDistance
                highscore.longestBikeRideDate = daily.date
            }
            
            if daily.swimmingDistance > highscore.longestSwim {
                highscore.longestSwim = daily.swimmingDistance
                highscore.longestSwimDate = daily.date
            }
            
            // Check sleep records
            if daily.sleepTotal > highscore.longestSleep {
                highscore.longestSleep = daily.sleepTotal
                highscore.longestSleepDate = daily.date
            }
            
            if daily.sleepDeep > highscore.mostDeepSleep {
                highscore.mostDeepSleep = daily.sleepDeep
                highscore.mostDeepSleepDate = daily.date
            }
            
            if daily.sleepREM > highscore.mostREMSleep {
                highscore.mostREMSleep = daily.sleepREM
                highscore.mostREMSleepDate = daily.date
            }
        }
        
        // Calculate streaks - these are tricky since they depend on consecutive days
        try calculateSleepStreak(highscore, from: allDailyAnalytics)
        try calculateWorkoutStreak(highscore, from: allDailyAnalytics)
    }
    
    /// Finds the longest consecutive streak of days with sleep data
    /// Uses a simple state machine approach
    private func calculateSleepStreak(_ highscore: HighscoreRecord, from dailyAnalytics: [DailyAnalytics]) throws {
        let sortedDays = dailyAnalytics.sorted { $0.date < $1.date }
        
        var currentStreak = 0
        var maxStreak = 0
        var maxStreakStart: Date?
        var maxStreakEnd: Date?
        var currentStreakStart: Date?
        
        for daily in sortedDays {
            if daily.sleepTotal > 0 { // Any sleep is better than no sleep
                if currentStreak == 0 {
                    currentStreakStart = daily.date
                }
                currentStreak += 1
                
                if currentStreak > maxStreak {
                    maxStreak = currentStreak
                    maxStreakStart = currentStreakStart
                    maxStreakEnd = daily.date
                }
            } else {
                currentStreak = 0
                currentStreakStart = nil
            }
        }
        
        if maxStreak > highscore.sleepStreakRecord {
            highscore.sleepStreakRecord = maxStreak
            highscore.sleepStreakRecordStartDate = maxStreakStart
            highscore.sleepStreakRecordEndDate = maxStreakEnd
        }
    }
    
    private func calculateWorkoutStreak(_ highscore: HighscoreRecord, from dailyAnalytics: [DailyAnalytics]) throws {
        let sortedDays = dailyAnalytics.sorted { $0.date < $1.date }
        
        var currentStreak = 0
        var maxStreak = 0
        var maxStreakStart: Date?
        var maxStreakEnd: Date?
        var currentStreakStart: Date?
        
        for daily in sortedDays {
            if daily.exerciseMinutes > 0 { // Any movement counts
                if currentStreak == 0 {
                    currentStreakStart = daily.date // Start of a new streak
                }
                currentStreak += 1
                
                if currentStreak > maxStreak {
                    maxStreak = currentStreak
                    maxStreakStart = currentStreakStart
                    maxStreakEnd = daily.date // New record!
                }
            } else {
                currentStreak = 0 // Streak broken
                currentStreakStart = nil
            }
        }
        
        // Only update if we found a better streak
        if maxStreak > highscore.workoutStreakRecord {
            highscore.workoutStreakRecord = maxStreak
            highscore.workoutStreakRecordStartDate = maxStreakStart
            highscore.workoutStreakRecordEndDate = maxStreakEnd
        }
    }
    
    /// Updates analytics for current time periods that are still changing
    /// Only touches periods that might be affected by new data
    private func refreshCurrentPeriodAnalytics(from startDate: Date, to endDate: Date, progressCallback: @escaping (Double) -> Void) throws {
        let calendar = Calendar.current
        
        // Update current week (if affected)
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: endDate)?.start ?? endDate
        if startDate <= currentWeekStart { // Week might have changed
            progressCallback(0.25)
            try updateWeeklyAnalyticsForWeek(currentWeekStart)
        }
        
        // Update current month (if affected)
        let currentMonthStart = calendar.dateInterval(of: .month, for: endDate)?.start ?? endDate
        if startDate <= currentMonthStart { // Month might have changed
            progressCallback(0.5)
            try updateMonthlyAnalyticsForMonth(currentMonthStart)
        }
        
        // Update current year (if affected)
        let currentYearStart = calendar.dateInterval(of: .year, for: endDate)?.start ?? endDate
        if startDate <= currentYearStart { // Year might have changed
            progressCallback(0.75)
            try updateYearlyAnalyticsForYear(currentYearStart)
        }
        
        progressCallback(1.0)
    }
    
    private func refreshHighscoresIncremental(from startDate: Date, to endDate: Date, progressCallback: @escaping (Double) -> Void) throws {
        let calendar = Calendar.current
        let startOfStartDate = calendar.startOfDay(for: startDate)
        let startOfEndDate = calendar.startOfDay(for: endDate)
        
        // Get existing highscore record or create new one
        let existingRecord = try getHighscoreRecord()
        let highscoreRecord = existingRecord ?? HighscoreRecord()
        
        if existingRecord == nil {
            modelContext.insert(highscoreRecord)
        }
        
        // Only get daily analytics from the refresh period
        let descriptor = FetchDescriptor<DailyAnalytics>(
            predicate: #Predicate { analytics in
                analytics.date >= startOfStartDate && analytics.date <= startOfEndDate
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        
        let newDailyAnalytics = try modelContext.fetch(descriptor)
        progressCallback(0.2)
        
        // Check each new day against existing records
        for (index, daily) in newDailyAnalytics.enumerated() {
            // Daily activity records
            if daily.steps > highscoreRecord.mostStepsInADay {
                highscoreRecord.mostStepsInADay = daily.steps
                highscoreRecord.mostStepsInADayDate = daily.date
            }
            
            let totalCalories = daily.energyActive + daily.energyResting
            if totalCalories > highscoreRecord.mostCaloriesInADay {
                highscoreRecord.mostCaloriesInADay = totalCalories
                highscoreRecord.mostCaloriesInADayDate = daily.date
            }
            
            if daily.exerciseMinutes > highscoreRecord.mostExerciseMinutesInADay {
                highscoreRecord.mostExerciseMinutesInADay = daily.exerciseMinutes
                highscoreRecord.mostExerciseMinutesInADayDate = daily.date
            }
            
            // Distance records
            if daily.walkingDistance > highscoreRecord.longestWalk {
                highscoreRecord.longestWalk = daily.walkingDistance
                highscoreRecord.longestWalkDate = daily.date
            }
            
            if daily.cyclingDistance > highscoreRecord.longestBikeRide {
                highscoreRecord.longestBikeRide = daily.cyclingDistance
                highscoreRecord.longestBikeRideDate = daily.date
            }
            
            if daily.swimmingDistance > highscoreRecord.longestSwim {
                highscoreRecord.longestSwim = daily.swimmingDistance
                highscoreRecord.longestSwimDate = daily.date
            }
            
            // Sleep records
            if daily.sleepTotal > highscoreRecord.longestSleep {
                highscoreRecord.longestSleep = daily.sleepTotal
                highscoreRecord.longestSleepDate = daily.date
            }
            
            if daily.sleepDeep > highscoreRecord.mostDeepSleep {
                highscoreRecord.mostDeepSleep = daily.sleepDeep
                highscoreRecord.mostDeepSleepDate = daily.date
            }
            
            if daily.sleepREM > highscoreRecord.mostREMSleep {
                highscoreRecord.mostREMSleep = daily.sleepREM
                highscoreRecord.mostREMSleepDate = daily.date
            }
            
            // Update progress
            let progress = 0.2 + (Double(index + 1) / Double(newDailyAnalytics.count)) * 0.6 // 20% to 80%
            progressCallback(progress)
        }
        
        // Recalculate streaks (they might be affected by new data)
        progressCallback(0.8)
        let allDailyAnalytics = try getAllDailyAnalytics()
        try calculateSleepStreak(highscoreRecord, from: allDailyAnalytics)
        try calculateWorkoutStreak(highscoreRecord, from: allDailyAnalytics)
        
        highscoreRecord.lastUpdated = Date()
        try modelContext.save()
        
        progressCallback(1.0)
    }
    
    // Helper methods for updating specific periods
    private func updateWeeklyAnalyticsForWeek(_ weekStart: Date) throws {
        let calendar = Calendar.current
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        
        // Get or create weekly analytics for this week
        let existingWeekly = try getWeeklyAnalyticsForWeek(weekStart)
        let aggregatedData = try aggregateDailyDataForWeek(weekStart, weekEnd)
        
        if let existing = existingWeekly {
            updateWeeklyRecord(existing, with: aggregatedData, weekRange: (start: weekStart, end: weekEnd))
        } else {
            // Create new weekly record with next available ID
            let highestID = try getHighestWeeklyAnalyticsID()
            let weeklyAnalytics = createWeeklyAnalytics(
                id: highestID + 1,
                data: aggregatedData,
                weekRange: (start: weekStart, end: weekEnd)
            )
            modelContext.insert(weeklyAnalytics)
        }
        
        try modelContext.save()
    }
    
    private func updateMonthlyAnalyticsForMonth(_ monthStart: Date) throws {
        let calendar = Calendar.current
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? monthStart
        let components = calendar.dateComponents([.year, .month], from: monthStart)
        
        // Get or create monthly analytics for this month
        let existingMonthly = try getMonthlyAnalyticsForMonth(components.year!, components.month!)
        let aggregatedData = try aggregateDailyDataForMonth(monthStart, monthEnd) // Roll up daily data
        
        if let existing = existingMonthly {
            updateMonthlyRecord(existing, with: aggregatedData, monthRange: (start: monthStart, end: monthEnd))
        } else {
            let highestID = try getHighestMonthlyAnalyticsID()
            let monthlyAnalytics = createMonthlyAnalytics(
                id: highestID + 1,
                data: aggregatedData,
                year: components.year!,
                month: components.month!,
                monthRange: (start: monthStart, end: monthEnd)
            )
            modelContext.insert(monthlyAnalytics)
        }
        
        try modelContext.save()
    }
    
    private func updateYearlyAnalyticsForYear(_ yearStart: Date) throws {
        let calendar = Calendar.current
        let yearEnd = calendar.date(from: DateComponents(year: calendar.component(.year, from: yearStart), month: 12, day: 31))!
        let year = calendar.component(.year, from: yearStart)
        
        // Get or create yearly analytics for this year
        let existingYearly = try getYearlyAnalyticsForYear(year)
        let aggregatedData = try aggregateDailyDataForYear(yearStart, yearEnd) // Aggregate from monthly for performance
        
        if let existing = existingYearly {
            updateYearlyRecord(existing, with: aggregatedData, yearRange: (start: yearStart, end: yearEnd))
        } else {
            let highestID = try getHighestYearlyAnalyticsID()
            let yearlyAnalytics = createYearlyAnalytics(
                id: highestID + 1,
                data: aggregatedData,
                year: year,
                yearRange: (start: yearStart, end: yearEnd)
            )
            modelContext.insert(yearlyAnalytics)
        }
        
        try modelContext.save()
    }
    
    // MARK: - Private Query Helpers
    // Internal methods for finding specific analytics records
    private func getWeeklyAnalyticsForWeek(_ weekStart: Date) throws -> WeeklyAnalytics? {
        let descriptor = FetchDescriptor<WeeklyAnalytics>(
            predicate: #Predicate { analytics in
                analytics.startDate == weekStart
            }
        )
        return try modelContext.fetch(descriptor).first
    }
    
    private func getMonthlyAnalyticsForMonth(_ year: Int, _ month: Int) throws -> MonthlyAnalytics? {
        var descriptor = FetchDescriptor<MonthlyAnalytics>(
            predicate: #Predicate { analytics in
                analytics.year == year && analytics.month == month
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
    
    private func getYearlyAnalyticsForYear(_ year: Int) throws -> YearlyAnalytics? {
        var descriptor = FetchDescriptor<YearlyAnalytics>(
            predicate: #Predicate { analytics in
                analytics.year == year
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
    
    private func getHighestWeeklyAnalyticsID() throws -> Int {
        var descriptor = FetchDescriptor<WeeklyAnalytics>(
            sortBy: [SortDescriptor(\.id, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.id ?? 0
    }
    
    private func getHighestMonthlyAnalyticsID() throws -> Int {
        var descriptor = FetchDescriptor<MonthlyAnalytics>(
            sortBy: [SortDescriptor(\.id, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.id ?? 0
    }
    
    private func getHighestYearlyAnalyticsID() throws -> Int {
        var descriptor = FetchDescriptor<YearlyAnalytics>(
            sortBy: [SortDescriptor(\.id, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.id ?? 0
    }
    
    private func aggregateDailyDataForWeek(_ weekStart: Date, _ weekEnd: Date) throws -> HealthDataPoint {
        let descriptor = FetchDescriptor<DailyAnalytics>(
            predicate: #Predicate { analytics in
                analytics.date >= weekStart && analytics.date <= weekEnd
            }
        )
        
        let dailyRecords = try modelContext.fetch(descriptor)
        return aggregateHealthDataFromDailyAnalytics(dailyRecords)
    }
    
    private func aggregateDailyDataForMonth(_ monthStart: Date, _ monthEnd: Date) throws -> HealthDataPoint {
        let descriptor = FetchDescriptor<DailyAnalytics>(
            predicate: #Predicate { analytics in
                analytics.date >= monthStart && analytics.date <= monthEnd
            }
        )
        
        let dailyRecords = try modelContext.fetch(descriptor)
        return aggregateHealthDataFromDailyAnalytics(dailyRecords)
    }
    
    private func aggregateDailyDataForYear(_ yearStart: Date, _ yearEnd: Date) throws -> HealthDataPoint {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: yearStart)
        
        // Smart optimization: use monthly data instead of daily for yearly aggregation
        let descriptor = FetchDescriptor<MonthlyAnalytics>(
            predicate: #Predicate { analytics in
                analytics.year == year
            }
        )
        
        let monthlyRecords = try modelContext.fetch(descriptor)
        return aggregateHealthDataFromMonthlyAnalytics(monthlyRecords)
    }
    
    private func aggregateHealthDataFromDailyAnalytics(_ dailyRecords: [DailyAnalytics]) -> HealthDataPoint {
        var aggregated = HealthDataPoint()
        
        for record in dailyRecords {
            aggregated.steps += record.steps
            aggregated.cyclingDistance += record.cyclingDistance
            aggregated.walkingDistance += record.walkingDistance
            aggregated.runningDistance += record.runningDistance
            aggregated.swimmingDistance += record.swimmingDistance
            aggregated.swimmingStrokes += record.swimmingStrokes
            aggregated.crossCountrySkiingDistance += record.crossCountrySkiingDistance
            aggregated.downhillSnowSportsDistance += record.downhillSnowSportsDistance
            aggregated.energyActive += record.energyActive
            aggregated.energyResting += record.energyResting
            aggregated.heartbeats += record.heartbeats
            aggregated.stairsClimbed += record.stairsClimbed
            aggregated.exerciseMinutes += record.exerciseMinutes
            aggregated.standMinutes += record.standMinutes
            aggregated.sleepTotal += record.sleepTotal
            aggregated.sleepDeep += record.sleepDeep
            aggregated.sleepREM += record.sleepREM
        }
        
        return aggregated
    }
    
    private func aggregateHealthDataFromMonthlyAnalytics(_ monthlyRecords: [MonthlyAnalytics]) -> HealthDataPoint {
        var aggregated = HealthDataPoint()
        
        for record in monthlyRecords {
            aggregated.steps += record.steps
            aggregated.cyclingDistance += record.cyclingDistance
            aggregated.walkingDistance += record.walkingDistance
            aggregated.runningDistance += record.runningDistance
            aggregated.swimmingDistance += record.swimmingDistance
            aggregated.swimmingStrokes += record.swimmingStrokes
            aggregated.crossCountrySkiingDistance += record.crossCountrySkiingDistance
            aggregated.downhillSnowSportsDistance += record.downhillSnowSportsDistance
            aggregated.energyActive += record.energyActive
            aggregated.energyResting += record.energyResting
            aggregated.heartbeats += record.heartbeats
            aggregated.stairsClimbed += record.stairsClimbed
            aggregated.exerciseMinutes += record.exerciseMinutes
            aggregated.standMinutes += record.standMinutes
            aggregated.sleepTotal += record.sleepTotal
            aggregated.sleepDeep += record.sleepDeep
            aggregated.sleepREM += record.sleepREM
        }
        
        return aggregated
    }
    
    private func updateWeeklyRecord(_ record: WeeklyAnalytics, with data: HealthDataPoint, weekRange: (start: Date, end: Date)) {
        record.startDate = weekRange.start
        record.endDate = weekRange.end
        record.steps = data.steps
        record.cyclingDistance = data.cyclingDistance
        record.walkingDistance = data.walkingDistance
        record.runningDistance = data.runningDistance
        record.swimmingDistance = data.swimmingDistance
        record.swimmingStrokes = data.swimmingStrokes
        record.crossCountrySkiingDistance = data.crossCountrySkiingDistance
        record.downhillSnowSportsDistance = data.downhillSnowSportsDistance
        record.energyActive = data.energyActive
        record.energyResting = data.energyResting
        record.heartbeats = data.heartbeats
        record.stairsClimbed = data.stairsClimbed
        record.exerciseMinutes = data.exerciseMinutes
        record.standMinutes = data.standMinutes
        record.sleepTotal = data.sleepTotal
        record.sleepDeep = data.sleepDeep
        record.sleepREM = data.sleepREM
        record.recordedAt = Date()
    }
    
    private func updateMonthlyRecord(_ record: MonthlyAnalytics, with data: HealthDataPoint, monthRange: (start: Date, end: Date)) {
        record.startDate = monthRange.start
        record.endDate = monthRange.end
        record.steps = data.steps
        record.cyclingDistance = data.cyclingDistance
        record.walkingDistance = data.walkingDistance
        record.runningDistance = data.runningDistance
        record.swimmingDistance = data.swimmingDistance
        record.swimmingStrokes = data.swimmingStrokes
        record.crossCountrySkiingDistance = data.crossCountrySkiingDistance
        record.downhillSnowSportsDistance = data.downhillSnowSportsDistance
        record.energyActive = data.energyActive
        record.energyResting = data.energyResting
        record.heartbeats = data.heartbeats
        record.stairsClimbed = data.stairsClimbed
        record.exerciseMinutes = data.exerciseMinutes
        record.standMinutes = data.standMinutes
        record.sleepTotal = data.sleepTotal
        record.sleepDeep = data.sleepDeep
        record.sleepREM = data.sleepREM
        record.recordedAt = Date()
    }
    
    private func updateYearlyRecord(_ record: YearlyAnalytics, with data: HealthDataPoint, yearRange: (start: Date, end: Date)) {
        record.startDate = yearRange.start
        record.endDate = yearRange.end
        record.steps = data.steps
        record.cyclingDistance = data.cyclingDistance
        record.walkingDistance = data.walkingDistance
        record.runningDistance = data.runningDistance
        record.swimmingDistance = data.swimmingDistance
        record.swimmingStrokes = data.swimmingStrokes
        record.crossCountrySkiingDistance = data.crossCountrySkiingDistance
        record.downhillSnowSportsDistance = data.downhillSnowSportsDistance
        record.energyActive = data.energyActive
        record.energyResting = data.energyResting
        record.heartbeats = data.heartbeats
        record.stairsClimbed = data.stairsClimbed
        record.exerciseMinutes = data.exerciseMinutes
        record.standMinutes = data.standMinutes
        record.sleepTotal = data.sleepTotal
        record.sleepDeep = data.sleepDeep
        record.sleepREM = data.sleepREM
        record.recordedAt = Date()
    }
    
    private func createWeeklyAnalytics(id: Int, data: HealthDataPoint, weekRange: (start: Date, end: Date)) -> WeeklyAnalytics {
        return WeeklyAnalytics(
            id: id,
            startDate: weekRange.start,
            endDate: weekRange.end,
            steps: data.steps,
            cyclingDistance: data.cyclingDistance,
            walkingDistance: data.walkingDistance,
            runningDistance: data.runningDistance,
            swimmingDistance: data.swimmingDistance,
            swimmingStrokes: data.swimmingStrokes,
            crossCountrySkiingDistance: data.crossCountrySkiingDistance,
            downhillSnowSportsDistance: data.downhillSnowSportsDistance,
            energyActive: data.energyActive,
            energyResting: data.energyResting,
            heartbeats: data.heartbeats,
            stairsClimbed: data.stairsClimbed,
            exerciseMinutes: data.exerciseMinutes,
            standMinutes: data.standMinutes,
            sleepTotal: data.sleepTotal,
            sleepDeep: data.sleepDeep,
            sleepREM: data.sleepREM,
            recordedAt: Date()
        )
    }
    
    private func createMonthlyAnalytics(id: Int, data: HealthDataPoint, year: Int, month: Int, monthRange: (start: Date, end: Date)) -> MonthlyAnalytics {
        return MonthlyAnalytics(
            id: id,
            year: year,
            month: month,
            startDate: monthRange.start,
            endDate: monthRange.end,
            steps: data.steps,
            cyclingDistance: data.cyclingDistance,
            walkingDistance: data.walkingDistance,
            runningDistance: data.runningDistance,
            swimmingDistance: data.swimmingDistance,
            swimmingStrokes: data.swimmingStrokes,
            crossCountrySkiingDistance: data.crossCountrySkiingDistance,
            downhillSnowSportsDistance: data.downhillSnowSportsDistance,
            energyActive: data.energyActive,
            energyResting: data.energyResting,
            heartbeats: data.heartbeats,
            stairsClimbed: data.stairsClimbed,
            exerciseMinutes: data.exerciseMinutes,
            standMinutes: data.standMinutes,
            sleepTotal: data.sleepTotal,
            sleepDeep: data.sleepDeep,
            sleepREM: data.sleepREM,
            recordedAt: Date()
        )
    }
    
    private func createYearlyAnalytics(id: Int, data: HealthDataPoint, year: Int, yearRange: (start: Date, end: Date)) -> YearlyAnalytics {
        return YearlyAnalytics(
            id: id,
            year: year,
            startDate: yearRange.start,
            endDate: yearRange.end,
            steps: data.steps,
            cyclingDistance: data.cyclingDistance,
            walkingDistance: data.walkingDistance,
            runningDistance: data.runningDistance,
            swimmingDistance: data.swimmingDistance,
            swimmingStrokes: data.swimmingStrokes,
            crossCountrySkiingDistance: data.crossCountrySkiingDistance,
            downhillSnowSportsDistance: data.downhillSnowSportsDistance,
            energyActive: data.energyActive,
            energyResting: data.energyResting,
            heartbeats: data.heartbeats,
            stairsClimbed: data.stairsClimbed,
            exerciseMinutes: data.exerciseMinutes,
            standMinutes: data.standMinutes,
            sleepTotal: data.sleepTotal,
            sleepDeep: data.sleepDeep,
            sleepREM: data.sleepREM,
            recordedAt: Date()
        )
    }
    
    // MARK: - Highscore Data Export
    // Convert highscore records into formatted display metrics
    
    /// Get formatted highscore metrics for display
    public func getFormattedHighscores() throws -> [CardioMetric] {
        guard let highscoreRecord = try getHighscoreRecord() else {
            return []
        }
        
        var formattedHighscores: [CardioMetric] = []
        
        // Steps record
        if highscoreRecord.mostStepsInADay > 0 {
            formattedHighscores.append(CardioMetric(
                title: "Most Steps in a Day",
                value: formatValue(Double(highscoreRecord.mostStepsInADay), decimals: 0),
                unit: "steps",
                icon: "figure.walk",
                color: Color.blue
            ))
        }
        
        // Calories record
        if highscoreRecord.mostCaloriesInADay > 0 {
            formattedHighscores.append(CardioMetric(
                title: "Most Calories in a Day",
                value: formatValue(highscoreRecord.mostCaloriesInADay, decimals: 0),
                unit: "cal",
                icon: "flame.fill",
                color: Color.orange
            ))
        }
        
        // Exercise record
        if highscoreRecord.mostExerciseMinutesInADay > 0 {
            formattedHighscores.append(CardioMetric(
                title: "Most Exercise in a Day",
                value: formatTime(highscoreRecord.mostExerciseMinutesInADay),
                unit: "min",
                icon: "figure.run",
                color: Color.green
            ))
        }
        
        // Distance records
        if highscoreRecord.longestWalk > 0 {
            formattedHighscores.append(CardioMetric(
                title: "Longest Walk",
                value: formatDistance(highscoreRecord.longestWalk),
                unit: "km",
                icon: "figure.walk",
                color: Color.green
            ))
        }
        
        if highscoreRecord.longestBikeRide > 0 {
            formattedHighscores.append(CardioMetric(
                title: "Longest Bike Ride",
                value: formatDistance(highscoreRecord.longestBikeRide),
                unit: "km",
                icon: "bicycle",
                color: Color.blue
            ))
        }
        
        if highscoreRecord.longestSwim > 0 {
            formattedHighscores.append(CardioMetric(
                title: "Longest Swim",
                value: formatDistance(highscoreRecord.longestSwim),
                unit: "km",
                icon: "figure.pool.swim",
                color: Color.blue
            ))
        }
        
        // Sleep records
        if highscoreRecord.longestSleep > 0 {
            formattedHighscores.append(CardioMetric(
                title: "Longest Sleep",
                value: formatTime(highscoreRecord.longestSleep),
                unit: "min",
                icon: "bed.double.fill",
                color: Color.blue
            ))
        }
        
        if highscoreRecord.mostDeepSleep > 0 {
            formattedHighscores.append(CardioMetric(
                title: "Most Deep Sleep",
                value: formatTime(highscoreRecord.mostDeepSleep),
                unit: "min",
                icon: "moon.zzz.fill",
                color: Color.blue
            ))
        }
        
        if highscoreRecord.mostREMSleep > 0 {
            formattedHighscores.append(CardioMetric(
                title: "Most REM Sleep",
                value: formatTime(highscoreRecord.mostREMSleep),
                unit: "min",
                icon: "brain.head.profile",
                color: Color.red
            ))
        }
        
        // Streak records
        if highscoreRecord.sleepStreakRecord > 0 {
            formattedHighscores.append(CardioMetric(
                title: "Sleep Streak Record",
                value: "\(highscoreRecord.sleepStreakRecord)",
                unit: "days",
                icon: "calendar",
                color: Color.blue
            ))
        }
        
        if highscoreRecord.workoutStreakRecord > 0 {
            formattedHighscores.append(CardioMetric(
                title: "Workout Streak Record",
                value: "\(highscoreRecord.workoutStreakRecord)",
                unit: "days",
                icon: "calendar",
                color: Color.green
            ))
        }
        
        return formattedHighscores
    }
    
    // MARK: - UI Data Export
    // Convert stored analytics into formatted CardioMetrics for display
    
    /// Get formatted metrics for widget display (filtered to most important ones)
    public func getWidgetMetrics() throws -> [CardioMetric] {
        guard let today = try getDailyAnalytics(for: Date()) else {
            return []
        }
        
        return [
            CardioMetric(
                title: "Steps",
                value: formatValue(Double(today.steps), decimals: 0),
                unit: "steps",
                icon: "figure.walk",
                color: Color.blue
            ),
            CardioMetric(
                title: "Active Energy",
                value: formatValue(today.energyActive, decimals: 0),
                unit: "cal",
                icon: "flame.fill",
                color: Color.orange
            ),
            CardioMetric(
                title: "Exercise Time",
                value: formatTime(today.exerciseMinutes),
                unit: "min",
                icon: "figure.run",
                color: Color.green
            )
        ]
    }
    
    /// Get formatted metrics for a specific date range
    public func getCustomRangeMetrics(from startDate: Date, to endDate: Date) throws -> [CardioMetric] {
        let dailyRecords = try getDailyAnalytics(from: startDate, to: endDate)
        let aggregated = aggregateHealthDataFromDailyAnalytics(dailyRecords)
        let days = dailyRecords.count
        
        return formatHealthDataPoint(aggregated, days: days)
    }
    
    /// Get metrics for standard periods (today, this week, etc.)
    public func getPeriodMetrics(for period: String) throws -> [CardioMetric] {
        let calendar = Calendar.current
        let now = Date()
        
        switch period.lowercased() {
        case "today":
            guard let today = try getDailyAnalytics(for: now) else { return [] }
            return formatDailyAnalytics(today)
            
        case "thisweek":
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let weekEnd = calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? now
            return try getCustomRangeMetrics(from: weekStart, to: weekEnd)
            
        case "thismonth":
            let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let monthEnd = calendar.dateInterval(of: .month, for: now)?.end ?? now
            return try getCustomRangeMetrics(from: monthStart, to: monthEnd)
            
        case "lastmonth":
            let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            let monthStart = calendar.dateInterval(of: .month, for: lastMonth)?.start ?? now
            let monthEnd = calendar.dateInterval(of: .month, for: lastMonth)?.end ?? now
            return try getCustomRangeMetrics(from: monthStart, to: monthEnd)
            
        case "last30days":
            let startDate = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return try getCustomRangeMetrics(from: startDate, to: now)
            
        case "lastyear":
            let lastYear = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            let yearStart = calendar.dateInterval(of: .year, for: lastYear)?.start ?? now
            let yearEnd = calendar.dateInterval(of: .year, for: lastYear)?.end ?? now
            return try getCustomRangeMetrics(from: yearStart, to: yearEnd)
            
        case "last365days":
            let startDate = calendar.date(byAdding: .day, value: -365, to: now) ?? now
            return try getCustomRangeMetrics(from: startDate, to: now)
            
        case "alltime":
            let allDaily = try getAllDailyAnalytics()
            if allDaily.isEmpty { return [] }
            let earliest = allDaily.min(by: { $0.date < $1.date })?.date ?? now
            return try getCustomRangeMetrics(from: earliest, to: now)
            
        default:
            return []
        }
    }
    
    /// Get time series data for charts
    public func getTimeSeriesData(metricType: String, from startDate: Date, to endDate: Date) throws -> TimeSeriesData {
        let dailyRecords = try getDailyAnalytics(from: startDate, to: endDate)
        let dataPoints: [TimeSeriesDataPoint] = dailyRecords.compactMap { daily in
            let (value, unit, _) = extractMetricValue(from: daily, type: metricType)
            guard value > 0 else { return nil }
            
            return TimeSeriesDataPoint(
                date: daily.date,
                value: value,
                formattedValue: formatValue(value, decimals: metricType.contains("distance") ? 2 : 0),
                unit: unit
            )
        }
        
        let (title, icon, color) = getMetricDisplayInfo(for: metricType)
        
        return TimeSeriesData(
            dataPoints: dataPoints,
            metricTitle: title,
            metricIcon: icon,
            metricColor: color,
            metricUnit: dataPoints.first?.unit ?? ""
        )
    }
    
    // MARK: - Private Formatting Helpers
    
    private func formatDailyAnalytics(_ daily: DailyAnalytics) -> [CardioMetric] {
        return [
            CardioMetric(title: "Steps", value: formatValue(Double(daily.steps), decimals: 0), unit: "steps", icon: "figure.walk", color: Color.blue),
            CardioMetric(title: "Walking Distance", value: formatDistance(daily.walkingDistance), unit: "km", icon: "figure.walk", color: Color.green),
            CardioMetric(title: "Running Distance", value: formatDistance(daily.runningDistance), unit: "km", icon: "figure.run", color: Color.red),
            CardioMetric(title: "Cycling Distance", value: formatDistance(daily.cyclingDistance), unit: "km", icon: "bicycle", color: Color.blue),
            CardioMetric(title: "Active Energy", value: formatValue(daily.energyActive, decimals: 0), unit: "cal", icon: "flame.fill", color: Color.orange),
            CardioMetric(title: "Resting Energy", value: formatValue(daily.energyResting, decimals: 0), unit: "cal", icon: "bed.double.fill", color: Color.gray),
            CardioMetric(title: "Exercise Time", value: formatTime(daily.exerciseMinutes), unit: "min", icon: "figure.run", color: Color.green),
            CardioMetric(title: "Stand Time", value: formatTime(daily.standMinutes), unit: "min", icon: "figure.stand", color: Color.blue),
            CardioMetric(title: "Sleep Total", value: formatTime(daily.sleepTotal), unit: "min", icon: "bed.double.fill", color: .indigo),
            CardioMetric(title: "Deep Sleep", value: formatTime(daily.sleepDeep), unit: "min", icon: "moon.zzz.fill", color: Color.blue),
            CardioMetric(title: "REM Sleep", value: formatTime(daily.sleepREM), unit: "min", icon: "brain.head.profile", color: .pink)
        ].filter { $0.value != "0" && $0.value != "0.0" } // Only show metrics with data
    }
    
    private func formatHealthDataPoint(_ data: HealthDataPoint, days: Int) -> [CardioMetric] {
        return [
            CardioMetric(title: "Steps", value: formatValue(Double(data.steps), decimals: 0), unit: "steps", icon: "figure.walk", color: Color.blue),
            CardioMetric(title: "Walking Distance", value: formatDistance(data.walkingDistance), unit: "km", icon: "figure.walk", color: Color.green),
            CardioMetric(title: "Running Distance", value: formatDistance(data.runningDistance), unit: "km", icon: "figure.run", color: Color.red),
            CardioMetric(title: "Cycling Distance", value: formatDistance(data.cyclingDistance), unit: "km", icon: "bicycle", color: Color.blue),
            CardioMetric(title: "Active Energy", value: formatValue(data.energyActive, decimals: 0), unit: "cal", icon: "flame.fill", color: Color.orange),
            CardioMetric(title: "Resting Energy", value: formatValue(data.energyResting, decimals: 0), unit: "cal", icon: "bed.double.fill", color: Color.gray),
            CardioMetric(title: "Exercise Time", value: formatTime(data.exerciseMinutes), unit: "min", icon: "figure.run", color: Color.green),
            CardioMetric(title: "Stand Time", value: formatTime(data.standMinutes), unit: "min", icon: "figure.stand", color: Color.blue),
            CardioMetric(title: "Sleep Total", value: formatTime(data.sleepTotal), unit: "min", icon: "bed.double.fill", color: .indigo)
        ].filter { $0.value != "0" && $0.value != "0.0" }
    }
    
    private func extractMetricValue(from daily: DailyAnalytics, type: String) -> (value: Double, unit: String, color: Color) {
        switch type.lowercased() {
        case "steps": return (Double(daily.steps), "steps", Color.blue)
        case "walkingdistance": return (daily.walkingDistance / 1000, "km", Color.green)
        case "runningdistance": return (daily.runningDistance / 1000, "km", Color.red)
        case "cyclingdistance": return (daily.cyclingDistance / 1000, "km", Color.blue)
        case "activeenergy": return (daily.energyActive, "cal", Color.orange)
        case "restingenergy": return (daily.energyResting, "cal", Color.gray)
        case "exercisetime": return (Double(daily.exerciseMinutes), "min", Color.green)
        case "standtime": return (Double(daily.standMinutes), "min", Color.blue)
        case "sleep": return (Double(daily.sleepTotal), "min", Color.blue)
        default: return (0, "", Color.gray)
        }
    }
    
    private func getMetricDisplayInfo(for type: String) -> (title: String, icon: String, color: Color) {
        switch type.lowercased() {
        case "steps": return ("Steps", "figure.walk", Color.blue)
        case "walkingdistance": return ("Walking Distance", "figure.walk", Color.green)
        case "runningdistance": return ("Running Distance", "figure.run", Color.red)
        case "cyclingdistance": return ("Cycling Distance", "bicycle", Color.blue)
        case "activeenergy": return ("Active Energy", "flame.fill", Color.orange)
        case "restingenergy": return ("Resting Energy", "bed.double.fill", Color.gray)
        case "exercisetime": return ("Exercise Time", "figure.run", Color.green)
        case "standtime": return ("Stand Time", "figure.stand", Color.blue)
        case "sleep": return ("Sleep", "bed.double.fill", Color.blue)
        default: return ("Unknown", "questionmark", Color.gray)
        }
    }
    
    private func formatValue(_ value: Double, decimals: Int) -> String {
        if decimals == 0 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.\(decimals)f", value)
        }
    }
    
    private func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000
        if km < 0.1 {
            return String(format: "%.0f", meters) // Show meters if less than 100m
        } else {
            return String(format: "%.2f", km)
        }
    }
    
    private func formatTime(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        }
    }
}
