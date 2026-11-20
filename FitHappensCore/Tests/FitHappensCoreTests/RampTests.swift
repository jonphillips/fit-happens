@testable import FitHappensCore
import Foundation
import Testing

struct RampContractTests {
  @Test func decodesRampWithoutPrescription() throws {
    let text = """
    FH-PROGRAM: v1
    {"workouts":[{"key":"A","items":[{"key":"bench","name":"Bench","loadKind":"weight",
      "startingWeight":175,"ramp":[{"reps":"10","offset":-20},{"reps":"8–10","offset":-10},{"reps":"6","offset":0}]}]}]}
    """
    let item = try ProgramContractDecoder.decode(text).contract.workouts[0].items[0]
    #expect(item.prescription.isEmpty)
    #expect(item.ramp?.count == 3)
  }

  @Test func rejectsRampWithFewerThanTwoStepsOrEmptyReps() {
    #expect(throws: ProgramContractError.rampTooShort("bench")) {
      try validate([RampStep(reps: "5", offset: 0)])
    }
    #expect(throws: ProgramContractError.emptyRampReps("bench")) {
      try validate([RampStep(reps: " ", offset: -5), RampStep(reps: "5", offset: 0)])
    }
  }

  @Test func rejectsInvalidOffsetsMissingTopAndBodyweight() {
    #expect(throws: ProgramContractError.invalidRampOffset("bench")) {
      try validate([RampStep(reps: "8", offset: 1), RampStep(reps: "5", offset: 0)])
    }
    #expect(throws: ProgramContractError.rampMissingTop("bench")) {
      try validate([RampStep(reps: "8", offset: -10), RampStep(reps: "5", offset: -5)])
    }
    #expect(throws: ProgramContractError.rampOnBodyweight("bench")) {
      try validate([RampStep(reps: "8", offset: -5), RampStep(reps: "5", offset: 0)], loadKind: .bodyweight)
    }
    #expect(ProgramErrorMessage.message(for: ProgramContractError.rampMissingTop("bench"))
      == "Ramp for exercise bench needs a step with offset 0.")
  }

  @Test func allowsWorkoutSpecificRampsForTheSameExerciseKey() throws {
    let contract = ProgramContract(workouts: [
      ProgramWorkout(key: "A", items: [ProgramExercise(
        key: "bench", name: "Bench", prescription: "", loadKind: .weight,
        ramp: [RampStep(reps: "10", offset: -20), RampStep(reps: "6", offset: 0)]
      )]),
      ProgramWorkout(key: "B", items: [ProgramExercise(
        key: "bench", name: "Bench", prescription: "", loadKind: .weight,
        ramp: [RampStep(reps: "8", offset: -10), RampStep(reps: "5", offset: 0)]
      )])
    ])
    try ProgramContractDecoder.validateShape(contract)
  }

  @Test func rampChangesAreReportedInRelativeFormAndResolveFromWorkingWeight() throws {
    let oldRamp = [RampStep(reps: "10", offset: -20), RampStep(reps: "6", offset: 0)]
    let newRamp = [
      RampStep(reps: "10", offset: -25), RampStep(reps: "8", offset: -10), RampStep(reps: "6", offset: 0)
    ]
    let current = CurrentProgram(
      exercises: [CurrentExercise(key: "bench", name: "Bench", loadKind: .weight, load: .weight(pounds: 2.5))],
      workouts: [CurrentWorkout(
        key: "A", exerciseKeys: ["bench"], prescriptions: ["bench": ""], ramps: ["bench": oldRamp]
      )]
    )
    let proposal = ProgramContract(workouts: [ProgramWorkout(key: "A", items: [ProgramExercise(
      key: "bench", name: "Bench", prescription: "ignored", loadKind: .weight, ramp: newRamp
    )])])
    let changes = try ProgramChanges.make(current: current, proposal: proposal)
    #expect(changes.workoutChanges[0].prescriptionChanges == [PrescriptionChange(
      workoutKey: "A", exerciseKey: "bench", oldPrescription: "10 @ −20 · 6 @ top",
      newPrescription: "10 @ −25 · 8 @ −10 · 6 @ top"
    )])
    #expect(changes.ignoredPrescriptions == [IgnoredPrescription(
      workoutKey: "A", exerciseKey: "bench", prescription: "ignored"
    )])
    #expect(ProgramPrescriptionResolver.resolve(
      prescription: "ignored", ramp: [RampStep(reps: "8", offset: -5), RampStep(reps: "5", offset: 0)],
      workingWeight: 2.5
    ) == "8 @ 0 · 5 @ 2.5")
  }

  @Test func addingAndRemovingRampArePrescriptionChanges() throws {
    let ramp = [RampStep(reps: "10", offset: -20), RampStep(reps: "6", offset: 0)]
    let straight = ProgramContract(workouts: [ProgramWorkout(key: "A", items: [ProgramExercise(
      key: "bench", name: "Bench", prescription: "3 × 5", loadKind: .weight
    )])])
    let ramped = ProgramContract(workouts: [ProgramWorkout(key: "A", items: [ProgramExercise(
      key: "bench", name: "Bench", prescription: "", loadKind: .weight, ramp: ramp
    )])])
    let currentStraight = CurrentProgram(
      exercises: [CurrentExercise(key: "bench", name: "Bench", loadKind: .weight, load: .weight(pounds: 175))],
      workouts: [CurrentWorkout(key: "A", exerciseKeys: ["bench"], prescriptions: ["bench": "3 × 5"])]
    )
    let added = try ProgramChanges.make(current: currentStraight, proposal: ramped)
    #expect(added.workoutChanges[0].prescriptionChanges == [PrescriptionChange(
      workoutKey: "A", exerciseKey: "bench", oldPrescription: "3 × 5", newPrescription: "10 @ −20 · 6 @ top"
    )])

    var currentRamped = currentStraight
    currentRamped.workouts[0].prescriptions["bench"] = ""
    currentRamped.workouts[0].ramps["bench"] = ramp
    let removed = try ProgramChanges.make(current: currentRamped, proposal: straight)
    #expect(removed.workoutChanges[0].prescriptionChanges == [PrescriptionChange(
      workoutKey: "A", exerciseKey: "bench", oldPrescription: "10 @ −20 · 6 @ top", newPrescription: "3 × 5"
    )])
  }
}

private func validate(_ ramp: [RampStep], loadKind: LoadKind = .weight) throws {
  try ProgramContractDecoder.validateShape(ProgramContract(workouts: [
    ProgramWorkout(key: "A", items: [ProgramExercise(
      key: "bench", name: "Bench", prescription: "", loadKind: loadKind, ramp: ramp
    )])
  ]))
}
