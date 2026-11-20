import Foundation

public enum ProgramContractRules {
  public static let chatServerInstructions = """
  Begin with get_program and reuse its exercise keys. When you have a proposed program, call
  propose_program instead of printing it. If a tool fails or times out, print the complete program
  with its FH-PROGRAM: v1 line so it can be pasted into Fit Happens.

  \(instructions)
  """

  public static let instructions = """
  Return the complete program as JSON. Prefix it with FH-PROGRAM: v1 when possible. One fenced JSON
  block is okay; short prose around it is okay. Use this shape:
  {
    "workouts": [{
      "key": "A",
      "items": [{
        "key": "flat-bench-press",
        "name": "Flat barbell bench press",
        "prescription": "3 × 5–8",
        "loadKind": "weight",
        "startingWeight": 135,
        "loadLabel": null,
        "notes": null
      }]
    }]
  }
  Keep units in pounds. Reuse a stable readable exercise key for the same lift; a new name is a rename.
  Omit increment when the exercise uses the default 5 lb step; include increment only for a different step.
  For an existing weighted key whose load kind stays weight, use newWeight to propose a working-weight change.
  Use newWeight only for that deliberate change; the app ignores it when reviewing a stored revision.
  New weighted exercises need startingWeight. A startingWeight on an existing or restored key is ignored;
  the app keeps its working weight.
  A change from bodyweight to weight needs a startingWeight; a change from weight to bodyweight omits it.
  Missing exercise keys retire the exercise. Include all workouts and items in order.
  A weighted item may use ramp instead of prescription. Ramps need at least two steps, non-empty reps,
  finite offsets at or below 0, and at least one offset of 0. The working weight is the top step; the
  app displays each step as working weight plus offset. For example: "ramp": [{"reps":"10","offset":-20},
  {"reps":"8","offset":-10}, {"reps":"6","offset":0}]. Omit prescription with ramp; if included, it is ignored.
  """
}

public enum ProgramErrorMessage {
  public static func message(for error: Error) -> String {
    switch error {
    case let error as ProgramContractError:
      switch error {
      case let .unsupportedMarker(marker): "Unsupported program marker: \(marker)."
      case let .malformedJSON(path, reason): "Program data at \(path): \(reason)"
      case .emptyWorkouts: "Add at least one workout."
      case let .emptyWorkout(key): "Workout \(key) has no exercises."
      case .emptyWorkoutKey: "Every workout needs a key."
      case .emptyExerciseKey: "Every exercise needs a key."
      case let .emptyExerciseName(key): "Exercise \(key) needs a name."
      case let .emptyPrescription(key): "Exercise \(key) needs a prescription."
      case let .duplicateWorkoutKey(key): "Workout key \(key) appears more than once."
      case let .duplicateExerciseKey(workout, exercise):
        "Exercise key \(exercise) appears more than once in workout \(workout)."
      case let .conflictingExerciseDefinition(key): "Exercise \(key) has conflicting definitions."
      case let .missingStartingWeight(key): "New weighted exercise \(key) needs a startingWeight."
      case let .bodyweightHasStartingWeight(key): "Bodyweight exercise \(key) must omit startingWeight."
      case let .invalidWeight(key): "Exercise \(key) has an invalid weight."
      case let .invalidIncrement(key): "Exercise \(key) must have a positive increment."
      case let .loadKindChangedWithoutWeight(key):
        "Exercise \(key) needs a startingWeight when changing to weight."
      case let .newWeightOnNewExercise(key): "New exercise \(key) must use startingWeight instead of newWeight."
      case let .newWeightOnBodyweight(key):
        "Bodyweight exercise \(key) must omit newWeight and startingWeight."
      case let .newWeightOnLoadKindChange(key):
        "Exercise \(key) must use startingWeight instead of newWeight when changing load kind."
      case let .rampTooShort(key): "Exercise \(key) needs at least two ramp steps."
      case let .emptyRampReps(key): "Every ramp step for exercise \(key) needs reps."
      case let .invalidRampOffset(key): "Ramp offsets for exercise \(key) must be finite and at or below 0."
      case let .rampMissingTop(key): "Ramp for exercise \(key) needs a step with offset 0."
      case let .rampOnBodyweight(key): "Bodyweight exercise \(key) must omit ramp."
      }
    case let error as CurrentProgramQueryError:
      switch error {
      case let .invalidLoad(key): "Saved exercise \(key) has an invalid working weight."
      }
    case let error as ProgramApplicationError:
      switch error {
      case let .duplicateExerciseKey(key): "Saved exercise key \(key) appears more than once."
      case let .duplicateWorkoutKey(key): "Saved workout key \(key) appears more than once."
      case let .duplicateWorkoutItem(workout, exercise):
        "Saved workout \(workout) has duplicate entries for \(exercise)."
      case let .invalidWeight(key): "Saved exercise \(key) has an invalid working weight."
      }
    default:
      "The program could not be reviewed. \(error.localizedDescription)"
    }
  }
}
