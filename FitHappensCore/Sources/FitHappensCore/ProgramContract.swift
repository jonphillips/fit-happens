import Foundation
import LLMHandoffKit

public struct ProgramContract: Codable, Equatable, Sendable {
  public var workouts: [ProgramWorkout]

  public init(workouts: [ProgramWorkout]) {
    self.workouts = workouts
  }
}

public struct ProgramWorkout: Codable, Equatable, Sendable {
  public var key: String
  public var items: [ProgramExercise]

  public init(key: String, items: [ProgramExercise]) {
    self.key = key
    self.items = items
  }
}

public struct ProgramExercise: Codable, Equatable, Sendable {
  public var key: String
  public var name: String
  public var prescription: String
  public var loadKind: LoadKind
  public var startingWeight: Double?
  public var increment: Double?
  public var loadLabel: String?
  public var notes: String?

  public init(
    key: String, name: String, prescription: String, loadKind: LoadKind,
    startingWeight: Double? = nil, increment: Double? = nil,
    loadLabel: String? = nil, notes: String? = nil
  ) {
    self.key = key
    self.name = name
    self.prescription = prescription
    self.loadKind = loadKind
    self.startingWeight = startingWeight
    self.increment = increment
    self.loadLabel = loadLabel
    self.notes = notes
  }
}

public enum ProgramContractMarker {
  public static let identifier = "FH-PROGRAM: v1"
  public static let handoffMarker = HandoffContractMarker(prefix: "FH-PROGRAM", version: "v1")
}

public struct DecodedProgram: Equatable, Sendable {
  public var contract: ProgramContract
  public var warning: String?

  public init(contract: ProgramContract, warning: String?) {
    self.contract = contract
    self.warning = warning
  }
}

public enum ProgramContractError: Error, Equatable, Sendable {
  case unsupportedMarker(String)
  case malformedJSON(path: String, reason: String)
  case emptyWorkouts
  case emptyWorkout(String)
  case emptyWorkoutKey
  case emptyExerciseKey
  case emptyExerciseName(String)
  case emptyPrescription(String)
  case duplicateWorkoutKey(String)
  case duplicateExerciseKey(workout: String, exercise: String)
  case conflictingExerciseDefinition(String)
  case missingStartingWeight(String)
  case bodyweightHasStartingWeight(String)
  case invalidWeight(String)
  case invalidIncrement(String)
  case existingExerciseHasStartingWeight(String)
  case loadKindChangedWithoutWeight(String)
}

public enum ProgramContractDecoder {
  public static func decode(_ text: String) throws -> DecodedProgram {
    let marked: HandoffContractResult
    do {
      marked = try ProgramContractMarker.handoffMarker.strippingMarker(from: text)
    } catch let HandoffContractError.unsupportedMarker(found, _) {
      throw ProgramContractError.unsupportedMarker(found)
    }
    let json = try extractJSONObject(from: marked.text)
    do {
      let contract = try JSONDecoder().decode(ProgramContract.self, from: Data(json.utf8))
      try validateShape(contract)
      let warning = marked.warning.map { _ in
        "The program marker was missing or older than FH-PROGRAM: v1. Confirm this is the intended program."
      }
      return DecodedProgram(contract: contract, warning: warning)
    } catch let error as ProgramContractError {
      throw error
    } catch let error as DecodingError {
      let context: DecodingError.Context
      let path: String
      switch error {
      case let .typeMismatch(_, value), let .valueNotFound(_, value), let .dataCorrupted(value):
        context = value
        path = formatPath(value.codingPath)
      case let .keyNotFound(key, value):
        context = value
        path = formatPath(value.codingPath + [key])
      @unknown default:
        throw ProgramContractError.malformedJSON(path: "$", reason: "The JSON could not be decoded.")
      }
      throw ProgramContractError.malformedJSON(path: path, reason: context.debugDescription)
    } catch {
      throw ProgramContractError.malformedJSON(path: "$", reason: String(describing: error))
    }
  }

  public static func validateShape(_ contract: ProgramContract) throws {
    guard !contract.workouts.isEmpty else { throw ProgramContractError.emptyWorkouts }
    var workoutKeys = Set<String>()
    var exerciseDefinitions: [String: ProgramExercise] = [:]
    for workout in contract.workouts {
      guard !workout.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ProgramContractError.emptyWorkoutKey
      }
      guard workoutKeys.insert(workout.key).inserted else {
        throw ProgramContractError.duplicateWorkoutKey(workout.key)
      }
      guard !workout.items.isEmpty else { throw ProgramContractError.emptyWorkout(workout.key) }
      var itemKeys = Set<String>()
      for item in workout.items {
        guard !item.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          throw ProgramContractError.emptyExerciseKey
        }
        guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          throw ProgramContractError.emptyExerciseName(item.key)
        }
        guard !item.prescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          throw ProgramContractError.emptyPrescription(item.key)
        }
        guard itemKeys.insert(item.key).inserted else {
          throw ProgramContractError.duplicateExerciseKey(workout: workout.key, exercise: item.key)
        }
        if let previous = exerciseDefinitions[item.key],
           previous.name != item.name || previous.loadKind != item.loadKind
             || previous.increment != item.increment || previous.loadLabel != item.loadLabel
             || previous.notes != item.notes || previous.startingWeight != item.startingWeight {
          throw ProgramContractError.conflictingExerciseDefinition(item.key)
        }
        exerciseDefinitions[item.key] = item
        if let weight = item.startingWeight, !weight.isFinite || weight < 0 {
          throw ProgramContractError.invalidWeight(item.key)
        }
        if item.loadKind == .bodyweight, item.startingWeight != nil {
          throw ProgramContractError.bodyweightHasStartingWeight(item.key)
        }
        if let increment = item.increment, !increment.isFinite || increment <= 0 {
          throw ProgramContractError.invalidIncrement(item.key)
        }
      }
    }
  }

  private static func extractJSONObject(from text: String) throws -> String {
    let source = try fencedSource(in: text)
    guard let opening = source.firstIndex(of: "{") else {
      throw ProgramContractError.malformedJSON(path: "$", reason: "No JSON object was found.")
    }
    return try matchingObject(in: source, startingAt: opening)
  }

  private static func fencedSource(in text: String) throws -> String {
    let lines = text.components(separatedBy: .newlines)
    let fences = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("```") }
    guard !fences.isEmpty else {
      return text
    }
    guard fences.count == 2, fences[1] > fences[0] else {
      throw ProgramContractError.malformedJSON(path: "$", reason: "Expected one fenced JSON block.")
    }
    let opening = lines[fences[0]].trimmingCharacters(in: .whitespaces)
    let closing = lines[fences[1]].trimmingCharacters(in: .whitespaces)
    let language = opening.dropFirst(3).trimmingCharacters(in: .whitespaces)
    let validLanguage = language.isEmpty || language.allSatisfy {
      $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
    }
    guard closing == "```", validLanguage else {
      throw ProgramContractError.malformedJSON(path: "$", reason: "The fenced block is not a single JSON block.")
    }
    return lines[(fences[0] + 1)..<fences[1]].joined(separator: "\n")
  }

  private static func matchingObject(in source: String, startingAt opening: String.Index) throws -> String {
    var depth = 0
    var inString = false
    var escaped = false
    for index in source.indices[opening...] {
      let character = source[index]
      if inString {
        if escaped {
          escaped = false
        } else if character == "\\" {
          escaped = true
        } else if character == "\"" {
          inString = false
        }
        continue
      }
      if character == "\"" {
        inString = true
      } else if character == "{" {
        depth += 1
      } else if character == "}" {
        depth -= 1
        if depth == 0 {
          return String(source[opening...index])
        }
      }
    }
    throw ProgramContractError.malformedJSON(path: "$", reason: "The JSON object is incomplete.")
  }

  private static func formatPath(_ codingPath: [any CodingKey]) -> String {
    codingPath.reduce(into: "") { path, key in
      if let index = key.intValue {
        path += "[\(index)]"
      } else {
        if !path.isEmpty { path += "." }
        path += key.stringValue
      }
    }.nilIfEmpty ?? "$"
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}

public struct CurrentExercise: Equatable, Sendable {
  public var key: String
  public var name: String
  public var loadKind: LoadKind
  public var load: Load?
  public var increment: Double?
  public var loadLabel: String?
  public var notes: String?

  public init(
    key: String, name: String, loadKind: LoadKind, load: Load?,
    increment: Double? = nil, loadLabel: String? = nil, notes: String? = nil
  ) {
    self.key = key
    self.name = name
    self.loadKind = loadKind
    self.load = load
    self.increment = increment
    self.loadLabel = loadLabel
    self.notes = notes
  }
}

public struct CurrentWorkout: Equatable, Sendable {
  public var key: String
  public var exerciseKeys: [String]
  public var prescriptions: [String: String]

  public init(key: String, exerciseKeys: [String], prescriptions: [String: String]) {
    self.key = key
    self.exerciseKeys = exerciseKeys
    self.prescriptions = prescriptions
  }
}

public struct CurrentProgram: Equatable, Sendable {
  /// Only currently prescribed exercises.
  public var exercises: [CurrentExercise]
  /// Retired exercises are separate so they can be restored without being retired again.
  public var retiredExercises: [CurrentExercise]
  public var workouts: [CurrentWorkout]

  public init(
    exercises: [CurrentExercise], retiredExercises: [CurrentExercise] = [], workouts: [CurrentWorkout]
  ) {
    self.exercises = exercises
    self.retiredExercises = retiredExercises
    self.workouts = workouts
  }
}

public struct ProgramRename: Equatable, Sendable {
  public var key: String
  public var oldName: String
  public var newName: String
}

public struct LoadKindChange: Equatable, Sendable {
  public var exerciseKey: String
  public var oldKind: LoadKind
  public var newKind: LoadKind
}

public struct WeightCarryover: Equatable, Sendable {
  public var exerciseKey: String
  public var load: Load
}

public struct ProgramItemAddition: Equatable, Sendable {
  public var exerciseKey: String
  public var prescription: String
}

public struct WorkoutMembershipChange: Equatable, Sendable {
  public var workoutKey: String
  public var addedItems: [ProgramItemAddition]
  public var removedExerciseKeys: [String]
  public var prescriptionChanges: [PrescriptionChange]
  public var orderChanged: Bool
}

public struct PrescriptionChange: Equatable, Sendable {
  public var workoutKey: String
  public var exerciseKey: String
  public var oldPrescription: String
  public var newPrescription: String
}

public struct ProgramChangeSet: Equatable, Sendable {
  public var addedExercises: [ProgramExercise]
  public var retiredExerciseKeys: [String]
  public var restoredExerciseKeys: [String]
  public var renames: [ProgramRename]
  public var loadKindChanges: [LoadKindChange]
  public var addedWorkouts: [ProgramWorkout]
  public var removedWorkoutKeys: [String]
  public var workoutChanges: [WorkoutMembershipChange]
  public var workoutOrderChanged: Bool
  public var carriedWeights: [WeightCarryover]
}

public enum ProgramChanges {
  private struct WorkoutChanges {
    var added: [ProgramWorkout]
    var removed: [String]
    var memberships: [WorkoutMembershipChange]
    var orderChanged: Bool
  }

  private struct ExerciseChanges {
    var added: [ProgramExercise] = []
    var retired: [String] = []
    var restored: [String] = []
    var renames: [ProgramRename] = []
    var kindChanges: [LoadKindChange] = []
    var carried: [WeightCarryover] = []
  }

  public static func make(current: CurrentProgram, proposal: ProgramContract) throws -> ProgramChangeSet {
    try ProgramContractDecoder.validateShape(proposal)
    let exerciseChanges = try reconcileExercises(current: current, proposal: proposal)
    let workoutChanges = makeWorkoutChanges(current: current.workouts, proposal: proposal.workouts)
    return ProgramChangeSet(
      addedExercises: exerciseChanges.added.sorted { $0.key < $1.key },
      retiredExerciseKeys: exerciseChanges.retired.sorted(),
      restoredExerciseKeys: exerciseChanges.restored.sorted(),
      renames: exerciseChanges.renames.sorted { $0.key < $1.key },
      loadKindChanges: exerciseChanges.kindChanges.sorted { $0.exerciseKey < $1.exerciseKey },
      addedWorkouts: workoutChanges.added,
      removedWorkoutKeys: workoutChanges.removed,
      workoutChanges: workoutChanges.memberships,
      workoutOrderChanged: workoutChanges.orderChanged,
      carriedWeights: exerciseChanges.carried.sorted { $0.exerciseKey < $1.exerciseKey }
    )
  }

  private static func reconcileExercises(
    current: CurrentProgram, proposal: ProgramContract
  ) throws -> ExerciseChanges {
    var active: [String: CurrentExercise] = [:]
    var retired: [String: CurrentExercise] = [:]
    for exercise in current.exercises { active[exercise.key] = exercise }
    for exercise in current.retiredExercises { retired[exercise.key] = exercise }
    var proposed: [String: ProgramExercise] = [:]
    for item in proposal.workouts.flatMap(\.items) where proposed[item.key] == nil {
      proposed[item.key] = item
    }
    var changes = ExerciseChanges()
    for item in proposed.values {
      let old = active[item.key]
      let restoring = retired[item.key]
      guard let previous = old ?? restoring else {
        if item.loadKind == .weight, item.startingWeight == nil {
          throw ProgramContractError.missingStartingWeight(item.key)
        }
        changes.added.append(item)
        continue
      }
      if restoring != nil { changes.restored.append(item.key) }
      if previous.loadKind == item.loadKind {
        if old != nil, item.startingWeight != nil {
          throw ProgramContractError.existingExerciseHasStartingWeight(item.key)
        }
        if let load = previous.load { changes.carried.append(.init(exerciseKey: item.key, load: load)) }
      } else {
        if item.loadKind == .weight, item.startingWeight == nil {
          throw ProgramContractError.loadKindChangedWithoutWeight(item.key)
        }
        changes.kindChanges.append(.init(
          exerciseKey: item.key, oldKind: previous.loadKind, newKind: item.loadKind
        ))
      }
      if previous.name != item.name {
        changes.renames.append(.init(key: item.key, oldName: previous.name, newName: item.name))
      }
    }
    changes.retired = current.exercises.filter { proposed[$0.key] == nil }.map(\.key)
    return changes
  }

  private static func makeWorkoutChanges(
    current: [CurrentWorkout], proposal: [ProgramWorkout]
  ) -> WorkoutChanges {
    var existing: [String: CurrentWorkout] = [:]
    for workout in current { existing[workout.key] = workout }
    let proposedKeys = Set(proposal.map(\.key))
    let currentKeys = Set(current.map(\.key))
    let added = proposal.filter { !currentKeys.contains($0.key) }
    let removed = current.filter { !proposedKeys.contains($0.key) }.map(\.key)
    let currentCommonOrder = current.map(\.key).filter { proposedKeys.contains($0) }
    let proposedCommonOrder = proposal.map(\.key).filter { currentKeys.contains($0) }
    var memberships: [WorkoutMembershipChange] = []
    for workout in proposal {
      guard let old = existing[workout.key] else { continue }
      let oldKeys = old.exerciseKeys
      let newKeys = workout.items.map(\.key)
      let oldSet = Set(oldKeys)
      let newSet = Set(newKeys)
      let additions = workout.items.filter { !oldSet.contains($0.key) }.map {
        ProgramItemAddition(exerciseKey: $0.key, prescription: $0.prescription)
      }
      let removals = oldKeys.filter { !newSet.contains($0) }
      var prescriptionChanges: [PrescriptionChange] = []
      for item in workout.items where oldSet.contains(item.key) {
        guard let oldPrescription = old.prescriptions[item.key], oldPrescription != item.prescription else { continue }
        prescriptionChanges.append(.init(
          workoutKey: workout.key, exerciseKey: item.key,
          oldPrescription: oldPrescription, newPrescription: item.prescription
        ))
      }
      let oldCommonOrder = oldKeys.filter { newSet.contains($0) }
      let newCommonOrder = newKeys.filter { oldSet.contains($0) }
      if !additions.isEmpty || !removals.isEmpty || !prescriptionChanges.isEmpty
        || oldCommonOrder != newCommonOrder {
        memberships.append(.init(
          workoutKey: workout.key, addedItems: additions,
          removedExerciseKeys: removals, prescriptionChanges: prescriptionChanges,
          orderChanged: oldCommonOrder != newCommonOrder
        ))
      }
    }
    return WorkoutChanges(
      added: added, removed: removed, memberships: memberships,
      orderChanged: currentCommonOrder != proposedCommonOrder
    )
  }
}
