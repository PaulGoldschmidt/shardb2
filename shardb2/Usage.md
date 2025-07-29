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

// 1. Setup SwiftData with all models
let container = try ModelContainer(for: StepCountRecord.self, User.self, DailyAnalytics.self, WeeklyAnalytics.self, MonthlyAnalytics.self, YearlyAnalytics.self)
let context = ModelContext(container)

// 2. Initialize library
let healthStats = HealthStatsLibrary(modelContext: context)

// 3. Handle HealthKit permissions in your app
let healthStore = HKHealthStore()
let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
try await healthStore.requestAuthorization(toShare: [], read: [stepCountType])

// 4. Create a user
let user = try healthStats.createUser(birthdate: userBirthdate, usesMetric: true)

// 5. Check authorization status
let authStatus = healthStats.getHealthKitAuthorizationStatus(for: .stepCount)
print("HealthKit status: \(authStatus)")

// 6. Sample and store step count
let record = try await healthStats.sampleAndStoreLatestStepCount()
print("Steps today: \(record.stepCount)")

// 7. Fetch and store last 7 days of data
let weeklyRecords = try await healthStats.fetchAndStoreLast7DaysStepCount()
print("Fetched \(weeklyRecords.count) days of data")

// 8. Initialize database with detailed progress tracking
for await progress in healthStats.initializeDatabase(for: user) {
    print("[\(String(format: "%.1f", progress.percentage))%] \(progress.currentTask)")
}

// 9. Retrieve stored data
let allRecords = try healthStats.getAllStepCountRecords()
let allUsers = try healthStats.getAllUsers()
```

## Analytics Queries

### Daily Analytics
```swift
// Get analytics for a specific date
let todayAnalytics = try healthStats.getDailyAnalytics(for: Date())

// Get analytics for a date range
let lastWeekAnalytics = try healthStats.getDailyAnalytics(
    from: Calendar.current.date(byAdding: .day, value: -7, to: Date())!,
    to: Date()
)

// Get all daily analytics
let allDaily = try healthStats.getAllDailyAnalytics()

// Get latest daily analytics
let latest = try healthStats.getLatestDailyAnalytics()
```

### Weekly Analytics
```swift
// Get weekly analytics for a specific date
let thisWeekAnalytics = try healthStats.getWeeklyAnalytics(for: Date())

// Get weekly analytics for a date range
let monthlyWeeks = try healthStats.getWeeklyAnalytics(from: startDate, to: endDate)

// Get all weekly analytics
let allWeekly = try healthStats.getAllWeeklyAnalytics()

// Get latest weekly analytics
let latestWeek = try healthStats.getLatestWeeklyAnalytics()
```

### Monthly Analytics
```swift
// Get monthly analytics for a specific date
let thisMonthAnalytics = try healthStats.getMonthlyAnalytics(for: Date())

// Get monthly analytics by year and month
let januaryAnalytics = try healthStats.getMonthlyAnalytics(year: 2024, month: 1)

// Get all months for a specific year
let year2024Months = try healthStats.getMonthlyAnalytics(for: 2024)

// Get all monthly analytics
let allMonthly = try healthStats.getAllMonthlyAnalytics()

// Get latest monthly analytics
let latestMonth = try healthStats.getLatestMonthlyAnalytics()
```

### Yearly Analytics
```swift
// Get yearly analytics for a specific date
let thisYearAnalytics = try healthStats.getYearlyAnalytics(for: Date())

// Get yearly analytics by year
let year2024Analytics = try healthStats.getYearlyAnalytics(for: 2024)

// Get all yearly analytics
let allYearly = try healthStats.getAllYearlyAnalytics()

// Get latest yearly analytics
let latestYear = try healthStats.getLatestYearlyAnalytics()
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

## Complete HealthStatsLibrary API Reference

### HealthKit Data Functions
- `sampleAndStoreLatestStepCount() async throws -> StepCountRecord` - Fetches today's step count and stores it
- `fetchAndStoreLast7DaysStepCount() async throws -> [StepCountRecord]` - Fetches and stores last 7 days of step data
- `getHealthKitAuthorizationStatus(for: HKQuantityTypeIdentifier = .stepCount) -> HKAuthorizationStatus` - Checks HealthKit permission status
- `initializeDatabase(for: User) -> AsyncStream<InitializationProgress>` - Comprehensive database initialization with detailed progress updates

### Step Count Data Functions  
- `getAllStepCountRecords() throws -> [StepCountRecord]` - Returns all stored step count records
- `getLatestStepCountRecord() throws -> StepCountRecord?` - Returns most recent step count record

### Daily Analytics Query Functions
- `getDailyAnalytics(for: Date) throws -> DailyAnalytics?` - Get analytics for specific date
- `getDailyAnalytics(from: Date, to: Date) throws -> [DailyAnalytics]` - Get analytics for date range
- `getAllDailyAnalytics() throws -> [DailyAnalytics]` - Get all daily analytics
- `getLatestDailyAnalytics() throws -> DailyAnalytics?` - Get most recent daily analytics

### Weekly Analytics Query Functions
- `getWeeklyAnalytics(for: Date) throws -> WeeklyAnalytics?` - Get weekly analytics for specific date
- `getWeeklyAnalytics(from: Date, to: Date) throws -> [WeeklyAnalytics]` - Get weekly analytics for date range
- `getAllWeeklyAnalytics() throws -> [WeeklyAnalytics]` - Get all weekly analytics
- `getLatestWeeklyAnalytics() throws -> WeeklyAnalytics?` - Get most recent weekly analytics

### Monthly Analytics Query Functions
- `getMonthlyAnalytics(for: Date) throws -> MonthlyAnalytics?` - Get monthly analytics for specific date
- `getMonthlyAnalytics(year: Int, month: Int) throws -> MonthlyAnalytics?` - Get analytics for specific year/month
- `getMonthlyAnalytics(for: Int) throws -> [MonthlyAnalytics]` - Get all months for specific year
- `getAllMonthlyAnalytics() throws -> [MonthlyAnalytics]` - Get all monthly analytics
- `getLatestMonthlyAnalytics() throws -> MonthlyAnalytics?` - Get most recent monthly analytics

### Yearly Analytics Query Functions
- `getYearlyAnalytics(for: Date) throws -> YearlyAnalytics?` - Get yearly analytics for specific date
- `getYearlyAnalytics(for: Int) throws -> YearlyAnalytics?` - Get analytics for specific year
- `getAllYearlyAnalytics() throws -> [YearlyAnalytics]` - Get all yearly analytics
- `getLatestYearlyAnalytics() throws -> YearlyAnalytics?` - Get most recent yearly analytics

### User Management Functions
- `createUser(birthdate: Date, usesMetric: Bool = true) throws -> User` - Creates new user
- `getUser(by userID: UUID) throws -> User?` - Finds user by UUID
- `getAllUsers() throws -> [User]` - Returns all users
- `updateUser(_ user: User) throws` - Saves user changes
- `deleteUser(_ user: User) throws` - Removes user from database

### Data Models

**StepCountRecord**: stepCount (Int), date (Date), recordedAt (Date)

**User**: userID (UUID), birthdate (Date), lastProcessedAt (Date), firstInit (Date), firstHealthKitRecord (Date), receivesNotifications (Bool), healthkitAuthorized (Bool), usesMetric (Bool)

**DailyAnalytics**: Comprehensive daily health metrics with strongly typed properties:
- id (Int) - Auto-incrementing identifier
- date (Date, unique) - The day these metrics represent
- steps (Int) - Step count
- cyclingDistance (Double) - Cycling distance in meters
- walkingDistance (Double) - Walking distance in meters  
- runningDistance (Double) - Running distance in meters
- swimmingDistance (Double) - Swimming distance in meters
- swimmingStrokes (Int) - Swimming stroke count
- crossCountrySkiingDistance (Double) - Cross country skiing distance in meters
- downhillSnowSportsDistance (Double) - Downhill snow sports distance in meters
- energyActive (Double) - Active energy burned in kilocalories
- energyResting (Double) - Resting energy burned in kilocalories
- heartbeats (Int) - Total heartbeats
- stairsClimbed (Int) - Number of stairs climbed
- exerciseMinutes (Int) - Exercise time in minutes
- standMinutes (Int) - Stand time in minutes
- sleepTotal (Int) - Total sleep time in minutes
- sleepDeep (Int) - Deep sleep time in minutes
- sleepREM (Int) - REM sleep time in minutes
- recordedAt (Date) - When this record was created

**WeeklyAnalytics**: Weekly aggregated health metrics with the same data points as DailyAnalytics:
- id (Int) - Auto-incrementing identifier
- startDate (Date) - Start of the week
- endDate (Date) - End of the week
- All the same health metrics as DailyAnalytics
- recordedAt (Date) - When this record was created

**MonthlyAnalytics**: Monthly aggregated health metrics:
- id (Int) - Auto-incrementing identifier
- year (Int) - The year this data represents
- month (Int) - The month (1-12) this data represents
- startDate (Date) - Start of the month
- endDate (Date) - End of the month
- All the same health metrics as DailyAnalytics
- recordedAt (Date) - When this record was created

**YearlyAnalytics**: Yearly aggregated health metrics:
- id (Int) - Auto-incrementing identifier
- year (Int, unique) - The year this data represents
- startDate (Date) - Start of the year (January 1st)
- endDate (Date) - End of the year (December 31st)
- All the same health metrics as DailyAnalytics
- recordedAt (Date) - When this record was created

**InitializationProgress**: Progress tracking for database initialization:
- percentage (Double) - Progress percentage (0.0 to 100.0)
- currentTask (String) - Human-readable description of current operation

## Requirements

- iOS 18+ / macOS 14+
- HealthKit capability enabled
- User permission for health data access