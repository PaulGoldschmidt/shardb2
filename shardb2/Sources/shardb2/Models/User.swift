import Foundation
import SwiftData

@Model
public final class User {
    @Attribute(.unique) public var userID: UUID
    public var birthdate: Date
    public var lastProcessedAt: Date
    public var firstInit: Date
    public var firstHealthKitRecord: Date
    public var receivesNotifications: Bool
    public var healthkitAuthorized: Bool
    public var usesMetric: Bool
    
    public init(
        userID: UUID = UUID(),
        birthdate: Date,
        lastProcessedAt: Date = Date(),
        firstInit: Date = Date(),
        firstHealthKitRecord: Date = Date(),
        receivesNotifications: Bool = true,
        healthkitAuthorized: Bool = false,
        usesMetric: Bool = true
    ) {
        self.userID = userID
        self.birthdate = birthdate
        self.lastProcessedAt = lastProcessedAt
        self.firstInit = firstInit
        self.firstHealthKitRecord = firstHealthKitRecord
        self.receivesNotifications = receivesNotifications
        self.healthkitAuthorized = healthkitAuthorized
        self.usesMetric = usesMetric
    }
}
