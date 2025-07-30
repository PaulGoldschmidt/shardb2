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
        // Re-detect the actual first HealthKit record
        try await setUserFirstHealthKitRecord(user)
    }
    
    // HealthKit authorization status
    public func getHealthKitAuthorizationStatus(for type: HKQuantityTypeIdentifier = .stepCount) -> HKAuthorizationStatus {
        return healthKitManager.getAuthorizationStatus(for: type)
    }
    
    
    // Database initialization with progress callback
    public func initializeDatabase(for user: User, progressCallback: @escaping (InitializationProgress) -> Void) async throws {
        try await databaseInitializer.initializeDatabase(for: user, progressCallback: progressCallback)
    }
    
    // Incremental data updates with progress callback
    public func updateMissingData(for user: User, progressCallback: @escaping (InitializationProgress) -> Void) async throws {
        try await dataUpdater.updateMissingData(for: user, progressCallback: progressCallback)
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
    
    // MARK: - Comprehensive Data Refresh
    
    public func refreshAllData(for user: User, progressCallback: @escaping (InitializationProgress) -> Void) async throws {
        let now = Date()
        let lastRefresh = user.lastProcessedAt
        let lastHighscoreUpdate = user.highscoresLastUpdated
        
        progressCallback(InitializationProgress(percentage: 0.0, currentTask: "Starting data refresh..."))
        
        // Phase 1: Update missing HealthKit data (0-30%)
        try await dataUpdater.updateMissingData(for: user) { progress in
            let adjustedProgress = InitializationProgress(
                percentage: progress.percentage * 0.3, // Scale to 30%
                currentTask: progress.currentTask
            )
            progressCallback(adjustedProgress)
        }
        
        // Phase 2: Update current week analytics (30-50%)
        progressCallback(InitializationProgress(percentage: 30.0, currentTask: "Refreshing current week..."))
        try refreshCurrentPeriodAnalytics(from: lastRefresh, to: now, progressCallback: { progress in
            let adjustedProgress = 30.0 + (progress * 20.0) // 30-50%
            progressCallback(InitializationProgress(percentage: adjustedProgress, currentTask: "Refreshing current period analytics..."))
        })
        
        // Phase 3: Update highscores with only new data (50-80%)
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
    
    public func getHighscoreRecord() throws -> HighscoreRecord? {
        var descriptor = FetchDescriptor<HighscoreRecord>()
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
    
    
    private func updateHighscoresFromDailyAnalytics(_ highscore: HighscoreRecord) throws {
        // Get all daily analytics to analyze
        let allDailyAnalytics = try getAllDailyAnalytics()
        
        // Process each day to find records
        for daily in allDailyAnalytics {
            // Daily activity records
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
            
            // Distance records (treating as potential longest single activities)
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
            
            // Sleep records
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
        
        // Calculate streaks
        try calculateSleepStreak(highscore, from: allDailyAnalytics)
        try calculateWorkoutStreak(highscore, from: allDailyAnalytics)
    }
    
    private func calculateSleepStreak(_ highscore: HighscoreRecord, from dailyAnalytics: [DailyAnalytics]) throws {
        let sortedDays = dailyAnalytics.sorted { $0.date < $1.date }
        
        var currentStreak = 0
        var maxStreak = 0
        var maxStreakStart: Date?
        var maxStreakEnd: Date?
        var currentStreakStart: Date?
        
        for daily in sortedDays {
            if daily.sleepTotal > 0 { // Has sleep data
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
            if daily.exerciseMinutes > 0 { // Has workout data
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
        
        if maxStreak > highscore.workoutStreakRecord {
            highscore.workoutStreakRecord = maxStreak
            highscore.workoutStreakRecordStartDate = maxStreakStart
            highscore.workoutStreakRecordEndDate = maxStreakEnd
        }
    }
    
    private func refreshCurrentPeriodAnalytics(from startDate: Date, to endDate: Date, progressCallback: @escaping (Double) -> Void) throws {
        let calendar = Calendar.current
        
        // Update current week (if affected)
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: endDate)?.start ?? endDate
        if startDate <= currentWeekStart {
            progressCallback(0.25)
            try updateWeeklyAnalyticsForWeek(currentWeekStart)
        }
        
        // Update current month (if affected)
        let currentMonthStart = calendar.dateInterval(of: .month, for: endDate)?.start ?? endDate
        if startDate <= currentMonthStart {
            progressCallback(0.5)
            try updateMonthlyAnalyticsForMonth(currentMonthStart)
        }
        
        // Update current year (if affected)
        let currentYearStart = calendar.dateInterval(of: .year, for: endDate)?.start ?? endDate
        if startDate <= currentYearStart {
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
        let aggregatedData = try aggregateDailyDataForMonth(monthStart, monthEnd)
        
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
        let aggregatedData = try aggregateDailyDataForYear(yearStart, yearEnd)
        
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
    
    // Helper methods that need to be accessible (moved from DataUpdater)
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
        let descriptor = FetchDescriptor<DailyAnalytics>(
            predicate: #Predicate { analytics in
                analytics.date >= yearStart && analytics.date <= yearEnd
            }
        )
        
        let dailyRecords = try modelContext.fetch(descriptor)
        return aggregateHealthDataFromDailyAnalytics(dailyRecords)
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
            sleepREM: data.sleepREM
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
            sleepREM: data.sleepREM
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
            sleepREM: data.sleepREM
        )
    }
}
