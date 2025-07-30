import Foundation
import SwiftData
import HealthKit

public final class DataUpdater {
    private let modelContext: ModelContext
    private let healthDataAggregator = HealthDataAggregator()
    
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    public func updateMissingData(for user: User, progressCallback: @escaping (InitializationProgress) -> Void) async throws {
        try await performDataUpdate(for: user, progressCallback: progressCallback)
    }
    
    private func performDataUpdate(for user: User, progressCallback: @escaping (InitializationProgress) -> Void) async throws {
        let calendar = Calendar.current
        let now = Date()
        
        // Calculate date range - start from lastProcessedAt day (to overwrite)
        let startDate = calendar.startOfDay(for: user.lastProcessedAt)
        let endDate = calendar.startOfDay(for: now)
        
        guard startDate <= endDate else {
            progressCallback(InitializationProgress(percentage: 100.0, currentTask: "No missing data to process"))
            return
        }
        
        progressCallback(InitializationProgress(percentage: 0.0, currentTask: "Starting incremental data update..."))
        
        // Phase 1: Fetch missing HealthKit data (0-15%)
        let dailyHealthData = try await healthDataAggregator.fetchAllHealthData(from: startDate, to: now) { progress in
            let adjustedProgress = InitializationProgress(
                percentage: progress.percentage * 0.15, // Scale to 15%
                currentTask: progress.currentTask
            )
            progressCallback(adjustedProgress)
        }
        
        progressCallback(InitializationProgress(percentage: 15.0, currentTask: "HealthKit data fetching completed"))
        
        // Phase 2: Update daily analytics (15-40%)
        try updateDailyAnalytics(from: dailyHealthData, progressCallback: progressCallback)
        
        // Phase 3: Update weekly analytics (40-65%)
        try updateWeeklyAnalytics(for: startDate, to: endDate, progressCallback: progressCallback)
        
        // Phase 4: Update monthly analytics (65-85%)
        try updateMonthlyAnalytics(for: startDate, to: endDate, progressCallback: progressCallback)
        
        // Phase 5: Update yearly analytics (85-95%)
        try updateYearlyAnalytics(for: startDate, to: endDate, progressCallback: progressCallback)
        
        // Phase 6: Update user record (95-100%)
        progressCallback(InitializationProgress(percentage: 95.0, currentTask: "Updating user record..."))
        user.lastProcessedAt = now
        try modelContext.save()
        
        progressCallback(InitializationProgress(percentage: 100.0, currentTask: "Incremental update completed!"))
    }
    
    private func updateDailyAnalytics(from dailyData: [Date: HealthDataPoint], progressCallback: @escaping (InitializationProgress) -> Void) throws {
        let sortedDates = dailyData.keys.sorted()
        let totalDays = sortedDates.count
        var processedDays = 0
        
        // Get the highest existing ID to continue the sequence
        let highestID = try getHighestDailyAnalyticsID()
        var currentID = highestID + 1
        
        for date in sortedDates {
            guard let dataPoint = dailyData[date] else { continue }
            
            // Check if record already exists (to overwrite)
            if let existingRecord = try getDailyAnalyticsForDate(date) {
                // Update existing record
                existingRecord.steps = dataPoint.steps
                existingRecord.cyclingDistance = dataPoint.cyclingDistance
                existingRecord.walkingDistance = dataPoint.walkingDistance
                existingRecord.runningDistance = dataPoint.runningDistance
                existingRecord.swimmingDistance = dataPoint.swimmingDistance
                existingRecord.swimmingStrokes = dataPoint.swimmingStrokes
                existingRecord.crossCountrySkiingDistance = dataPoint.crossCountrySkiingDistance
                existingRecord.downhillSnowSportsDistance = dataPoint.downhillSnowSportsDistance
                existingRecord.energyActive = dataPoint.energyActive
                existingRecord.energyResting = dataPoint.energyResting
                existingRecord.heartbeats = dataPoint.heartbeats
                existingRecord.stairsClimbed = dataPoint.stairsClimbed
                existingRecord.exerciseMinutes = dataPoint.exerciseMinutes
                existingRecord.standMinutes = dataPoint.standMinutes
                existingRecord.sleepTotal = dataPoint.sleepTotal
                existingRecord.sleepDeep = dataPoint.sleepDeep
                existingRecord.sleepREM = dataPoint.sleepREM
                existingRecord.recordedAt = Date()
            } else {
                // Create new record
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
            }
            
            processedDays += 1
            
            // Update progress (15% to 40%)
            let progress = 15.0 + (Double(processedDays) / Double(totalDays)) * 25.0
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            progressCallback(InitializationProgress(
                percentage: progress,
                currentTask: "Updating daily analytics for \(dateFormatter.string(from: date))..."))
            
            // Save in batches
            if processedDays % 50 == 0 {
                try modelContext.save()
            }
        }
        
        try modelContext.save()
    }
    
    private func updateWeeklyAnalytics(for startDate: Date, to endDate: Date, progressCallback: @escaping (InitializationProgress) -> Void) throws {
        _ = Calendar.current
        
        // Get all weeks that need updating
        let weeksToUpdate = getWeekRanges(from: startDate, to: endDate)
        let totalWeeks = weeksToUpdate.count
        var processedWeeks = 0
        
        let highestID = try getHighestWeeklyAnalyticsID()
        var currentID = highestID + 1
        
        for weekRange in weeksToUpdate {
            let aggregatedData = try aggregateDailyDataForWeek(weekRange.start, weekRange.end)
            
            // Check if weekly record exists (to overwrite)
            if let existingRecord = try getWeeklyAnalyticsForWeek(weekRange.start) {
                updateWeeklyRecord(existingRecord, with: aggregatedData, weekRange: weekRange)
            } else {
                let weeklyAnalytics = createWeeklyAnalytics(
                    id: currentID,
                    data: aggregatedData,
                    weekRange: weekRange
                )
                modelContext.insert(weeklyAnalytics)
                currentID += 1
            }
            
            processedWeeks += 1
            
            let progress = 40.0 + (Double(processedWeeks) / Double(totalWeeks)) * 25.0
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            progressCallback(InitializationProgress(
                percentage: progress,
                currentTask: "Updating weekly analytics for week of \(dateFormatter.string(from: weekRange.start))..."))
        }
        
        try modelContext.save()
    }
    
    private func updateMonthlyAnalytics(for startDate: Date, to endDate: Date, progressCallback: @escaping (InitializationProgress) -> Void) throws {
        let calendar = Calendar.current
        
        // Get all months that need updating
        let monthsToUpdate = getMonthRanges(from: startDate, to: endDate)
        let totalMonths = monthsToUpdate.count
        var processedMonths = 0
        
        let highestID = try getHighestMonthlyAnalyticsID()
        var currentID = highestID + 1
        
        for monthRange in monthsToUpdate {
            let aggregatedData = try aggregateDailyDataForMonth(monthRange.start, monthRange.end)
            let components = calendar.dateComponents([.year, .month], from: monthRange.start)
            
            // Check if monthly record exists (to overwrite)
            if let existingRecord = try getMonthlyAnalyticsForMonth(components.year!, components.month!) {
                updateMonthlyRecord(existingRecord, with: aggregatedData, monthRange: monthRange)
            } else {
                let monthlyAnalytics = createMonthlyAnalytics(
                    id: currentID,
                    data: aggregatedData,
                    year: components.year!,
                    month: components.month!,
                    monthRange: monthRange
                )
                modelContext.insert(monthlyAnalytics)
                currentID += 1
            }
            
            processedMonths += 1
            
            let progress = 65.0 + (Double(processedMonths) / Double(totalMonths)) * 20.0
            let monthName = DateFormatter().monthSymbols[components.month! - 1]
            progressCallback(InitializationProgress(
                percentage: progress,
                currentTask: "Updating monthly analytics for \(monthName) \(components.year!)..."))
        }
        
        try modelContext.save()
    }
    
    private func updateYearlyAnalytics(for startDate: Date, to endDate: Date, progressCallback: @escaping (InitializationProgress) -> Void) throws {
        let calendar = Calendar.current
        
        // Get all years that need updating
        let yearsToUpdate = getYearRanges(from: startDate, to: endDate)
        let totalYears = yearsToUpdate.count
        var processedYears = 0
        
        let highestID = try getHighestYearlyAnalyticsID()
        var currentID = highestID + 1
        
        for yearRange in yearsToUpdate {
            let aggregatedData = try aggregateDailyDataForYear(yearRange.start, yearRange.end)
            let year = calendar.component(.year, from: yearRange.start)
            
            // Check if yearly record exists (to overwrite)
            if let existingRecord = try getYearlyAnalyticsForYear(year) {
                updateYearlyRecord(existingRecord, with: aggregatedData, yearRange: yearRange)
            } else {
                let yearlyAnalytics = createYearlyAnalytics(
                    id: currentID,
                    data: aggregatedData,
                    year: year,
                    yearRange: yearRange
                )
                modelContext.insert(yearlyAnalytics)
                currentID += 1
            }
            
            processedYears += 1
            
            let progress = 85.0 + (Double(processedYears) / Double(totalYears)) * 10.0
            progressCallback(InitializationProgress(
                percentage: progress,
                currentTask: "Updating yearly analytics for \(year)..."))
        }
        
        try modelContext.save()
    }
    
    // MARK: - Helper Functions
    
    private func getHighestDailyAnalyticsID() throws -> Int {
        var descriptor = FetchDescriptor<DailyAnalytics>(
            sortBy: [SortDescriptor(\.id, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.id ?? 0
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
    
    private func getDailyAnalyticsForDate(_ date: Date) throws -> DailyAnalytics? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        var descriptor = FetchDescriptor<DailyAnalytics>(
            predicate: #Predicate { $0.date == startOfDay }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
    
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
    
    private func getWeekRanges(from startDate: Date, to endDate: Date) -> [(start: Date, end: Date)] {
        let calendar = Calendar.current
        var ranges: [(start: Date, end: Date)] = []
        var currentDate = startDate
        
        while currentDate <= endDate {
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: currentDate) else {
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? endDate
                continue
            }
            
            let weekStart = weekInterval.start
            let weekEnd = calendar.date(byAdding: .day, value: -1, to: weekInterval.end) ?? weekInterval.end
            
            ranges.append((start: weekStart, end: weekEnd))
            currentDate = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? endDate
        }
        
        return ranges
    }
    
    private func getMonthRanges(from startDate: Date, to endDate: Date) -> [(start: Date, end: Date)] {
        let calendar = Calendar.current
        var ranges: [(start: Date, end: Date)] = []
        var currentDate = startDate
        
        while currentDate <= endDate {
            let components = calendar.dateComponents([.year, .month], from: currentDate)
            let monthStart = calendar.date(from: components)!
            let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)!
            
            ranges.append((start: monthStart, end: monthEnd))
            currentDate = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? endDate
        }
        
        return ranges
    }
    
    private func getYearRanges(from startDate: Date, to endDate: Date) -> [(start: Date, end: Date)] {
        let calendar = Calendar.current
        var ranges: [(start: Date, end: Date)] = []
        var currentDate = startDate
        
        while currentDate <= endDate {
            let year = calendar.component(.year, from: currentDate)
            let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            let yearEnd = calendar.date(from: DateComponents(year: year, month: 12, day: 31))!
            
            ranges.append((start: yearStart, end: yearEnd))
            currentDate = calendar.date(byAdding: .year, value: 1, to: yearStart) ?? endDate
        }
        
        return ranges
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
        
        // Aggregate from monthly analytics instead of daily analytics for better performance
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