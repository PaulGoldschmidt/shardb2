# shardb2 Usage Guide / Function overview

TODO @paul: Add structured explanation for Swift Package index.

A Swift package for managing health statistics applications with comprehensive health data analytics. Uses SwiftData for database persistence and provides both synchronous and asynchronous operations with progress tracking callbacks.

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
let container = try ModelContainer(for: User.self, DailyAnalytics.self, WeeklyAnalytics.self, MonthlyAnalytics.self, YearlyAnalytics.self, HighscoreRecord.self)
let context = ModelContext(container)

// 2. Initialize library
let healthStats = HealthStatsLibrary(modelContext: context)

// 3. Handle HealthKit permissions in your app
let healthStore = HKHealthStore()
let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
healthStore.requestAuthorization(toShare: [], read: [stepCountType]) { success, error in
    // Handle authorization result
}

// 4. Create a user
let user = try healthStats.createUser(birthdate: userBirthdate, usesMetric: true)

// 5. Check and update authorization status
let authStatus = healthStats.getHealthKitAuthorizationStatus(for: .stepCount)
let isAuthorized = try healthStats.updateUserHealthKitAuthorizationStatus(for: user)
print("HealthKit authorized: \(isAuthorized)")

// 6. Set the user's actual first HealthKit record date (async - recommended after authorization)
try await healthStats.setUserFirstHealthKitRecord(user)

// 7. Initialize database with comprehensive health data (async)
// This fetches ALL available health data from the user's first HealthKit sample to present
// and processes them into daily, weekly, monthly, and yearly analytics
try await healthStats.initializeDatabase(for: user) { progress in
    print("[\(String(format: "%.1f", progress.percentage))%] \(progress.currentTask)")
}

// 8. Refresh all data efficiently (async - recommended for regular updates)
try await healthStats.refreshAllData(for: user) { progress in
    print("[\(String(format: "%.1f", progress.percentage))%] \(progress.currentTask)")
}

// Alternative: Update missing data incrementally (async - legacy method)
try await healthStats.updateMissingData(for: user) { progress in
    print("[\(String(format: "%.1f", progress.percentage))%] \(progress.currentTask)")
}

// Alternative: Refresh just current day data (async)
try await healthStats.refreshCurrentDay(for: user) { progress in
    print("[\(String(format: "%.1f", progress.percentage))%] \(progress.currentTask)")
}

// 9. Retrieve stored data (synchronous)
let todaySteps = try healthStats.getDailyAnalytics(for: Date())?.steps ?? 0
let allUsers = try healthStats.getAllUsers()
print("Steps today: \(todaySteps)")

// 10. Get personal records and achievements (synchronous)
let highscores = try healthStats.getHighscoreRecord()
print("Personal best steps: \(highscores?.mostStepsInADay ?? 0)")
print("Longest sleep: \(highscores?.longestSleep ?? 0) minutes")
print("Sleep streak record: \(highscores?.sleepStreakRecord ?? 0) days")

// 11. Highscores are automatically updated during refreshAllData()
// No manual update needed - use refreshAllData() for efficient updates
```

## Analytics Queries

All query methods are synchronous and throw errors on failure.

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

All user management operations are synchronous except where noted.

```swift
// Create user (synchronous)
let user = try healthStats.createUser(birthdate: birthdate, usesMetric: true)

// Get user by ID (synchronous)
let retrievedUser = try healthStats.getUser(by: userID)

// Get all users (synchronous)
let allUsers = try healthStats.getAllUsers()

// Update user properties (synchronous)
user.healthkitAuthorized = true
user.lastProcessedAt = Date()
try healthStats.updateUser(user)

// Update user's HealthKit authorization status (synchronous)
let isAuthorized = try healthStats.updateUserHealthKitAuthorizationStatus(for: user)

// Set user's first HealthKit record date (async)
try await healthStats.setUserFirstHealthKitRecord(user)

// Delete user (synchronous)
try healthStats.deleteUser(user)

// Clear all analytics data while preserving user data (async)
try await healthStats.clearDatabaseExceptUser(user)
```

## Complete HealthStatsLibrary API Reference

### HealthKit Integration Functions
- `getHealthKitAuthorizationStatus(for: HKQuantityTypeIdentifier = .stepCount) -> HKAuthorizationStatus` - Checks HealthKit permission status (synchronous)
- `updateUserHealthKitAuthorizationStatus(for: User) throws -> Bool` - Updates user model with current HealthKit authorization status (synchronous)
- `setUserFirstHealthKitRecord(_ user: User) async throws` - Queries HealthKit to find earliest sample and sets firstHealthKitRecord (asynchronous)

### Database Operations
- `initializeDatabase(for: User, progressCallback: @escaping (InitializationProgress) -> Void) async throws` - Comprehensive database initialization with detailed progress updates (asynchronous)
- `updateMissingData(for: User, progressCallback: @escaping (InitializationProgress) -> Void) async throws` - Incremental data updates based on user's lastProcessedAt timestamp (asynchronous)
- `refreshAllData(for: User, progressCallback: @escaping (InitializationProgress) -> Void) async throws` - **Recommended**: Efficiently refreshes only new data since last update, updates current period analytics, and performs incremental highscore checking (asynchronous)
- `refreshCurrentDay(for: User, progressCallback: @escaping (InitializationProgress) -> Void) async throws` - Refresh current day data specifically to get latest HealthKit updates (asynchronous)
- `clearDatabaseExceptUser(_ user: User) async throws` - Clears all analytics data while preserving user data, resets user's lastProcessedAt to 1999-01-01 and re-detects firstHealthKitRecord for full reprocessing (asynchronous)

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

### Highscore Functions
- `getHighscoreRecord() throws -> HighscoreRecord?` - Retrieves the user's personal records and achievements

## Data Models

**User**: Stores user preferences and tracking metadata
- userID (UUID) - Unique identifier
- birthdate (Date) - User's birth date
- lastProcessedAt (Date) - Last data processing timestamp
- firstInit (Date) - Initial creation timestamp
- firstHealthKitRecord (Date) - Earliest HealthKit sample date
- highscoresLastUpdated (Date) - Last highscore calculation timestamp
- receivesNotifications (Bool) - Notification preferences
- healthkitAuthorized (Bool) - HealthKit authorization status
- usesMetric (Bool) - Measurement unit preference

**DailyAnalytics**: Comprehensive daily health metrics with strongly typed properties
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

**WeeklyAnalytics**: Weekly aggregated health metrics with the same data points as DailyAnalytics
- id (Int) - Auto-incrementing identifier
- startDate (Date) - Start of the week
- endDate (Date) - End of the week
- All the same health metrics as DailyAnalytics
- recordedAt (Date) - When this record was created

**MonthlyAnalytics**: Monthly aggregated health metrics
- id (Int) - Auto-incrementing identifier
- year (Int) - The year this data represents
- month (Int) - The month (1-12) this data represents
- startDate (Date) - Start of the month
- endDate (Date) - End of the month
- All the same health metrics as DailyAnalytics
- recordedAt (Date) - When this record was created

**YearlyAnalytics**: Yearly aggregated health metrics
- id (Int) - Auto-incrementing identifier
- year (Int, unique) - The year this data represents
- startDate (Date) - Start of the year (January 1st)
- endDate (Date) - End of the year (December 31st)
- All the same health metrics as DailyAnalytics
- recordedAt (Date) - When this record was created

**HighscoreRecord**: Personal records and achievements
- id (Int, unique) - Record identifier (usually 1 per user)
- peakHeartRate (Double) + date - Highest recorded heart rate in BPM
- peakRunningSpeed (Double) + date - Fastest running speed in m/s
- peakRunningPower (Double) + date - Highest running power in Watts
- longestRun (Double) + date - Longest running distance in meters
- longestBikeRide (Double) + date - Longest cycling distance in meters
- longestSwim (Double) + date - Longest swimming distance in meters
- longestWalk (Double) + date - Longest walking distance in meters
- longestWorkout (Int) + date - Longest workout duration in minutes
- mostStepsInADay (Int) + date - Highest daily step count
- mostCaloriesInADay (Double) + date - Highest daily calorie burn (active + resting)
- mostExerciseMinutesInADay (Int) + date - Most exercise minutes in a single day
- longestSleep (Int) + date - Longest sleep duration in minutes
- mostDeepSleep (Int) + date - Most deep sleep in minutes
- mostREMSleep (Int) + date - Most REM sleep in minutes
- sleepStreakRecord (Int) + start/end dates - Longest consecutive days with sleep data
- workoutStreakRecord (Int) + start/end dates - Longest consecutive days with workouts
- lastUpdated (Date) - When records were last calculated
- recordedAt (Date) - When this record was created

**InitializationProgress**: Progress tracking for database operations
- percentage (Double) - Progress percentage (0.0 to 100.0)
- currentTask (String) - Human-readable description of current operation

## Data Processing Methods

### Full Database Initialization

The `initializeDatabase` function performs a complete health data import and processing:

```swift
// Initialize database with detailed progress tracking (async)
try await healthStats.initializeDatabase(for: user) { progress in
    print("[\(String(format: "%.1f", progress.percentage))%] \(progress.currentTask)")
}
```

### Incremental Data Updates

The `updateMissingData` function allows you to add missing health data incrementally based on a user's `lastProcessedAt` timestamp:

```swift
// Update missing data from lastProcessedAt to now (async)
try await healthStats.updateMissingData(for: user) { progress in
    print("[\(String(format: "%.1f", progress.percentage))%] \(progress.currentTask)")
}
```

**Key Features:**
- Starts from the user's `lastProcessedAt` date (inclusive, to overwrite partial day data)
- Fetches only missing HealthKit data to minimize processing time
- Overwrites existing analytics for affected time periods to ensure accuracy
- Updates daily → weekly → monthly → yearly analytics hierarchically
- Provides detailed progress updates throughout the process
- Updates user's `lastProcessedAt` timestamp upon completion

### Efficient Data Refresh

The `refreshAllData` function provides the most efficient way to update existing data:

```swift
// Refresh all data efficiently (async)
try await healthStats.refreshAllData(for: user) { progress in
    print("[\(String(format: "%.1f", progress.percentage))%] \(progress.currentTask)")
}
```

### Current Day Refresh

For real-time updates of today's data:

```swift
// Refresh current day data (async)
try await healthStats.refreshCurrentDay(for: user) { progress in
    print("[\(String(format: "%.1f", progress.percentage))%] \(progress.currentTask)")
}
```

## Requirements

- iOS 18.0+
- macOS 14.0+ (for testing)
- HealthKit capability enabled
- User permission for health data access

## Key Features

- **Mixed Synchronous/Asynchronous API**: Query methods are synchronous for immediate data access, while data processing operations are asynchronous with progress callbacks
- **Swift 6 Compatible**: No concurrency warnings or issues
- **Comprehensive Health Data**: Supports 14+ HealthKit data types including steps, heart rate, sleep, and exercise metrics
- **Multi-level Analytics**: Automatic aggregation into daily, weekly, monthly, and yearly analytics
- **Incremental Updates**: Efficient data updates based on last processed timestamp
- **Personal Records**: Automatic tracking of achievements, streaks, and personal bests
- **SwiftData Integration**: Modern Core Data abstraction for reliable persistence
- **Progress Tracking**: Real-time feedback during all data processing operations
