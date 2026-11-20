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
  }

  @Test func eachRampErrorHasItsReviewMessage() {
    let cases: [(ProgramContractError, String)] = [
      (.rampTooShort("bench"), "Exercise bench needs at least two ramp steps."),
      (.emptyRampReps("bench"), "Every ramp step for exercise bench needs reps."),
      (.invalidRampOffset("bench"), "Ramp offsets for exercise bench must be finite and at or below 0."),
      (.rampMissingTop("bench"), "Ramp for exercise bench needs a step with offset 0."),
      (.rampOnBodyweight("bench"), "Bodyweight exercise bench must omit ramp.")
    ]
    for (error, message) in cases {
      #expect(ProgramErrorMessage.message(for: error) == message)
    }
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
    #expect(changes.workoutChanges[0].prescriptionChanges.count == 1)
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

  @Test func echoingExportedRampPrescriptionIsNoChange() throws {
    let ramp = [RampStep(reps: "10", offset: -20), RampStep(reps: "8", offset: -10), RampStep(reps: "6", offset: 0)]
    let export = FitHappensChatExport(
      generatedAt: Date(timeIntervalSince1970: 1), device: "iPhone",
      program: ChatProgram(
        workouts: [ChatWorkout(key: "A", items: [ChatWorkoutItem(
          exerciseKey: "bench", prescription: "10 @ 125 · 8 @ 135 · 6 @ 145", name: "Bench",
          loadKind: .weight, currentWeight: 145, increment: 5, loadLabel: nil, notes: nil, ramp: ramp
        )])],
        exercises: [ChatExercise(
          key: "bench", name: "Bench", loadKind: .weight, currentWeight: 145,
          increment: 5, loadLabel: nil, notes: nil
        )],
        retiredExercises: [], nextWorkoutKey: "A", lastCompletion: nil
      ),
      completions: [], walks: [], bodyMass: []
    )
    let proposal = """
    FH-PROGRAM: v1
    {"workouts":[{"key":"A","items":[{"key":"bench","name":"Bench","loadKind":"weight",
      "prescription":"10 @ 125 · 8 @ 135 · 6 @ 145",
      "ramp":[{"reps":"10","offset":-20},{"reps":"8","offset":-10},{"reps":"6","offset":0}]}]}]}
    """
    let current = CurrentProgram(
      exercises: [CurrentExercise(
        key: "bench", name: "Bench", loadKind: .weight, load: .weight(pounds: 145), increment: 5
      )],
      workouts: [CurrentWorkout(
        key: "A", exerciseKeys: ["bench"],
        prescriptions: ["bench": "10 @ 125 · 8 @ 135 · 6 @ 145"], ramps: ["bench": ramp]
      )]
    )
    let contract = try ProgramContractDecoder.decode(proposal).contract
    let changes = try ProgramChanges.make(current: current, proposal: contract)
    #expect(changes.workoutChanges.isEmpty)
    #expect(StagedProgram.check(text: proposal, export: export) == .valid(.init(changeSummary: "No changes")))
  }
}

private func validate(_ ramp: [RampStep], loadKind: LoadKind = .weight) throws {
  try ProgramContractDecoder.validateShape(ProgramContract(workouts: [
    ProgramWorkout(key: "A", items: [ProgramExercise(
      key: "bench", name: "Bench", prescription: "", loadKind: loadKind, ramp: ramp
    )])
  ]))
}
