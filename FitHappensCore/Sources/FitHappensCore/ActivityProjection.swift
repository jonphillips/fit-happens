import Foundation

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
  public var isFuture: Bool

  public var id: Date { date }

  public init(date: Date, training: Training, walkingMiles: Double?, isFuture: Bool = false) {
    self.date = date
    self.training = training
    self.walkingMiles = walkingMiles
    self.isFuture = isFuture
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
  private struct Snapshot {
    var date: Date
    var id: UUID
    var pounds: Double
  }

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
      let isFuture = day > calendar.startOfDay(for: now)
      let completionsToday = !isFuture && completions.contains {
        calendar.isDate($0.completedAt, inSameDayAs: day)
      }
      let healthStrengthToday = !isFuture && strengthWorkouts.contains {
        calendar.isDate($0.start, inSameDayAs: day)
      }
      let walks = isFuture ? [] : walkingWorkouts.filter { calendar.isDate($0.start, inSameDayAs: day) }
      let recordedDistances = walks.compactMap(\.distanceMeters)
      let miles = recordedDistances.isEmpty ? nil : recordedDistances.reduce(0, +) / metersPerMile
      let hasStrength = completionsToday || healthStrengthToday
      let hasWalking = !walks.isEmpty
      let training: ActivityDay.Training = switch (hasStrength, hasWalking) {
      case (false, false): .neither
      case (true, false): .strength
      case (false, true): .walking
      case (true, true): .both
      }
      return ActivityDay(date: day, training: training, walkingMiles: miles, isFuture: isFuture)
    }
  }

  public static func orderedWeightedExercises(program: CurrentProgram, exercises: [Exercise]) -> [Exercise] {
    let canonicalExercises = CurrentProgramQuery.canonicalExerciseRows(exercises)
    let exercisesByKey = Dictionary(uniqueKeysWithValues: canonicalExercises.map { ($0.key, $0) })
    let orderedKeys = program.workouts.flatMap(\.exerciseKeys)
    var seen = Set<String>()
    return orderedKeys.compactMap { key in
      guard seen.insert(key).inserted, let exercise = exercisesByKey[key],
            !exercise.isRetired, exercise.loadKind == .weight, exercise.currentLoadPounds != nil
      else {
        return nil
      }
      return exercise
    }
  }

  public static func defaultExercise(program: CurrentProgram, exercises: [Exercise]) -> Exercise? {
    orderedWeightedExercises(program: program, exercises: exercises).first
  }

  public static func progression(
    exercise: Exercise?, exercises: [Exercise], completions: [Completion], items: [CompletionItem], now: Date,
    calendar: Calendar
  ) -> ExerciseProgression? {
    guard let exercise, let currentPounds = exercise.currentLoadPounds else {
      return nil
    }
    let matchingExerciseIDs = Set(exercises.filter { $0.key == exercise.key }.map(\.id)).union([exercise.id])
    let matchingItems = items.filter { matchingExerciseIDs.contains($0.exerciseID) }
    let itemByCompletion = Dictionary(grouping: matchingItems, by: \.completionID)
    let snapshots = completions.compactMap { completion -> Snapshot? in
      guard let item = itemByCompletion[completion.id]?.first, let pounds = item.loadPounds else {
        return nil
      }
      return Snapshot(date: completion.completedAt, id: completion.id, pounds: pounds)
    }.sorted {
      if $0.date == $1.date {
        return $0.id.uuidString < $1.id.uuidString
      }
      return $0.date < $1.date
    }
    let threshold = calendar.date(byAdding: .day, value: -progressionLookbackDays, to: now) ?? .distantPast
    let baseline = snapshots.last { $0.date <= threshold } ?? snapshots.first
    return ExerciseProgression(
      exerciseKey: exercise.key, exerciseName: exercise.name, currentPounds: currentPounds,
      previousPounds: baseline?.pounds, previousDate: baseline?.date
    )
  }
}
