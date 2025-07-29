import Foundation
import SwiftData

@Model
public final class DailyAnalytics {
    @Attribute(.unique) public var date: Date
    
    // Activity metrics
    public var steps: Int
    public var cyclingDistance: Double // meters
    public var walkingDistance: Double // meters
    public var runningDistance: Double // meters
    public var swimmingDistance: Double // meters
    public var swimmingStrokes: Int
    public var crossCountrySkiingDistance: Double // meters
    public var downhillSnowSportsDistance: Double // meters
    
    // Energy metrics
    public var energyActive: Double // kilocalories
    public var energyResting: Double // kilocalories
    
    // Health metrics
    public var heartbeats: Int
    public var stairsClimbed: Int
    
    // Time-based metrics
    public var exerciseMinutes: Int
    public var standMinutes: Int
    public var sleepTotal: Int // minutes
    public var sleepDeep: Int // minutes
    public var sleepREM: Int // minutes
    
    // Metadata
    public var recordedAt: Date
    
    public init(
        date: Date,
        steps: Int = 0,
        cyclingDistance: Double = 0.0,
        walkingDistance: Double = 0.0,
        runningDistance: Double = 0.0,
        swimmingDistance: Double = 0.0,
        swimmingStrokes: Int = 0,
        crossCountrySkiingDistance: Double = 0.0,
        downhillSnowSportsDistance: Double = 0.0,
        energyActive: Double = 0.0,
        energyResting: Double = 0.0,
        heartbeats: Int = 0,
        stairsClimbed: Int = 0,
        exerciseMinutes: Int = 0,
        standMinutes: Int = 0,
        sleepTotal: Int = 0,
        sleepDeep: Int = 0,
        sleepREM: Int = 0,
        recordedAt: Date = Date()
    ) {
        self.date = date
        self.steps = steps
        self.cyclingDistance = cyclingDistance
        self.walkingDistance = walkingDistance
        self.runningDistance = runningDistance
        self.swimmingDistance = swimmingDistance
        self.swimmingStrokes = swimmingStrokes
        self.crossCountrySkiingDistance = crossCountrySkiingDistance
        self.downhillSnowSportsDistance = downhillSnowSportsDistance
        self.energyActive = energyActive
        self.energyResting = energyResting
        self.heartbeats = heartbeats
        self.stairsClimbed = stairsClimbed
        self.exerciseMinutes = exerciseMinutes
        self.standMinutes = standMinutes
        self.sleepTotal = sleepTotal
        self.sleepDeep = sleepDeep
        self.sleepREM = sleepREM
        self.recordedAt = recordedAt
    }
}