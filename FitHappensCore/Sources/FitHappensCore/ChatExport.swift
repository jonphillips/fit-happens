import Foundation

public struct FitHappensChatExport: Codable, Equatable, Sendable {
  public var version: Int
  public var generatedAt: Date
  public var device: String
  public var program: ChatProgram
  public var completions: [ChatCompletion]
  public var walks: [ChatWalk]
  public var bodyMass: [ChatBodyMass]

  public init(
    version: Int = 1, generatedAt: Date, device: String, program: ChatProgram,
    completions: [ChatCompletion], walks: [ChatWalk], bodyMass: [ChatBodyMass]
  ) {
    self.version = version
    self.generatedAt = generatedAt
    self.device = device
    self.program = program
    self.completions = completions
    self.walks = walks
    self.bodyMass = bodyMass
  }

  public static func decode(_ data: Data) throws -> Self {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let value = try decoder.decode(Self.self, from: data)
    guard value.version == 1 else { throw DecodeError.unsupportedVersion(value.version) }
    return value
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }

  public enum DecodeError: Error, Equatable { case unsupportedVersion(Int) }
}

public struct ChatProgram: Codable, Equatable, Sendable {
  public var workouts: [ChatWorkout]
  public var exercises: [ChatExercise]
  public var retiredExercises: [ChatExercise]
  public var nextWorkoutKey: String?
  public var lastCompletion: ChatLastCompletion?
}

public struct ChatWorkout: Codable, Equatable, Sendable {
  public var key: String
  public var items: [ChatWorkoutItem]
}

public struct ChatWorkoutItem: Codable, Equatable, Sendable {
  public var exerciseKey: String
  public var prescription: String
  public var name: String
  public var loadKind: LoadKind
  public var currentWeight: Double?
  public var increment: Double
  public var loadLabel: String?
  public var notes: String?
}

public struct ChatExercise: Codable, Equatable, Sendable {
  public var key: String
  public var name: String
  public var loadKind: LoadKind
  public var currentWeight: Double?
  public var increment: Double
  public var loadLabel: String?
  public var notes: String?
}

public struct ChatLastCompletion: Codable, Equatable, Sendable {
  public var date: Date
  public var workoutKey: String
}

public struct ChatCompletion: Codable, Equatable, Sendable {
  public var date: Date
  public var workoutKey: String
  public var items: [ChatCompletionItem]
}

public struct ChatCompletionItem: Codable, Equatable, Sendable {
  public var exerciseKey: String
  public var loadKind: LoadKind
  public var loadPounds: Double?
}

public struct ChatWalk: Codable, Equatable, Sendable {
  public var date: Date
  public var miles: Double?
}

public struct ChatBodyMass: Codable, Equatable, Sendable {
  public var date: Date
  public var pounds: Double
}

public struct ChatActivity: Equatable, Sendable {
  public var walks: [ChatWalk]
  public var bodyMass: [ChatBodyMass]
  public var latestBodyMass: ChatBodyMass?
}

public struct ChatLoadChange: Codable, Equatable, Sendable {
  public var exerciseKey: String
  public var date: Date
  public var pounds: Double
}

public struct ChatHistory: Equatable, Sendable {
  public var completions: [ChatCompletion]
  public var loadChanges: [ChatLoadChange]
}

public enum FitHappensChatExportBuilder {
  public static func make(
    program: CurrentProgram, completions: [Completion], completionItems: [CompletionItem],
    exercises: [Exercise], walks: [HealthWalkingWorkout], bodyMass: [HealthBodyMass],
    generatedAt: Date, device: String, calendar: Calendar = .current
  ) -> FitHappensChatExport {
    let cutoff = calendar.date(byAdding: .day, value: -365, to: generatedAt) ?? .distantPast
    let completionSummaries = completions.map {
      CompletionSummary(id: $0.id, workoutKey: $0.workoutKey, completedAt: $0.completedAt)
    }
    let recentCompletions = completionSummaries.filter { $0.completedAt >= cutoff }
    let exerciseKeysByID = Dictionary(
      uniqueKeysWithValues: CurrentProgramQuery.canonicalExerciseRows(exercises).map { ($0.id, $0.key) }
    )
    let itemsByCompletion = Dictionary(grouping: completionItems, by: \.completionID)
    let exportedCompletions = makeCompletions(
      recentCompletions, itemsByCompletion: itemsByCompletion, exerciseKeysByID: exerciseKeysByID
    )
    let summary = CompletionSummary.latest(in: completionSummaries)
    let active = program.exercises.map(chatExercise)
    let retired = program.retiredExercises.map(chatExercise)
    let exercisesByKey = Dictionary(uniqueKeysWithValues: active.map { ($0.key, $0) })
    let workoutValues = makeWorkouts(program.workouts, exercisesByKey: exercisesByKey)
    let exportedMass = dailyBodyMass(
      bodyMass, cutoff: cutoff, generatedAt: generatedAt, calendar: calendar
    )
    return FitHappensChatExport(
      generatedAt: generatedAt, device: device,
      program: ChatProgram(
        workouts: workoutValues, exercises: active, retiredExercises: retired,
        nextWorkoutKey: WorkoutRotation.nextWorkoutKey(
          workoutKeys: program.workouts.map(\.key), latestCompletion: summary
        ),
        lastCompletion: summary.map { ChatLastCompletion(date: $0.completedAt, workoutKey: $0.workoutKey) }
      ),
      completions: exportedCompletions,
      walks: exportedWalks(walks, cutoff: cutoff, generatedAt: generatedAt),
      bodyMass: exportedMass
    )
  }

  private static func makeCompletions(
    _ completions: [CompletionSummary], itemsByCompletion: [UUID: [CompletionItem]],
    exerciseKeysByID: [UUID: String]
  ) -> [ChatCompletion] {
    completions.sorted { CompletionSummary.isNewer($1, than: $0) }.map { completion in
      let items = (itemsByCompletion[completion.id] ?? []).sorted { $0.position < $1.position }
      return ChatCompletion(
        date: completion.completedAt, workoutKey: completion.workoutKey,
        items: items.compactMap { item in
          guard let key = exerciseKeysByID[item.exerciseID] else {
            return nil
          }
          return ChatCompletionItem(exerciseKey: key, loadKind: item.loadKind, loadPounds: item.loadPounds)
        }
      )
    }
  }

  private static func makeWorkouts(
    _ workouts: [CurrentWorkout], exercisesByKey: [String: ChatExercise]
  ) -> [ChatWorkout] {
    workouts.map { workout in
      let items = workout.exerciseKeys.compactMap { key -> ChatWorkoutItem? in
        guard let exercise = exercisesByKey[key], let prescription = workout.prescriptions[key] else {
          return nil
        }
        return ChatWorkoutItem(
          exerciseKey: key, prescription: prescription, name: exercise.name,
          loadKind: exercise.loadKind, currentWeight: exercise.currentWeight,
          increment: exercise.increment, loadLabel: exercise.loadLabel, notes: exercise.notes
        )
      }
      return ChatWorkout(key: workout.key, items: items)
    }
  }

  private static func dailyBodyMass(
    _ samples: [HealthBodyMass], cutoff: Date, generatedAt: Date, calendar: Calendar
  ) -> [ChatBodyMass] {
    let byDay = Dictionary(grouping: samples.filter { $0.date >= cutoff && $0.date <= generatedAt }) {
      calendar.startOfDay(for: $0.date)
    }
    return byDay.values.compactMap { $0.max { $0.date < $1.date } }
      .sorted { $0.date < $1.date }
      .map { ChatBodyMass(date: $0.date, pounds: $0.pounds) }
  }

  private static func exportedWalks(
    _ walks: [HealthWalkingWorkout], cutoff: Date, generatedAt: Date
  ) -> [ChatWalk] {
    walks.filter { $0.start >= cutoff && $0.start <= generatedAt }.map { walk in
      ChatWalk(date: walk.start, miles: walk.distanceMeters.map { $0 / 1_609.344 })
    }.sorted { $0.date < $1.date }
  }

  private static func chatExercise(_ exercise: CurrentExercise) -> ChatExercise {
    ChatExercise(
      key: exercise.key, name: exercise.name, loadKind: exercise.loadKind,
      currentWeight: exercise.load.flatMap { if case let .weight(value) = $0 { value } else { nil } },
      increment: exercise.increment ?? 5, loadLabel: exercise.loadLabel, notes: exercise.notes
    )
  }
}

public enum FitHappensChatProjection {
  public static func history(
    _ export: FitHappensChatExport, days: Int = 90, exercise: String? = nil
  ) -> [ChatCompletion] {
    historyDetails(export, days: days, exercise: exercise).completions
  }

  public static func historyDetails(
    _ export: FitHappensChatExport, days: Int = 90, exercise: String? = nil
  ) -> ChatHistory {
    let cutoff = export.generatedAt.addingTimeInterval(-Double(min(max(days, 1), 365)) * 86_400)
    let matching = export.completions.filter { completion in
      completion.date >= cutoff && (exercise == nil || completion.items.contains { $0.exerciseKey == exercise })
    }.map { completion in
      guard let exercise else {
        return completion
      }
      var result = completion
      result.items = result.items.filter { $0.exerciseKey == exercise }
      return result
    }.sorted { $0.date < $1.date }
    let changes = loadChanges(export.completions, since: cutoff, exercise: exercise)
    return ChatHistory(completions: matching, loadChanges: changes)
  }

  private static func loadChanges(
    _ completions: [ChatCompletion], since cutoff: Date, exercise: String?
  ) -> [ChatLoadChange] {
    var previous: [String: Double] = [:]
    var changes: [ChatLoadChange] = []
    for completion in completions.sorted(by: { $0.date < $1.date }) {
      for item in completion.items where exercise == nil || item.exerciseKey == exercise {
        guard let pounds = item.loadPounds else { continue }
        if let oldPounds = previous[item.exerciseKey], oldPounds != pounds, completion.date >= cutoff {
          changes.append(ChatLoadChange(exerciseKey: item.exerciseKey, date: completion.date, pounds: pounds))
        }
        previous[item.exerciseKey] = pounds
      }
    }
    return changes
  }

  public static func activity(_ export: FitHappensChatExport, days: Int = 90) -> ChatActivity {
    let cutoff = export.generatedAt.addingTimeInterval(-Double(min(max(days, 1), 365)) * 86_400)
    let walks = export.walks.filter { $0.date >= cutoff }
    let bodyMass = export.bodyMass.filter { $0.date >= cutoff }
    return ChatActivity(walks: walks, bodyMass: bodyMass, latestBodyMass: export.bodyMass.max { $0.date < $1.date })
  }
}
