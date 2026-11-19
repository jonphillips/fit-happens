import Foundation

public struct StagedProgramCheck: Equatable, Sendable {
  public var changeSummary: String?

  public init(changeSummary: String?) {
    self.changeSummary = changeSummary
  }
}

public enum StagedProgram {
  public enum Check: Equatable, Sendable {
    case valid(StagedProgramCheck)
    case invalid(String)
  }

  public static func check(text: String, export: FitHappensChatExport?) -> Check {
    do {
      let decoded = try ProgramContractDecoder.decode(text)
      guard let export else {
        return .valid(StagedProgramCheck(changeSummary: nil))
      }
      let current = currentProgram(from: export.program)
      let changes = try ProgramChanges.make(current: current, proposal: decoded.contract)
      return .valid(StagedProgramCheck(changeSummary: changeSummary(for: changes)))
    } catch {
      return .invalid(ProgramErrorMessage.message(for: error))
    }
  }

  private static func currentProgram(from program: ChatProgram) -> CurrentProgram {
    func exercise(_ value: ChatExercise) -> CurrentExercise {
      CurrentExercise(
        key: value.key,
        name: value.name,
        loadKind: value.loadKind,
        load: value.loadKind == .weight
          ? value.currentWeight.map { .weight(pounds: $0) }
          : .bodyweight,
        increment: value.increment,
        loadLabel: value.loadLabel,
        notes: value.notes
      )
    }

    return CurrentProgram(
      exercises: program.exercises.map(exercise),
      retiredExercises: program.retiredExercises.map(exercise),
      workouts: program.workouts.map { workout in
        CurrentWorkout(
          key: workout.key,
          exerciseKeys: workout.items.map(\.exerciseKey),
          prescriptions: Dictionary(uniqueKeysWithValues: workout.items.map { ($0.exerciseKey, $0.prescription) })
        )
      }
    )
  }

  private static func changeSummary(for changes: ProgramChangeSet) -> String {
    var parts: [String] = []
    if !changes.addedExercises.isEmpty { parts.append("\(changes.addedExercises.count) added") }
    if !changes.retiredExerciseKeys.isEmpty { parts.append("\(changes.retiredExerciseKeys.count) retired") }
    if !changes.restoredExerciseKeys.isEmpty { parts.append("\(changes.restoredExerciseKeys.count) restored") }
    if !changes.addedWorkouts.isEmpty {
      parts.append("\(countAndNoun(changes.addedWorkouts.count, singular: "workout")) added")
    }
    if !changes.removedWorkoutKeys.isEmpty {
      parts.append("\(countAndNoun(changes.removedWorkoutKeys.count, singular: "workout")) removed")
    }
    parts.append(contentsOf: changes.weightChanges.map {
      "\($0.exerciseKey) \($0.oldPounds.formatted()) → \($0.newPounds.formatted()) lb"
    })
    parts.append(contentsOf: changes.incrementChanges.map {
      "\($0.exerciseKey) increment \($0.oldPounds.formatted()) → \($0.newPounds.formatted()) lb"
    })
    let detailChanges = changes.renames.count + changes.loadKindChanges.count
      + changes.workoutChanges.count + (changes.workoutOrderChanged ? 1 : 0)
      + changes.loadLabelChanges.count + changes.notesChanges.count
    if detailChanges > 0 { parts.append(countAndNoun(detailChanges, singular: "other change")) }
    return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
  }

  private static func countAndNoun(_ count: Int, singular: String) -> String {
    "\(count) \(singular)\(count == 1 ? "" : "s")"
  }
}
