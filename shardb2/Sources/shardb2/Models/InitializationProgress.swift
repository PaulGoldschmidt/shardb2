import Foundation

public struct InitializationProgress {
    public let percentage: Double
    public let currentTask: String
    
    public init(percentage: Double, currentTask: String) {
        self.percentage = percentage
        self.currentTask = currentTask
    }
}