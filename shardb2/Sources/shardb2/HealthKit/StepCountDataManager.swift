import Foundation
import HealthKit

public final class StepCountDataManager {
    private let healthStore = HKHealthStore()
    
    public init() {}
    
    public func fetchLatestStepCount() async throws -> (stepCount: Int, date: Date) {
        let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: now,
            options: .strictStartDate
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepCountType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                
                guard let result = result,
                      let sum = result.sumQuantity() else {
                    continuation.resume(throwing: HealthKitError.dataNotFound)
                    return
                }
                
                let stepCount = Int(sum.doubleValue(for: HKUnit.count()))
                continuation.resume(returning: (stepCount: stepCount, date: startOfDay))
            }
            
            healthStore.execute(query)
        }
    }
    
    public func fetchStepCountLast7Days() async throws -> [(date: Date, stepCount: Int)] {
        let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        
        let calendar = Calendar.current
        let now = Date()
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        
        let predicate = HKQuery.predicateForSamples(
            withStart: sevenDaysAgo,
            end: now,
            options: .strictStartDate
        )
        
        let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: stepCountType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sortDescriptors
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                
                guard let samples = samples as? [HKQuantitySample] else {
                    continuation.resume(throwing: HealthKitError.dataNotFound)
                    return
                }
                
                // Group samples by day and sum step counts
                var dailySteps: [String: Int] = [:]
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                
                for sample in samples {
                    let dayKey = dateFormatter.string(from: sample.endDate)
                    let steps = Int(sample.quantity.doubleValue(for: HKUnit.count()))
                    dailySteps[dayKey, default: 0] += steps
                }
                
                // Convert back to array of tuples sorted by date
                let results = dailySteps.compactMap { dayKey, stepCount -> (date: Date, stepCount: Int)? in
                    guard let date = dateFormatter.date(from: dayKey) else { return nil }
                    return (date: date, stepCount: stepCount)
                }.sorted { $0.date > $1.date }
                
                continuation.resume(returning: results)
            }
            
            healthStore.execute(query)
        }
    }
}