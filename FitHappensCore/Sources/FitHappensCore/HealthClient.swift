import Dependencies
import Foundation

public struct HealthWorkout: Equatable, Identifiable, Sendable {
  public var id: UUID
  public var start: Date
  public var end: Date

  public init(id: UUID, start: Date, end: Date) {
    self.id = id
    self.start = start
    self.end = end
  }
}

public struct HealthWalkingWorkout: Equatable, Identifiable, Sendable {
  public var id: UUID
  public var start: Date
  public var end: Date
  public var distanceMeters: Double?

  public init(id: UUID, start: Date, end: Date, distanceMeters: Double?) {
    self.id = id
    self.start = start
    self.end = end
    self.distanceMeters = distanceMeters
  }
}

public struct HealthBodyMass: Equatable, Sendable {
  public var pounds: Double
  public var date: Date

  public init(pounds: Double, date: Date) {
    self.pounds = pounds
    self.date = date
  }
}

public struct ActivityDay: Equatable, Identifiable, Sendable {
  public enum Training: Equatable, Sendable {
    case neither
    case strength
    case walking
    case both
  }

  public var date: Date
  public var training: Training
  public var walkingMiles: Double?

  public var id: Date { date }

  public init(date: Date, training: Training, walkingMiles: Double?) {
    self.date = date
    self.training = training
    self.walkingMiles = walkingMiles
  }
}

public struct ExerciseProgression: Equatable, Sendable {
  public var exerciseKey: String
  public var exerciseName: String
  public var currentPounds: Double
  public var previousPounds: Double?
  public var previousDate: Date?

  public init(
    exerciseKey: String, exerciseName: String, currentPounds: Double,
    previousPounds: Double?, previousDate: Date?
  ) {
    self.exerciseKey = exerciseKey
    self.exerciseName = exerciseName
    self.currentPounds = currentPounds
    self.previousPounds = previousPounds
    self.previousDate = previousDate
  }
}

public enum ActivityProjection {
  // M2 S3 defines a four-week display; each calendar week has seven days.
  private static let calendarDayCount = 4 * 7
  // The international mile is exactly 1,609.344 meters.
  private static let metersPerMile = 1_609.344
  // M2 S3 compares against the most recent snapshot at least 90 days old.
  private static let progressionLookbackDays = 90

  public static func calendarDays(
    now: Date, calendar: Calendar, completions: [Completion],
    strengthWorkouts: [HealthWorkout], walkingWorkouts: [HealthWalkingWorkout]
  ) -> [ActivityDay] {
    guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now),
          let firstDay = calendar.date(byAdding: .weekOfYear, value: -3, to: currentWeek.start)
    else {
      return []
    }

    return (0..<calendarDayCount).compactMap { offset in
      guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else {
        return nil
      }
      let dayInterval = calendar.dateInterval(of: .day, for: day)
      let isFuture = day > calendar.startOfDay(for: now)
      let strength = !isFuture && (
        completions.contains { dayInterval?.contains($0.completedAt) == true }
          || strengthWorkouts.contains { dayInterval?.contains($0.start) == true }
      )
      let walks = isFuture ? [] : walkingWorkouts.filter { dayInterval?.contains($0.start) == true }
      let recordedDistances = walks.compactMap(\.distanceMeters)
      let miles = recordedDistances.isEmpty ? nil : recordedDistances.reduce(0, +) / metersPerMile
      let hasWalking = !walks.isEmpty
      let training: ActivityDay.Training = switch (strength, hasWalking) {
      case (false, false): .neither
      case (true, false): .strength
      case (false, true): .walking
      case (true, true): .both
      }
      return ActivityDay(date: day, training: training, walkingMiles: miles)
    }
  }

  public static func defaultExercise(program: CurrentProgram, exercises: [Exercise]) -> Exercise? {
    let canonicalExercises = CurrentProgramQuery.canonicalExerciseRows(exercises)
    let exercisesByKey = Dictionary(uniqueKeysWithValues: canonicalExercises.map { ($0.key, $0) })
    guard let firstWorkout = program.workouts.first else {
      return nil
    }
    return firstWorkout.exerciseKeys.compactMap { exercisesByKey[$0] }.first {
      !$0.isRetired && $0.loadKind == .weight && $0.currentLoadPounds != nil
    }
  }

  public static func progression(
    exercise: Exercise?, completions: [Completion], items: [CompletionItem], now: Date,
    calendar: Calendar
  ) -> ExerciseProgression? {
    guard let exercise, let currentPounds = exercise.currentLoadPounds else {
      return nil
    }
    let itemByCompletion = Dictionary(grouping: items.filter { $0.exerciseID == exercise.id }, by: \.completionID)
    let snapshots = completions.compactMap { completion -> (Date, Double)? in
      guard let item = itemByCompletion[completion.id]?.first, let pounds = item.loadPounds else {
        return nil
      }
      return (completion.completedAt, pounds)
    }.sorted { $0.0 < $1.0 }
    let threshold = calendar.date(byAdding: .day, value: -progressionLookbackDays, to: now) ?? .distantPast
    let baseline = snapshots.last { $0.0 <= threshold } ?? snapshots.first
    return ExerciseProgression(
      exerciseKey: exercise.key, exerciseName: exercise.name, currentPounds: currentPounds,
      previousPounds: baseline?.1, previousDate: baseline?.0
    )
  }
}

public struct HealthClient: Sendable {
  public var requestReadAuthorization: @Sendable () async throws -> Void
  public var strengthWorkouts: @Sendable (Date, Date) async throws -> [HealthWorkout]
  public var walkingWorkouts: @Sendable (Date, Date) async throws -> [HealthWalkingWorkout]
  public var latestBodyMass: @Sendable () async throws -> HealthBodyMass?

  public init(
    requestReadAuthorization: @escaping @Sendable () async throws -> Void,
    strengthWorkouts: @escaping @Sendable (Date, Date) async throws -> [HealthWorkout],
    walkingWorkouts: @escaping @Sendable (Date, Date) async throws -> [HealthWalkingWorkout],
    latestBodyMass: @escaping @Sendable () async throws -> HealthBodyMass?
  ) {
    self.requestReadAuthorization = requestReadAuthorization
    self.strengthWorkouts = strengthWorkouts
    self.walkingWorkouts = walkingWorkouts
    self.latestBodyMass = latestBodyMass
  }

  public static let unimplemented = Self(
    requestReadAuthorization: { fatalError("HealthClient is not configured") },
    strengthWorkouts: { _, _ in fatalError("HealthClient is not configured") },
    walkingWorkouts: { _, _ in fatalError("HealthClient is not configured") },
    latestBodyMass: { fatalError("HealthClient is not configured") }
  )

  public static let preview = Self(
    requestReadAuthorization: {},
    strengthWorkouts: { _, _ in [] },
    walkingWorkouts: { _, _ in [] },
    latestBodyMass: { nil }
  )

  public static let test = preview
}

private enum HealthClientKey: DependencyKey {
  static var liveValue: HealthClient { .unimplemented }
  static var previewValue: HealthClient { .preview }
  static var testValue: HealthClient { .test }
}

public extension DependencyValues {
  var healthClient: HealthClient {
    get { self[HealthClientKey.self] }
    set { self[HealthClientKey.self] = newValue }
  }
}

public enum StrengthWorkoutCandidate {
  public static func pick(
    from workouts: [HealthWorkout],
    latestCompletionAt: Date?,
    linkedWorkoutIDs: Set<UUID>,
    declinedWorkoutIDs: Set<UUID>,
    now: Date
  ) -> HealthWorkout? {
    workouts
      .filter { workout in
        workout.start > (latestCompletionAt ?? .distantPast)
          && workout.end >= now.addingTimeInterval(-12 * 60 * 60)
          && workout.end <= now
          && !linkedWorkoutIDs.contains(workout.id)
          && !declinedWorkoutIDs.contains(workout.id)
      }
      .max { $0.end < $1.end }
  }
}
