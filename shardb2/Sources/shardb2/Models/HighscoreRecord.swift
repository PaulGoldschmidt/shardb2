import Foundation
import SwiftData

@Model
public final class HighscoreRecord {
    @Attribute(.unique) public var id: Int
    
    // Heart Rate Records
    public var peakHeartRate: Double // BPM
    public var peakHeartRateDate: Date?
    
    // Running Records
    public var peakRunningSpeed: Double // m/s
    public var peakRunningSpeedDate: Date?
    public var peakRunningPower: Double // Watts (if available)
    public var peakRunningPowerDate: Date?
    public var longestRun: Double // meters
    public var longestRunDate: Date?
    
    // Cycling Records
    public var longestBikeRide: Double // meters
    public var longestBikeRideDate: Date?
    
    // Swimming Records
    public var longestSwim: Double // meters
    public var longestSwimDate: Date?
    
    // Walking Records
    public var longestWalk: Double // meters
    public var longestWalkDate: Date?
    
    // Workout Records
    public var longestWorkout: Int // minutes
    public var longestWorkoutDate: Date?
    
    // Daily Activity Records
    public var mostStepsInADay: Int
    public var mostStepsInADayDate: Date?
    public var mostCaloriesInADay: Double // kcal (active + resting)
    public var mostCaloriesInADayDate: Date?
    public var mostExerciseMinutesInADay: Int
    public var mostExerciseMinutesInADayDate: Date?
    
    // Sleep Records
    public var longestSleep: Int // minutes
    public var longestSleepDate: Date?
    public var mostDeepSleep: Int // minutes
    public var mostDeepSleepDate: Date?
    public var mostREMSleep: Int // minutes
    public var mostREMSleepDate: Date?
    
    // Streak Records
    public var sleepStreakRecord: Int // consecutive days with sleep data
    public var sleepStreakRecordStartDate: Date?
    public var sleepStreakRecordEndDate: Date?
    public var workoutStreakRecord: Int // consecutive days with workouts
    public var workoutStreakRecordStartDate: Date?
    public var workoutStreakRecordEndDate: Date?
    
    // Metadata
    public var lastUpdated: Date
    public var recordedAt: Date
    
    public init(
        id: Int = 1, // Usually one record per user
        peakHeartRate: Double = 0.0,
        peakHeartRateDate: Date? = nil,
        peakRunningSpeed: Double = 0.0,
        peakRunningSpeedDate: Date? = nil,
        peakRunningPower: Double = 0.0,
        peakRunningPowerDate: Date? = nil,
        longestRun: Double = 0.0,
        longestRunDate: Date? = nil,
        longestBikeRide: Double = 0.0,
        longestBikeRideDate: Date? = nil,
        longestSwim: Double = 0.0,
        longestSwimDate: Date? = nil,
        longestWalk: Double = 0.0,
        longestWalkDate: Date? = nil,
        longestWorkout: Int = 0,
        longestWorkoutDate: Date? = nil,
        mostStepsInADay: Int = 0,
        mostStepsInADayDate: Date? = nil,
        mostCaloriesInADay: Double = 0.0,
        mostCaloriesInADayDate: Date? = nil,
        mostExerciseMinutesInADay: Int = 0,
        mostExerciseMinutesInADayDate: Date? = nil,
        longestSleep: Int = 0,
        longestSleepDate: Date? = nil,
        mostDeepSleep: Int = 0,
        mostDeepSleepDate: Date? = nil,
        mostREMSleep: Int = 0,
        mostREMSleepDate: Date? = nil,
        sleepStreakRecord: Int = 0,
        sleepStreakRecordStartDate: Date? = nil,
        sleepStreakRecordEndDate: Date? = nil,
        workoutStreakRecord: Int = 0,
        workoutStreakRecordStartDate: Date? = nil,
        workoutStreakRecordEndDate: Date? = nil,
        lastUpdated: Date = Date(),
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.peakHeartRate = peakHeartRate
        self.peakHeartRateDate = peakHeartRateDate
        self.peakRunningSpeed = peakRunningSpeed
        self.peakRunningSpeedDate = peakRunningSpeedDate
        self.peakRunningPower = peakRunningPower
        self.peakRunningPowerDate = peakRunningPowerDate
        self.longestRun = longestRun
        self.longestRunDate = longestRunDate
        self.longestBikeRide = longestBikeRide
        self.longestBikeRideDate = longestBikeRideDate
        self.longestSwim = longestSwim
        self.longestSwimDate = longestSwimDate
        self.longestWalk = longestWalk
        self.longestWalkDate = longestWalkDate
        self.longestWorkout = longestWorkout
        self.longestWorkoutDate = longestWorkoutDate
        self.mostStepsInADay = mostStepsInADay
        self.mostStepsInADayDate = mostStepsInADayDate
        self.mostCaloriesInADay = mostCaloriesInADay
        self.mostCaloriesInADayDate = mostCaloriesInADayDate
        self.mostExerciseMinutesInADay = mostExerciseMinutesInADay
        self.mostExerciseMinutesInADayDate = mostExerciseMinutesInADayDate
        self.longestSleep = longestSleep
        self.longestSleepDate = longestSleepDate
        self.mostDeepSleep = mostDeepSleep
        self.mostDeepSleepDate = mostDeepSleepDate
        self.mostREMSleep = mostREMSleep
        self.mostREMSleepDate = mostREMSleepDate
        self.sleepStreakRecord = sleepStreakRecord
        self.sleepStreakRecordStartDate = sleepStreakRecordStartDate
        self.sleepStreakRecordEndDate = sleepStreakRecordEndDate
        self.workoutStreakRecord = workoutStreakRecord
        self.workoutStreakRecordStartDate = workoutStreakRecordStartDate
        self.workoutStreakRecordEndDate = workoutStreakRecordEndDate
        self.lastUpdated = lastUpdated
        self.recordedAt = recordedAt
    }
}