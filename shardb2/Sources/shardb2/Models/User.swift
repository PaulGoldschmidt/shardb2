import Foundation
import SwiftData

@Model
public final class User {
    @Attribute(.unique) public var userID: UUID
    public var birthdate: Date
    public var lastProcessedAt: Date
    public var firstInit: Date
    public var firstHealthKitRecord: Date
    public var highscoresLastUpdated: Date
    public var receivesNotifications: Bool
    public var healthkitAuthorized: Bool
    public var usesMetric: Bool
    
    public init(
        userID: UUID = UUID(),
        birthdate: Date,
        lastProcessedAt: Date = DateComponents(calendar: Calendar.current, year: 1999, month: 1, day: 1).date!,
        firstInit: Date = Date(),
        firstHealthKitRecord: Date = DateComponents(calendar: Calendar.current, year: 2014, month: 9, day: 1).date!, // Default to HealthKit launch
        highscoresLastUpdated: Date = DateComponents(calendar: Calendar.current, year: 1999, month: 1, day: 1).date!,
        receivesNotifications: Bool = true,
        healthkitAuthorized: Bool = false,
        usesMetric: Bool = true
    ) {
        self.userID = userID
        self.birthdate = birthdate
        self.lastProcessedAt = lastProcessedAt
        self.firstInit = firstInit
        self.firstHealthKitRecord = firstHealthKitRecord
        self.highscoresLastUpdated = highscoresLastUpdated
        self.receivesNotifications = receivesNotifications
        self.healthkitAuthorized = healthkitAuthorized
        self.usesMetric = usesMetric
    }
}
