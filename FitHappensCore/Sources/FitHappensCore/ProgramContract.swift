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
  public static let identifier = "FH-PROGRAM-1"
  public static let handoffMarker = HandoffContractMarker(prefix: "FH-PROGRAM", version: "v1")
}

public enum ProgramContractError: Error, Equatable, Sendable {
  case missingMarker
  case unsupportedMarker(String)
  case malformedJSON
  case emptyWorkouts
  case emptyKey
  case duplicateWorkoutKey(String)
  case duplicateExerciseKey(String)
  case conflictingExerciseDefinition(String)
  case missingStartingWeight(String)
  case bodyweightHasStartingWeight(String)
  case invalidWeight(String)
  case existingExerciseHasStartingWeight(String)
}

public enum ProgramContractDecoder {
  public static func decode(_ text: String) throws -> ProgramContract {
    var lines = text.components(separatedBy: .newlines)
    guard let markerIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    else { throw ProgramContractError.missingMarker }
    let suppliedMarker = lines[markerIndex].trimmingCharacters(in: .whitespacesAndNewlines)
    guard suppliedMarker == ProgramContractMarker.identifier else {
      if suppliedMarker.hasPrefix("FH-PROGRAM-") {
        throw ProgramContractError.unsupportedMarker(suppliedMarker)
      }
      throw ProgramContractError.missingMarker
    }
    // LLMHandoffKit owns the marker version check. Normalize the app's stable
    // compact identifier to the package's prefix/version marker spelling first.
    lines[markerIndex] = ProgramContractMarker.handoffMarker.marker
    let marked: HandoffContractResult
    do {
      marked = try ProgramContractMarker.handoffMarker.strippingMarker(from: lines.joined(separator: "\n"))
    } catch {
      throw ProgramContractError.unsupportedMarker(suppliedMarker)
    }
    do {
      let contract = try JSONDecoder().decode(ProgramContract.self, from: Data(marked.text.utf8))
      try validateShape(contract)
      return contract
    } catch let error as ProgramContractError {
      throw error
    } catch {
      throw ProgramContractError.malformedJSON
    }
  }

  public static func validateShape(_ contract: ProgramContract) throws {
    guard !contract.workouts.isEmpty else { throw ProgramContractError.emptyWorkouts }
    var workoutKeys = Set<String>()
    var exerciseDefinitions: [String: ProgramExercise] = [:]
    for workout in contract.workouts {
      guard !workout.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ProgramContractError.emptyKey
      }
      guard workoutKeys.insert(workout.key).inserted else {
        throw ProgramContractError.duplicateWorkoutKey(workout.key)
      }
      for item in workout.items {
        guard !item.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !item.prescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw ProgramContractError.emptyKey }
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
      }
    }
  }
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
  public var exercises: [CurrentExercise]
  public var workouts: [CurrentWorkout]

  public init(exercises: [CurrentExercise], workouts: [CurrentWorkout]) {
    self.exercises = exercises
    self.workouts = workouts
  }
}

public struct ProgramRename: Equatable, Sendable {
  public var key: String
  public var oldName: String
  public var newName: String
}

public struct PrescriptionChange: Equatable, Sendable {
  public var workoutKey: String
  public var exerciseKey: String
  public var oldPrescription: String?
  public var newPrescription: String
}

public struct WeightCarryover: Equatable, Sendable {
  public var exerciseKey: String
  public var load: Load
}

public struct ProgramChangeSet: Equatable, Sendable {
  public var addedExercises: [ProgramExercise]
  public var retiredExerciseKeys: [String]
  public var renames: [ProgramRename]
  public var prescriptionChanges: [PrescriptionChange]
  public var workoutOrderChanged: Bool
  public var exerciseOrderChanges: [String]
  public var carriedWeights: [WeightCarryover]

  public init(
    addedExercises: [ProgramExercise], retiredExerciseKeys: [String],
    renames: [ProgramRename], prescriptionChanges: [PrescriptionChange],
    workoutOrderChanged: Bool, exerciseOrderChanges: [String], carriedWeights: [WeightCarryover]
  ) {
    self.addedExercises = addedExercises
    self.retiredExerciseKeys = retiredExerciseKeys
    self.renames = renames
    self.prescriptionChanges = prescriptionChanges
    self.workoutOrderChanged = workoutOrderChanged
    self.exerciseOrderChanges = exerciseOrderChanges
    self.carriedWeights = carriedWeights
  }
}

public enum ProgramChanges {
  private struct ExerciseChanges {
    var added: [ProgramExercise]
    var retired: [String]
    var renames: [ProgramRename]
    var carried: [WeightCarryover]
  }

  public static func make(current: CurrentProgram, proposal: ProgramContract) throws -> ProgramChangeSet {
    try ProgramContractDecoder.validateShape(proposal)
    let exercises = try exerciseChanges(current: current, proposal: proposal)
    let prescriptions = prescriptionChanges(current: current, proposal: proposal)
    return ProgramChangeSet(
      addedExercises: exercises.added.sorted { $0.key < $1.key },
      retiredExerciseKeys: exercises.retired.sorted(),
      renames: exercises.renames.sorted { $0.key < $1.key },
      prescriptionChanges: prescriptions.changes,
      workoutOrderChanged: current.workouts.map(\.key) != proposal.workouts.map(\.key),
      exerciseOrderChanges: prescriptions.reorderedWorkouts,
      carriedWeights: exercises.carried.sorted { $0.exerciseKey < $1.exerciseKey }
    )
  }

  private static func exerciseChanges(
    current: CurrentProgram, proposal: ProgramContract
  ) throws -> ExerciseChanges {
    var existing: [String: CurrentExercise] = [:]
    for exercise in current.exercises { existing[exercise.key] = exercise }
    var proposed: [String: ProgramExercise] = [:]
    for item in proposal.workouts.flatMap(\.items) where proposed[item.key] == nil {
      proposed[item.key] = item
    }
    var changes = ExerciseChanges(added: [], retired: [], renames: [], carried: [])
    for item in proposed.values {
      guard let old = existing[item.key] else {
        if item.loadKind == .weight, item.startingWeight == nil {
          throw ProgramContractError.missingStartingWeight(item.key)
        }
        changes.added.append(item)
        continue
      }
      guard item.startingWeight == nil else {
        throw ProgramContractError.existingExerciseHasStartingWeight(item.key)
      }
      if old.loadKind == item.loadKind, let load = old.load {
        changes.carried.append(.init(exerciseKey: item.key, load: load))
      }
      if old.name != item.name {
        changes.renames.append(.init(key: item.key, oldName: old.name, newName: item.name))
      }
    }
    changes.retired = current.exercises
      .filter { proposed[$0.key] == nil }
      .map(\.key)
    return changes
  }

  private static func prescriptionChanges(
    current: CurrentProgram, proposal: ProgramContract
  ) -> (changes: [PrescriptionChange], reorderedWorkouts: [String]) {
    var oldByKey: [String: CurrentWorkout] = [:]
    for workout in current.workouts { oldByKey[workout.key] = workout }
    var changes: [PrescriptionChange] = []
    var reorderedWorkouts: [String] = []
    for workout in proposal.workouts {
      let old = oldByKey[workout.key]
      if let old, old.exerciseKeys != workout.items.map(\.key) {
        reorderedWorkouts.append(workout.key)
      }
      for item in workout.items {
        guard let previous = old?.prescriptions[item.key], previous != item.prescription else { continue }
        changes.append(.init(
          workoutKey: workout.key, exerciseKey: item.key,
          oldPrescription: previous, newPrescription: item.prescription
        ))
      }
    }
    return (changes, reorderedWorkouts)
  }
}
