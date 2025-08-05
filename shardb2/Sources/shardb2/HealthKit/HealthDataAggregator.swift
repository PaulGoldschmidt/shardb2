import Foundation
import HealthKit

public final class HealthDataAggregator {
    private let healthStore = HKHealthStore()
    
    public init() {}
    
    public func findEarliestHealthKitSample() async throws -> Date {
        let quantityTypes = getHealthKitQuantityTypes()
        var earliestDate: Date?
        
        // Check quantity types (steps, heart rate, etc.)
        for quantityType in quantityTypes {
            if let sampleDate = try await fetchEarliestSampleDate(for: quantityType) {
                if earliestDate == nil || sampleDate < earliestDate! {
                    earliestDate = sampleDate
                }
            }
        }
        
        // Check sleep analysis (category type)
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis),
           let sleepDate = try await fetchEarliestSleepSampleDate(for: sleepType) {
            if earliestDate == nil || sleepDate < earliestDate! {
                earliestDate = sleepDate
            }
        }
        
        // Return the earliest date found, or fallback to HealthKit launch date
        return earliestDate ?? DateComponents(calendar: Calendar.current, year: 2014, month: 9, day: 1).date!
    }
    
    public func fetchAllHealthData(from startDate: Date, to endDate: Date, progressCallback: @escaping (InitializationProgress) -> Void) async throws -> [Date: HealthDataPoint] {
        let quantityTypes = getHealthKitQuantityTypes()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        var dailyData: [Date: HealthDataPoint] = [:]
        let calendar = Calendar.current
        
        // Initialize all days with empty data points
        var currentDate = calendar.startOfDay(for: startDate)
        let finalDate = calendar.startOfDay(for: endDate)
        
        while currentDate <= finalDate {
            dailyData[currentDate] = HealthDataPoint()
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        // Fetch data for each quantity type
        for (index, quantityType) in quantityTypes.enumerated() {
            let typeName = getHumanReadableName(for: quantityType.identifier)
            let progress = 1.0 + (Double(index) / Double(quantityTypes.count)) * 7.0 // 1% to 8%
            
            progressCallback(InitializationProgress(
                percentage: progress,
                currentTask: "Fetching \(typeName) data..."
            ))
            
            do {
                let samples = try await fetchSamples(for: quantityType, predicate: predicate)
                
                progressCallback(InitializationProgress(
                    percentage: progress + 0.5,
                    currentTask: "Processing \(samples.count) \(typeName) samples..."
                ))
                
                processSamples(samples, into: &dailyData, calendar: calendar)
            } catch {
                // If fetching fails, the data type will remain at default values (0)
                // which is already set when initializing dailyData
                progressCallback(InitializationProgress(
                    percentage: progress + 0.5,
                    currentTask: "Skipped \(typeName) (no data available)"
                ))
            }
        }
        
        // Fetch sleep analysis data separately as it's a category type
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            progressCallback(InitializationProgress(
                percentage: 8.0,
                currentTask: "Fetching Sleep Analysis data..."
            ))
            
            do {
                let sleepSamples = try await fetchSleepSamples(for: sleepType, predicate: predicate)
                
                progressCallback(InitializationProgress(
                    percentage: 8.5,
                    currentTask: "Processing \(sleepSamples.count) Sleep Analysis samples..."
                ))
                
                processSleepSamples(sleepSamples, into: &dailyData, calendar: calendar)
            } catch {
                // If sleep data fetching fails, sleep values remain at default (0)
                progressCallback(InitializationProgress(
                    percentage: 8.5,
                    currentTask: "Skipped Sleep Analysis (no data available)"
                ))
            }
        }
        
        // Final logging of processed data
        let totalDays = dailyData.count
        let daysWithSteps = dailyData.values.filter { $0.steps > 0 }.count
        
        progressCallback(InitializationProgress(
            percentage: 9.0,
            currentTask: "Processed \(totalDays) days of data (\(daysWithSteps) days with steps)"
        ))
        
        return dailyData
    }
    
    private func fetchSamples(for quantityType: HKQuantityType, predicate: NSPredicate) async throws -> [HKQuantitySample] {
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                } else {
                    continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
                }
            }
            
            healthStore.execute(query)
        }
    }
    
    private func processSamples(_ samples: [HKQuantitySample], into dailyData: inout [Date: HealthDataPoint], calendar: Calendar) {
        for sample in samples {
            let day = calendar.startOfDay(for: sample.endDate)
            
            guard var dataPoint = dailyData[day] else { continue }
            
            switch sample.quantityType.identifier {
            case HKQuantityTypeIdentifier.stepCount.rawValue:
                dataPoint.steps += Int(sample.quantity.doubleValue(for: .count()))
            case HKQuantityTypeIdentifier.distanceCycling.rawValue:
                dataPoint.cyclingDistance += sample.quantity.doubleValue(for: .meter())
            case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
                dataPoint.walkingDistance += sample.quantity.doubleValue(for: .meter())
            case HKQuantityTypeIdentifier.distanceSwimming.rawValue:
                dataPoint.swimmingDistance += sample.quantity.doubleValue(for: .meter())
            case HKQuantityTypeIdentifier.swimmingStrokeCount.rawValue:
                dataPoint.swimmingStrokes += Int(sample.quantity.doubleValue(for: .count()))
            case HKQuantityTypeIdentifier.distanceCrossCountrySkiing.rawValue:
                dataPoint.crossCountrySkiingDistance += sample.quantity.doubleValue(for: .meter())
            case HKQuantityTypeIdentifier.distanceDownhillSnowSports.rawValue:
                dataPoint.downhillSnowSportsDistance += sample.quantity.doubleValue(for: .meter())
            case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                dataPoint.energyActive += sample.quantity.doubleValue(for: .kilocalorie())
            case HKQuantityTypeIdentifier.basalEnergyBurned.rawValue:
                dataPoint.energyResting += sample.quantity.doubleValue(for: .kilocalorie())
            case HKQuantityTypeIdentifier.heartRate.rawValue:
                dataPoint.heartbeats += Int(sample.quantity.doubleValue(for: .count().unitDivided(by: .minute())) * (sample.endDate.timeIntervalSince(sample.startDate) / 60.0))
            case HKQuantityTypeIdentifier.flightsClimbed.rawValue:
                dataPoint.stairsClimbed += Int(sample.quantity.doubleValue(for: .count()))
            case HKQuantityTypeIdentifier.appleExerciseTime.rawValue:
                dataPoint.exerciseMinutes += Int(sample.quantity.doubleValue(for: .minute()))
            case HKQuantityTypeIdentifier.appleStandTime.rawValue:
                dataPoint.standMinutes += Int(sample.quantity.doubleValue(for: .minute()))
            default:
                break
            }
            
            dailyData[day] = dataPoint
        }
    }
    
    private func getHealthKitQuantityTypes() -> [HKQuantityType] {
        let identifiers: [HKQuantityTypeIdentifier] = [
            .stepCount, .distanceCycling, .distanceWalkingRunning, .distanceSwimming,
            .swimmingStrokeCount, .distanceCrossCountrySkiing, .distanceDownhillSnowSports,
            .activeEnergyBurned, .basalEnergyBurned, .heartRate, .flightsClimbed,
            .appleExerciseTime, .appleStandTime
        ]
        
        return identifiers.compactMap { HKQuantityType.quantityType(forIdentifier: $0) }
    }
    
    private func getHumanReadableName(for identifier: String) -> String {
        switch identifier {
        case HKQuantityTypeIdentifier.stepCount.rawValue:
            return "Step Count"
        case HKQuantityTypeIdentifier.distanceCycling.rawValue:
            return "Cycling Distance"
        case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
            return "Walking & Running Distance"
        case HKQuantityTypeIdentifier.distanceSwimming.rawValue:
            return "Swimming Distance"
        case HKQuantityTypeIdentifier.swimmingStrokeCount.rawValue:
            return "Swimming Strokes"
        case HKQuantityTypeIdentifier.distanceCrossCountrySkiing.rawValue:
            return "Cross Country Skiing Distance"
        case HKQuantityTypeIdentifier.distanceDownhillSnowSports.rawValue:
            return "Downhill Snow Sports Distance"
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
            return "Active Energy Burned"
        case HKQuantityTypeIdentifier.basalEnergyBurned.rawValue:
            return "Resting Energy Burned"
        case HKQuantityTypeIdentifier.heartRate.rawValue:
            return "Heart Rate"
        case HKQuantityTypeIdentifier.flightsClimbed.rawValue:
            return "Flights Climbed"
        case HKQuantityTypeIdentifier.appleExerciseTime.rawValue:
            return "Exercise Time"
        case HKQuantityTypeIdentifier.appleStandTime.rawValue:
            return "Stand Time"
        default:
            return "Health Data"
        }
    }
    
    private func fetchSleepSamples(for categoryType: HKCategoryType, predicate: NSPredicate) async throws -> [HKCategorySample] {
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: categoryType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                } else {
                    continuation.resume(returning: samples as? [HKCategorySample] ?? [])
                }
            }
            
            healthStore.execute(query)
        }
    }
    
    private func processSleepSamples(_ samples: [HKCategorySample], into dailyData: inout [Date: HealthDataPoint], calendar: Calendar) {
        // Group samples by day and source to avoid double-counting
        var samplesByDay: [Date: [String: [HKCategorySample]]] = [:]
        
        for sample in samples {
            let day = calendar.startOfDay(for: sample.startDate)
            let sourceId = sample.sourceRevision.source.bundleIdentifier
            
            if samplesByDay[day] == nil {
                samplesByDay[day] = [:]
            }
            if samplesByDay[day]![sourceId] == nil {
                samplesByDay[day]![sourceId] = []
            }
            samplesByDay[day]![sourceId]!.append(sample)
        }
        
        // Process each day, using only the highest priority source
        for (day, sourceDict) in samplesByDay {
            let prioritizedSourceId = selectPrioritySource(from: Array(sourceDict.keys))
            let prioritizedSamples = sourceDict[prioritizedSourceId] ?? []
            
            var dataPoint = dailyData[day] ?? HealthDataPoint()
            
            // Process only samples from the prioritized source
            for sample in prioritizedSamples {
                let sleepDuration = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                let sleepMinutes = Int(sleepDuration)
                
                switch sample.value {
                case HKCategoryValueSleepAnalysis.inBed.rawValue,
                     HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                    dataPoint.sleepTotal += sleepMinutes
                case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                    dataPoint.sleepTotal += sleepMinutes
                case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                    dataPoint.sleepTotal += sleepMinutes
                    dataPoint.sleepDeep += sleepMinutes
                case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                    dataPoint.sleepTotal += sleepMinutes
                    dataPoint.sleepREM += sleepMinutes
                default:
                    break
                }
            }
            
            dailyData[day] = dataPoint
        }
    }
    
    private func selectPrioritySource(from sourceIds: [String]) -> String {
        // Priority order: Apple Watch > iPhone > Third-party apps
        let priorities = [
            "com.apple.health.8A0DD10F-5ABF-4314-AD7E-C77CF88BA901", // Apple Watch
            "com.apple.Health",                                       // iPhone Health app
            "com.apple.health"                                        // iPhone Health app (alternative)
        ]
        
        for priority in priorities {
            if sourceIds.contains(priority) {
                return priority
            }
        }
        
        // If no known sources, return the first one (alphabetically for consistency)
        return sourceIds.sorted().first ?? sourceIds.first ?? ""
    }
}

public struct HealthDataPoint {
    public var steps: Int = 0
    public var cyclingDistance: Double = 0.0
    public var walkingDistance: Double = 0.0
    public var runningDistance: Double = 0.0
    public var swimmingDistance: Double = 0.0
    public var swimmingStrokes: Int = 0
    public var crossCountrySkiingDistance: Double = 0.0
    public var downhillSnowSportsDistance: Double = 0.0
    public var energyActive: Double = 0.0
    public var energyResting: Double = 0.0
    public var heartbeats: Int = 0
    public var stairsClimbed: Int = 0
    public var exerciseMinutes: Int = 0
    public var standMinutes: Int = 0
    public var sleepTotal: Int = 0
    public var sleepDeep: Int = 0
    public var sleepREM: Int = 0
}

extension HealthDataAggregator {
    private func fetchEarliestSampleDate(for quantityType: HKQuantityType) async throws -> Date? {
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil, // No date filter - we want the earliest sample ever
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                } else if let sample = samples?.first {
                    continuation.resume(returning: sample.startDate)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            
            healthStore.execute(query)
        }
    }
    
    private func fetchEarliestSleepSampleDate(for categoryType: HKCategoryType) async throws -> Date? {
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: categoryType,
                predicate: nil, // No date filter - we want the earliest sample ever
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                } else if let sample = samples?.first {
                    continuation.resume(returning: sample.startDate)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            
            healthStore.execute(query)
        }
    }
}