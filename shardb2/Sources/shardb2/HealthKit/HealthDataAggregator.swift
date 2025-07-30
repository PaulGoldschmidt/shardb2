import Foundation
import HealthKit

public final class HealthDataAggregator {
    private let healthStore = HKHealthStore()
    
    public init() {}
    
    public func fetchAllHealthData(from startDate: Date, to endDate: Date, progressCallback: @escaping (InitializationProgress) -> Void) throws -> [Date: HealthDataPoint] {
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
            
            let samples = try fetchSamples(for: quantityType, predicate: predicate)
            
            // Enhanced logging for sample details
            progressCallback(InitializationProgress(
                percentage: progress + 0.5,
                currentTask: "Processing \(samples.count) \(typeName) samples..."
            ))
            
            processSamples(samples, into: &dailyData, calendar: calendar)
        }
        
        // Fetch sleep analysis data separately as it's a category type
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            progressCallback(InitializationProgress(
                percentage: 8.0,
                currentTask: "Fetching Sleep Analysis data..."
            ))
            
            let sleepSamples = try fetchSleepSamples(for: sleepType, predicate: predicate)
            
            progressCallback(InitializationProgress(
                percentage: 8.5,
                currentTask: "Processing \(sleepSamples.count) Sleep Analysis samples..."
            ))
            
            processSleepSamples(sleepSamples, into: &dailyData, calendar: calendar)
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
    
    private func fetchSamples(for quantityType: HKQuantityType, predicate: NSPredicate) throws -> [HKQuantitySample] {
        var result: [HKQuantitySample] = []
        var queryError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        
        let query = HKSampleQuery(
            sampleType: quantityType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
        ) { _, samples, error in
            if let error = error {
                queryError = HealthKitError.queryFailed(error)
            } else {
                result = samples as? [HKQuantitySample] ?? []
            }
            semaphore.signal()
        }
        
        healthStore.execute(query)
        semaphore.wait()
        
        if let error = queryError {
            throw error
        }
        
        return result
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
    
    private func fetchSleepSamples(for categoryType: HKCategoryType, predicate: NSPredicate) throws -> [HKCategorySample] {
        var result: [HKCategorySample] = []
        var queryError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        
        let query = HKSampleQuery(
            sampleType: categoryType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
        ) { _, samples, error in
            if let error = error {
                queryError = HealthKitError.queryFailed(error)
            } else {
                result = samples as? [HKCategorySample] ?? []
            }
            semaphore.signal()
        }
        
        healthStore.execute(query)
        semaphore.wait()
        
        if let error = queryError {
            throw error
        }
        
        return result
    }
    
    private func processSleepSamples(_ samples: [HKCategorySample], into dailyData: inout [Date: HealthDataPoint], calendar: Calendar) {
        for sample in samples {
            let day = calendar.startOfDay(for: sample.startDate)
            
            var dataPoint = dailyData[day] ?? HealthDataPoint()
            
            // Calculate sleep duration in minutes
            let sleepDuration = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
            let sleepMinutes = Int(sleepDuration)
            
            // Process different sleep stages
            switch sample.value {
            case HKCategoryValueSleepAnalysis.inBed.rawValue,
                 HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                dataPoint.sleepTotal += sleepMinutes
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                dataPoint.sleepTotal += sleepMinutes
                // Core sleep can be considered as regular sleep
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                dataPoint.sleepTotal += sleepMinutes
                dataPoint.sleepDeep += sleepMinutes
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                dataPoint.sleepTotal += sleepMinutes
                dataPoint.sleepREM += sleepMinutes
            default:
                // Handle other sleep states if needed
                break
            }
            
            dailyData[day] = dataPoint
        }
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