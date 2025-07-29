# shardb2 Guide
A package to provide a interface to manage and handle statics-related health-applications in Swift. Uses SwiftData as Database abstraction and implements functions to handle often-used data requests.

## Setup

1. **Add HealthKit capability** to your app target
2. **Add Info.plist entries**:
   ```xml
   <key>NSHealthShareUsageDescription</key>
   <string>This app needs access to step count data</string>
   ```
3. **Handle HealthKit authorization** in your app before using the library

## Basic Usage

```swift
import SwiftData
import HealthKit
import shardb2

// 1. Setup SwiftData with both models
let container = try ModelContainer(for: StepCountRecord.self, User.self)
let context = ModelContext(container)

// 2. Initialize library
let healthStats = HealthStatsLibrary(modelContext: context)

// 3. Handle HealthKit permissions in your app
let healthStore = HKHealthStore()
let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
try await healthStore.requestAuthorization(toShare: [], read: [stepCountType])

// 4. Create a user
let user = try healthStats.createUser(birthdate: userBirthdate, usesMetric: true)

// 5. Sample and store step count
let record = try await healthStats.sampleAndStoreLatestStepCount()
print("Steps today: \(record.stepCount)")

// 6. Retrieve stored data
let allRecords = try healthStats.getAllStepCountRecords()
let allUsers = try healthStats.getAllUsers()
```

## User Management

```swift
// Create user
let user = try healthStats.createUser(birthdate: birthdate, usesMetric: true)

// Get user by ID
let retrievedUser = try healthStats.getUser(by: userID)

// Update user properties
user.healthkitAuthorized = true
user.lastProcessedAt = Date()
try healthStats.updateUser(user)

// Delete user
try healthStats.deleteUser(user)
```
