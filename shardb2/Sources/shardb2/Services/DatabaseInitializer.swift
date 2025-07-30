import Foundation
import SwiftData
import HealthKit

public final class DatabaseInitializer {
    private let modelContext: ModelContext
    private let healthDataAggregator = HealthDataAggregator()
    
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    public func initializeDatabase(for user: User, progressCallback: @escaping (InitializationProgress) -> Void) async throws {
        try await performInitialization(for: user, progressCallback: progressCallback)
    }
    
    private func performInitialization(for user: User, progressCallback: @escaping (InitializationProgress) -> Void) async throws {
        let startDate = user.firstHealthKitRecord
        let endDate = Date()
        
        // Phase 1: Fetch all HealthKit data (1% to 10% of total progress)
        progressCallback(InitializationProgress(percentage: 0.0, currentTask: "Starting database initialization..."))
        
        let dailyHealthData = try await healthDataAggregator.fetchAllHealthData(from: startDate, to: endDate) { progress in
            progressCallback(progress)
        }
        let totalDays = dailyHealthData.count
        
        progressCallback(InitializationProgress(percentage: 10.0, currentTask: "HealthKit data fetching completed"))
        
        // Phase 2: Create daily analytics (30% of progress, 10-40%)
        try createDailyAnalytics(from: dailyHealthData, totalDays: totalDays, progressCallback: progressCallback)
        
        // Phase 3: Create weekly analytics (20% of progress, 40-60%)
        try createWeeklyAnalytics(from: dailyHealthData, progressCallback: progressCallback)
        
        // Phase 4: Create monthly analytics (15% of progress, 60-75%)
        try createMonthlyAnalytics(from: dailyHealthData, progressCallback: progressCallback)
        
        // Phase 5: Create yearly analytics (15% of progress, 75-90%)
        try createYearlyAnalytics(from: dailyHealthData, progressCallback: progressCallback)
        
        // Phase 6: Calculate highscores (5% of progress, 90-95%)
        progressCallback(InitializationProgress(percentage: 90.0, currentTask: "Calculating personal records..."))
        try calculateHighscores()
        
        // Phase 7: Update user (5% of progress, 95-100%)
        progressCallback(InitializationProgress(percentage: 95.0, currentTask: "Updating user record..."))
        user.lastProcessedAt = Date()
        try modelContext.save()
        
        progressCallback(InitializationProgress(percentage: 100.0, currentTask: "Database initialization completed!"))
    }
    
    private func createDailyAnalytics(from dailyData: [Date: HealthDataPoint], totalDays: Int, progressCallback: @escaping (InitializationProgress) -> Void) throws {
        let sortedDates = dailyData.keys.sorted()
        var processedDays = 0
        var currentID = 1
        
        for date in sortedDates {
            guard let dataPoint = dailyData[date] else { continue }
            
            let dailyAnalytics = DailyAnalytics(
                id: currentID,
                date: date,
                steps: dataPoint.steps,
                cyclingDistance: dataPoint.cyclingDistance,
                walkingDistance: dataPoint.walkingDistance,
                runningDistance: dataPoint.runningDistance,
                swimmingDistance: dataPoint.swimmingDistance,
                swimmingStrokes: dataPoint.swimmingStrokes,
                crossCountrySkiingDistance: dataPoint.crossCountrySkiingDistance,
                downhillSnowSportsDistance: dataPoint.downhillSnowSportsDistance,
                energyActive: dataPoint.energyActive,
                energyResting: dataPoint.energyResting,
                heartbeats: dataPoint.heartbeats,
                stairsClimbed: dataPoint.stairsClimbed,
                exerciseMinutes: dataPoint.exerciseMinutes,
                standMinutes: dataPoint.standMinutes,
                sleepTotal: dataPoint.sleepTotal,
                sleepDeep: dataPoint.sleepDeep,
                sleepREM: dataPoint.sleepREM
            )
            
            modelContext.insert(dailyAnalytics)
            currentID += 1
            processedDays += 1
            
            // Update progress (10% to 40%)
            let progress = 10.0 + (Double(processedDays) / Double(totalDays)) * 30.0
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            progressCallback(InitializationProgress(
                percentage: progress,
                currentTask: "Processing daily analytics for \(dateFormatter.string(from: date))..."))
            
            // Save in batches to manage memory
            if processedDays % 100 == 0 {
                try modelContext.save()
            }
        }
        
        try modelContext.save()
    }
    
    private func createWeeklyAnalytics(from dailyData: [Date: HealthDataPoint], progressCallback: @escaping (InitializationProgress) -> Void) throws {
        let calendar = Calendar.current
        
        // Get all daily analytics from the database (already stored)
        let allDailyAnalytics = try getAllDailyAnalyticsFromDB()
        
        guard !allDailyAnalytics.isEmpty else { return }
        
        var weeklyData: [Date: HealthDataPoint] = [:]
        
        // Group daily analytics by weeks
        for dailyAnalytic in allDailyAnalytics {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: dailyAnalytic.date)?.start ?? dailyAnalytic.date
            
            if weeklyData[weekStart] == nil {
                weeklyData[weekStart] = HealthDataPoint()
            }
            
            // Aggregate from daily analytics in database
            let dailyPoint = convertDailyAnalyticsToHealthDataPoint(dailyAnalytic)
            weeklyData[weekStart] = aggregateHealthData(weeklyData[weekStart]!, with: dailyPoint)
        }
        
        // Create weekly analytics records
        let totalWeeks = weeklyData.count
        var processedWeeks = 0
        var currentID = 1
        
        for (weekStart, dataPoint) in weeklyData.sorted(by: { $0.key < $1.key }) {
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            
            let weeklyAnalytics = WeeklyAnalytics(
                id: currentID,
                startDate: weekStart,
                endDate: weekEnd,
                steps: dataPoint.steps,
                cyclingDistance: dataPoint.cyclingDistance,
                walkingDistance: dataPoint.walkingDistance,
                runningDistance: dataPoint.runningDistance,
                swimmingDistance: dataPoint.swimmingDistance,
                swimmingStrokes: dataPoint.swimmingStrokes,
                crossCountrySkiingDistance: dataPoint.crossCountrySkiingDistance,
                downhillSnowSportsDistance: dataPoint.downhillSnowSportsDistance,
                energyActive: dataPoint.energyActive,
                energyResting: dataPoint.energyResting,
                heartbeats: dataPoint.heartbeats,
                stairsClimbed: dataPoint.stairsClimbed,
                exerciseMinutes: dataPoint.exerciseMinutes,
                standMinutes: dataPoint.standMinutes,
                sleepTotal: dataPoint.sleepTotal,
                sleepDeep: dataPoint.sleepDeep,
                sleepREM: dataPoint.sleepREM
            )
            
            modelContext.insert(weeklyAnalytics)
            currentID += 1
            processedWeeks += 1
            
            // Update progress (40% to 60%)
            let progress = 40.0 + (Double(processedWeeks) / Double(totalWeeks)) * 20.0
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            progressCallback(InitializationProgress(
                percentage: progress,
                currentTask: "Processing weekly analytics for week of \(dateFormatter.string(from: weekStart))..."))
        }
        
        try modelContext.save()
    }
    
    private func createMonthlyAnalytics(from dailyData: [Date: HealthDataPoint], progressCallback: @escaping (InitializationProgress) -> Void) throws {
        let calendar = Calendar.current
        
        // Get all daily analytics from the database (already stored)
        let allDailyAnalytics = try getAllDailyAnalyticsFromDB()
        
        guard !allDailyAnalytics.isEmpty else { return }
        
        var monthlyData: [String: HealthDataPoint] = [:]
        
        // Group daily analytics by months
        for dailyAnalytic in allDailyAnalytics {
            let components = calendar.dateComponents([.year, .month], from: dailyAnalytic.date)
            let monthKey = "\(components.year!)-\(components.month!)"
            
            if monthlyData[monthKey] == nil {
                monthlyData[monthKey] = HealthDataPoint()
            }
            
            // Aggregate from daily analytics in database
            let dailyPoint = convertDailyAnalyticsToHealthDataPoint(dailyAnalytic)
            monthlyData[monthKey] = aggregateHealthData(monthlyData[monthKey]!, with: dailyPoint)
        }
        
        // Create monthly analytics records
        let totalMonths = monthlyData.count
        var processedMonths = 0
        var currentID = 1
        
        for (monthKey, dataPoint) in monthlyData.sorted(by: { $0.key < $1.key }) {
            let components = monthKey.split(separator: "-")
            let year = Int(components[0])!
            let month = Int(components[1])!
            
            let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
            let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)!
            
            let monthlyAnalytics = MonthlyAnalytics(
                id: currentID,
                year: year,
                month: month,
                startDate: monthStart,
                endDate: monthEnd,
                steps: dataPoint.steps,
                cyclingDistance: dataPoint.cyclingDistance,
                walkingDistance: dataPoint.walkingDistance,
                runningDistance: dataPoint.runningDistance,
                swimmingDistance: dataPoint.swimmingDistance,
                swimmingStrokes: dataPoint.swimmingStrokes,
                crossCountrySkiingDistance: dataPoint.crossCountrySkiingDistance,
                downhillSnowSportsDistance: dataPoint.downhillSnowSportsDistance,
                energyActive: dataPoint.energyActive,
                energyResting: dataPoint.energyResting,
                heartbeats: dataPoint.heartbeats,
                stairsClimbed: dataPoint.stairsClimbed,
                exerciseMinutes: dataPoint.exerciseMinutes,
                standMinutes: dataPoint.standMinutes,
                sleepTotal: dataPoint.sleepTotal,
                sleepDeep: dataPoint.sleepDeep,
                sleepREM: dataPoint.sleepREM
            )
            
            modelContext.insert(monthlyAnalytics)
            currentID += 1
            processedMonths += 1
            
            // Update progress (60% to 75%)
            let progress = 60.0 + (Double(processedMonths) / Double(totalMonths)) * 15.0
            let monthName = DateFormatter().monthSymbols[month - 1]
            progressCallback(InitializationProgress(
                percentage: progress,
                currentTask: "Processing monthly analytics for \(monthName) \(year)..."))
        }
        
        try modelContext.save()
    }
    
    private func createYearlyAnalytics(from dailyData: [Date: HealthDataPoint], progressCallback: @escaping (InitializationProgress) -> Void) throws {
        // Get all monthly analytics from the database (already stored)
        let allMonthlyAnalytics = try getAllMonthlyAnalyticsFromDB()
        
        guard !allMonthlyAnalytics.isEmpty else { return }
        
        var yearlyData: [Int: HealthDataPoint] = [:]
        
        // Group monthly analytics by years
        for monthlyAnalytic in allMonthlyAnalytics {
            let year = monthlyAnalytic.year
            
            if yearlyData[year] == nil {
                yearlyData[year] = HealthDataPoint()
            }
            
            // Aggregate from monthly analytics in database
            let monthlyPoint = convertMonthlyAnalyticsToHealthDataPoint(monthlyAnalytic)
            yearlyData[year] = aggregateHealthData(yearlyData[year]!, with: monthlyPoint)
        }
        
        // Create yearly analytics records
        let totalYears = yearlyData.count
        var processedYears = 0
        var currentID = 1
        
        for (year, dataPoint) in yearlyData.sorted(by: { $0.key < $1.key }) {
            let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            let yearEnd = calendar.date(from: DateComponents(year: year, month: 12, day: 31))!
            
            let yearlyAnalytics = YearlyAnalytics(
                id: currentID,
                year: year,
                startDate: yearStart,
                endDate: yearEnd,
                steps: dataPoint.steps,
                cyclingDistance: dataPoint.cyclingDistance,
                walkingDistance: dataPoint.walkingDistance,
                runningDistance: dataPoint.runningDistance,
                swimmingDistance: dataPoint.swimmingDistance,
                swimmingStrokes: dataPoint.swimmingStrokes,
                crossCountrySkiingDistance: dataPoint.crossCountrySkiingDistance,
                downhillSnowSportsDistance: dataPoint.downhillSnowSportsDistance,
                energyActive: dataPoint.energyActive,
                energyResting: dataPoint.energyResting,
                heartbeats: dataPoint.heartbeats,
                stairsClimbed: dataPoint.stairsClimbed,
                exerciseMinutes: dataPoint.exerciseMinutes,
                standMinutes: dataPoint.standMinutes,
                sleepTotal: dataPoint.sleepTotal,
                sleepDeep: dataPoint.sleepDeep,
                sleepREM: dataPoint.sleepREM
            )
            
            modelContext.insert(yearlyAnalytics)
            currentID += 1
            processedYears += 1
            
            // Update progress (75% to 90%)
            let progress = 75.0 + (Double(processedYears) / Double(totalYears)) * 15.0
            progressCallback(InitializationProgress(
                percentage: progress,
                currentTask: "Processing yearly analytics for \(year)..."))
        }
        
        try modelContext.save()
    }
    
    private func aggregateHealthData(_ existing: HealthDataPoint, with new: HealthDataPoint) -> HealthDataPoint {
        var aggregated = existing
        
        aggregated.steps += new.steps
        aggregated.cyclingDistance += new.cyclingDistance
        aggregated.walkingDistance += new.walkingDistance
        aggregated.runningDistance += new.runningDistance
        aggregated.swimmingDistance += new.swimmingDistance
        aggregated.swimmingStrokes += new.swimmingStrokes
        aggregated.crossCountrySkiingDistance += new.crossCountrySkiingDistance
        aggregated.downhillSnowSportsDistance += new.downhillSnowSportsDistance
        aggregated.energyActive += new.energyActive
        aggregated.energyResting += new.energyResting
        aggregated.heartbeats += new.heartbeats
        aggregated.stairsClimbed += new.stairsClimbed
        aggregated.exerciseMinutes += new.exerciseMinutes
        aggregated.standMinutes += new.standMinutes
        aggregated.sleepTotal += new.sleepTotal
        aggregated.sleepDeep += new.sleepDeep
        aggregated.sleepREM += new.sleepREM
        
        return aggregated
    }
    
    private func calculateHighscores() throws {
        // Create a temporary HealthStatsLibrary instance to access highscore methods
        let healthStatsLibrary = HealthStatsLibrary(modelContext: modelContext)
        
        // Get existing highscore record or create new one
        let existingRecord = try healthStatsLibrary.getHighscoreRecord()
        let highscoreRecord = existingRecord ?? HighscoreRecord()
        
        if existingRecord == nil {
            modelContext.insert(highscoreRecord)
        }
        
        // Calculate all highscores from existing daily analytics (full calculation during init)
        let allDailyAnalytics = try healthStatsLibrary.getAllDailyAnalytics()
        
        // Process each day to find records
        for daily in allDailyAnalytics {
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
        }
        
        highscoreRecord.lastUpdated = Date()
        try modelContext.save()
    }
    
    // MARK: - Helper Functions for Database Aggregation
    
    private func getAllDailyAnalyticsFromDB() throws -> [DailyAnalytics] {
        let descriptor = FetchDescriptor<DailyAnalytics>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    private func getAllMonthlyAnalyticsFromDB() throws -> [MonthlyAnalytics] {
        let descriptor = FetchDescriptor<MonthlyAnalytics>(
            sortBy: [SortDescriptor(\.year, order: .forward), SortDescriptor(\.month, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    private func convertDailyAnalyticsToHealthDataPoint(_ daily: DailyAnalytics) -> HealthDataPoint {
        var point = HealthDataPoint()
        point.steps = daily.steps
        point.cyclingDistance = daily.cyclingDistance
        point.walkingDistance = daily.walkingDistance
        point.runningDistance = daily.runningDistance
        point.swimmingDistance = daily.swimmingDistance
        point.swimmingStrokes = daily.swimmingStrokes
        point.crossCountrySkiingDistance = daily.crossCountrySkiingDistance
        point.downhillSnowSportsDistance = daily.downhillSnowSportsDistance
        point.energyActive = daily.energyActive
        point.energyResting = daily.energyResting
        point.heartbeats = daily.heartbeats
        point.stairsClimbed = daily.stairsClimbed
        point.exerciseMinutes = daily.exerciseMinutes
        point.standMinutes = daily.standMinutes
        point.sleepTotal = daily.sleepTotal
        point.sleepDeep = daily.sleepDeep
        point.sleepREM = daily.sleepREM
        return point
    }
    
    private func convertMonthlyAnalyticsToHealthDataPoint(_ monthly: MonthlyAnalytics) -> HealthDataPoint {
        var point = HealthDataPoint()
        point.steps = monthly.steps
        point.cyclingDistance = monthly.cyclingDistance
        point.walkingDistance = monthly.walkingDistance
        point.runningDistance = monthly.runningDistance
        point.swimmingDistance = monthly.swimmingDistance
        point.swimmingStrokes = monthly.swimmingStrokes
        point.crossCountrySkiingDistance = monthly.crossCountrySkiingDistance
        point.downhillSnowSportsDistance = monthly.downhillSnowSportsDistance
        point.energyActive = monthly.energyActive
        point.energyResting = monthly.energyResting
        point.heartbeats = monthly.heartbeats
        point.stairsClimbed = monthly.stairsClimbed
        point.exerciseMinutes = monthly.exerciseMinutes
        point.standMinutes = monthly.standMinutes
        point.sleepTotal = monthly.sleepTotal
        point.sleepDeep = monthly.sleepDeep
        point.sleepREM = monthly.sleepREM
        return point
    }
}