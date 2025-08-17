# shardb2

A Swift Package Manager library for comprehensive health statistics tracking and analytics. Integrates with HealthKit to collect health data and uses SwiftData for modern, reliable persistence. Designed for iOS health apps (e.g. "YourStats") that need robust step tracking, sleep analysis, exercise monitoring, and personal record tracking.
This lib is a playground to explore optimization potentials in data-store using the SwiftData framework and can be seen as a blueprint for all sorts of data-intensive, multilevel time-series Apps.

## Features

- **Comprehensive Health Tracking** /Supports 14+ HealthKit data types including steps, distances, heart rate, sleep metrics, and exercise data
- **Multi-Level Analytics** / Automatic aggregation into daily, weekly, monthly, and yearly analytics
- **Personal Records** /Track achievements and streaks with detailed highscore management
- **Incremental Updates** / Efficient data synchronization based on timestamps
- **SwiftData Integration** /Modern Core Data abstraction for reliable data persistence
- **Progress Tracking** / Real-time feedback during data processing operations

## Requirements

- iOS 18.0+
- Swift 6.1+
- HealthKit capability (no Mac for you, sorry)
- SwiftData framework

## Installation

Add shardb2 to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/PaulGoldschmidt/shardb2.git", from: "1.0.0")
]
```
Soon to be found in the Swift Package index!

## Quick Start

1. Enable HealthKit capability in your app target
2. Add required Info.plist permissions
3. Handle HealthKit authorization in your app (not done by app)
4. Initialize the library with SwiftData context
5. Create a user and start tracking health data

See Usage.md for detailed implementation examples and complete API reference.

## Core Components

- **HealthStatsLibrary**: Main interface combining HealthKit and SwiftData functionality
- **Data Models**: Comprehensive models for users, analytics, and personal records
- **Analytics Engine**: Automatic aggregation from daily to yearly statistics
- **Progress Tracking**: Real-time updates during data processing operations

## Architecture

The library uses a layered architecture with HealthKit integration, SwiftData persistence, and comprehensive analytics processing. All health data is aggregated hierarchically from daily metrics up to yearly summaries, with automatic personal record tracking and streak calculations.


## Acknowledgements

I build this upon my learnings from the work I did in the [Stanford Biodesign Digital Health Group](https://github.com/StanfordBDHG) and the [Stanford Spezi Ecosystem](https://github.com/StanfordSpezi). Huge thanks to [Paul Schmiedmayer] and [Lukas Kollmer](https://github.com/lukaskollmer) for the support.


## License

MIT License - see LICENSE file for details.

A project by Paul Goldschmidt, 2025, Stanford University. Made with love and terminal.shop coffee.
