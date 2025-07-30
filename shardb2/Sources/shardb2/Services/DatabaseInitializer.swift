import Foundation
import SwiftData
import HealthKit

public final class DatabaseInitializer {
    private let modelContext: ModelContext
    private let healthDataAggregator = HealthDataAggregator()
    
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    public func initializeDatabase(for user: User, progressCallback: @escaping (InitializationProgress) -> Void) throws {
        try performInitialization(for: user, progressCallback: progressCallback)
    }
    
    private func performInitialization(for user: User, progressCallback: @escaping (InitializationProgress) -> Void) throws {
        // Use a much earlier start date to capture all available HealthKit data
        let startDate = DateComponents(calendar: Calendar.current, year: 2014, month: 9, day: 1).date! // iOS 8 HealthKit launch
        let endDate = Date()
        
        // Phase 1: Fetch all HealthKit data (1% to 10% of total progress)
        progressCallback(InitializationProgress(percentage: 0.0, currentTask: "Starting database initialization..."))
        
        let dailyHealthData = try healthDataAggregator.fetchAllHealthData(from: startDate, to: endDate) { progress in
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
        
        // Phase 6: Update user (10% of progress, 90-100%)
        progressCallback(InitializationProgress(percentage: 90.0, currentTask: "Updating user record..."))
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
        let sortedDates = dailyData.keys.sorted()
        
        guard let firstDate = sortedDates.first, let lastDate = sortedDates.last else { return }
        
        var weeklyData: [Date: HealthDataPoint] = [:]
        var currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: firstDate)?.start ?? firstDate
        let finalWeekStart = calendar.dateInterval(of: .weekOfYear, for: lastDate)?.start ?? lastDate
        
        // Group daily data by weeks
        for date in sortedDates {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            
            if weeklyData[weekStart] == nil {
                weeklyData[weekStart] = HealthDataPoint()
            }
            
            if let dailyPoint = dailyData[date] {
                weeklyData[weekStart] = aggregateHealthData(weeklyData[weekStart]!, with: dailyPoint)
            }
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
        let sortedDates = dailyData.keys.sorted()
        
        var monthlyData: [String: HealthDataPoint] = [:]
        
        // Group daily data by months
        for date in sortedDates {
            let components = calendar.dateComponents([.year, .month], from: date)
            let monthKey = "\(components.year!)-\(components.month!)"
            
            if monthlyData[monthKey] == nil {
                monthlyData[monthKey] = HealthDataPoint()
            }
            
            if let dailyPoint = dailyData[date] {
                monthlyData[monthKey] = aggregateHealthData(monthlyData[monthKey]!, with: dailyPoint)
            }
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
        let calendar = Calendar.current
        let sortedDates = dailyData.keys.sorted()
        
        var yearlyData: [Int: HealthDataPoint] = [:]
        
        // Group daily data by years
        for date in sortedDates {
            let year = calendar.component(.year, from: date)
            
            if yearlyData[year] == nil {
                yearlyData[year] = HealthDataPoint()
            }
            
            if let dailyPoint = dailyData[date] {
                yearlyData[year] = aggregateHealthData(yearlyData[year]!, with: dailyPoint)
            }
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
}