@testable import FitHappensCore
import Foundation
import Testing

struct ProgramLogicTests {
  @Test func changeSetReportsExerciseChangesAndPerWorkoutMembership() throws {
    let current = CurrentProgram(
      exercises: [
        CurrentExercise(key: "bench", name: "Bench", loadKind: .weight, load: .weight(pounds: 135)),
        CurrentExercise(key: "row", name: "Row", loadKind: .weight, load: .weight(pounds: 90)),
        CurrentExercise(key: "retired", name: "Old lift", loadKind: .weight, load: .weight(pounds: 40))
      ],
      workouts: [
        CurrentWorkout(key: "A", exerciseKeys: ["bench", "row"], prescriptions: ["bench": "3 × 5", "row": "3 × 8"]),
        CurrentWorkout(key: "B", exerciseKeys: ["row", "bench"], prescriptions: ["bench": "3 × 5", "row": "3 × 8"])
      ]
    )
    let proposal = ProgramContract(workouts: [
      ProgramWorkout(key: "B", items: [
        ProgramExercise(key: "bench", name: "Flat bench", prescription: "3 × 5–8", loadKind: .weight),
        ProgramExercise(key: "new", name: "New lift", prescription: "2 × 10", loadKind: .weight, startingWeight: 0)
      ]),
      ProgramWorkout(key: "A", items: [
        ProgramExercise(key: "row", name: "Row", prescription: "3 × 8", loadKind: .weight),
        ProgramExercise(key: "bench", name: "Flat bench", prescription: "3 × 5–8", loadKind: .weight)
      ])
    ])
    let changes = try ProgramChanges.make(current: current, proposal: proposal)
    #expect(changes.addedExercises.map(\.key) == ["new"])
    #expect(changes.retiredExerciseKeys == ["retired"])
    #expect(changes.renames.map(\.newName) == ["Flat bench"])
    #expect(changes.workoutOrderChanged)
    #expect(changes.carriedWeights == [
      WeightCarryover(exerciseKey: "bench", load: .weight(pounds: 135)),
      WeightCarryover(exerciseKey: "row", load: .weight(pounds: 90))
    ])
    let workoutB = try #require(changes.workoutChanges.first { $0.workoutKey == "B" })
    #expect(workoutB.addedItems == [ProgramItemAddition(exerciseKey: "new", prescription: "2 × 10")])
    #expect(workoutB.removedExerciseKeys == ["row"])
    #expect(workoutB.prescriptionChanges.count == 1)
    #expect(!workoutB.orderChanged)
    let workoutA = try #require(changes.workoutChanges.first { $0.workoutKey == "A" })
    #expect(workoutA.orderChanged)
  }

  @Test func changeSetReportsAnExerciseMovedBetweenWorkouts() throws {
    let current = CurrentProgram(
      exercises: [
        CurrentExercise(key: "bench", name: "Bench", loadKind: .weight, load: .weight(pounds: 135))
      ],
      workouts: [
        CurrentWorkout(key: "A", exerciseKeys: ["bench"], prescriptions: ["bench": "3 × 5"]),
        CurrentWorkout(key: "B", exerciseKeys: [], prescriptions: [:])
      ]
    )
    let proposal = ProgramContract(workouts: [
      ProgramWorkout(key: "A", items: [
        ProgramExercise(key: "other", name: "Other", prescription: "2 × 8", loadKind: .weight, startingWeight: 0)
      ]),
      ProgramWorkout(key: "B", items: [
        ProgramExercise(key: "bench", name: "Bench", prescription: "3 × 5", loadKind: .weight)
      ])
    ])
    let changes = try ProgramChanges.make(current: current, proposal: proposal)
    let removedFromA = try #require(changes.workoutChanges.first { $0.workoutKey == "A" })
    let addedToB = try #require(changes.workoutChanges.first { $0.workoutKey == "B" })
    #expect(removedFromA.removedExerciseKeys == ["bench"])
    #expect(addedToB.addedItems == [ProgramItemAddition(exerciseKey: "bench", prescription: "3 × 5")])
  }

  @Test func changeSetReportsAddedAndRemovedWorkoutsWithTheirItems() throws {
    let current = CurrentProgram(
      exercises: [CurrentExercise(key: "bench", name: "Bench", loadKind: .weight, load: .weight(pounds: 135))],
      workouts: [CurrentWorkout(key: "A", exerciseKeys: ["bench"], prescriptions: ["bench": "3 × 5"])]
    )
    let addedWorkout = ProgramWorkout(key: "C", items: [
      ProgramExercise(key: "bench", name: "Bench", prescription: "2 × 8", loadKind: .weight),
      ProgramExercise(key: "new", name: "New lift", prescription: "3 × 10", loadKind: .weight, startingWeight: 10)
    ])
    let proposal = ProgramContract(workouts: [addedWorkout])
    let changes = try ProgramChanges.make(current: current, proposal: proposal)
    #expect(changes.addedWorkouts == [addedWorkout])
    #expect(changes.removedWorkoutKeys == ["A"])
    #expect(!changes.workoutOrderChanged)
  }

  @Test func changeSetReportsRestoringRetiredExerciseAndCarryingItsWeight() throws {
    let current = CurrentProgram(
      exercises: [CurrentExercise(key: "bench", name: "Bench", loadKind: .weight, load: .weight(pounds: 135))],
      retiredExercises: [CurrentExercise(key: "old", name: "Old lift", loadKind: .weight, load: .weight(pounds: 40))],
      workouts: [CurrentWorkout(key: "A", exerciseKeys: ["bench"], prescriptions: ["bench": "3 × 5"])]
    )
    let proposal = ProgramContract(workouts: [
      ProgramWorkout(key: "A", items: [
        ProgramExercise(key: "bench", name: "Bench", prescription: "3 × 5", loadKind: .weight),
        ProgramExercise(key: "old", name: "Old lift", prescription: "2 × 8", loadKind: .weight)
      ])
    ])
    let changes = try ProgramChanges.make(current: current, proposal: proposal)
    #expect(changes.restoredExerciseKeys == ["old"])
    #expect(changes.retiredExerciseKeys.isEmpty)
    #expect(changes.carriedWeights.contains(WeightCarryover(exerciseKey: "old", load: .weight(pounds: 40))))
  }

  @Test func restoredExerciseCannotOverrideItsCarriedWeight() {
    let current = CurrentProgram(
      exercises: [],
      retiredExercises: [CurrentExercise(key: "old", name: "Old lift", loadKind: .weight, load: .weight(pounds: 40))],
      workouts: []
    )
    let proposal = ProgramContract(workouts: [
      ProgramWorkout(key: "A", items: [
        ProgramExercise(key: "old", name: "Old lift", prescription: "2 × 8", loadKind: .weight, startingWeight: 5)
      ])
    ])
    #expect(throws: ProgramContractError.existingExerciseHasStartingWeight("old")) {
      try ProgramChanges.make(current: current, proposal: proposal)
    }
  }

  @Test func bodyweightToWeightIsAReportedKindChangeWithStartingWeight() throws {
    let current = CurrentProgram(
      exercises: [CurrentExercise(key: "bridge", name: "Bridge", loadKind: .bodyweight, load: .bodyweight)],
      workouts: [CurrentWorkout(key: "A", exerciseKeys: ["bridge"], prescriptions: ["bridge": "2 × 10"])]
    )
    let proposal = ProgramContract(workouts: [
      ProgramWorkout(key: "A", items: [
        ProgramExercise(key: "bridge", name: "Bridge", prescription: "2 × 10", loadKind: .weight, startingWeight: 15)
      ])
    ])
    let changes = try ProgramChanges.make(current: current, proposal: proposal)
    #expect(changes.loadKindChanges == [LoadKindChange(exerciseKey: "bridge", oldKind: .bodyweight, newKind: .weight)])
    #expect(changes.carriedWeights.isEmpty)
  }

  @Test func newWeightedExerciseNeedsStartingWeight() {
    let proposal = ProgramContract(workouts: [
      ProgramWorkout(key: "A", items: [
        ProgramExercise(key: "new", name: "New lift", prescription: "3 × 8", loadKind: .weight)
      ])
    ])
    #expect(throws: ProgramContractError.missingStartingWeight("new")) {
      try ProgramChanges.make(current: CurrentProgram(exercises: [], workouts: []), proposal: proposal)
    }
  }

  @Test func weightKindChangeNeedsStartingWeight() {
    let current = CurrentProgram(
      exercises: [CurrentExercise(key: "bridge", name: "Bridge", loadKind: .bodyweight, load: .bodyweight)],
      workouts: []
    )
    let proposal = ProgramContract(workouts: [
      ProgramWorkout(key: "A", items: [
        ProgramExercise(key: "bridge", name: "Bridge", prescription: "2 × 10", loadKind: .weight)
      ])
    ])
    #expect(throws: ProgramContractError.loadKindChangedWithoutWeight("bridge")) {
      try ProgramChanges.make(current: current, proposal: proposal)
    }
  }

  @Test func rotationAdvancesFromLatestCompletionAndWraps() {
    let completions = [
      CompletionSummary(workoutKey: "A", completedAt: Date(timeIntervalSince1970: 10)),
      CompletionSummary(workoutKey: "B", completedAt: Date(timeIntervalSince1970: 20))
    ]
    #expect(WorkoutRotation.nextWorkoutKey(workoutKeys: ["A", "B"], completions: []) == "A")
    #expect(WorkoutRotation.nextWorkoutKey(workoutKeys: ["A", "B"], completions: completions) == "A")
    #expect(WorkoutRotation.nextWorkoutKey(workoutKeys: ["A", "B"], completions: [
      CompletionSummary(workoutKey: "removed", completedAt: Date(timeIntervalSince1970: 30))
    ]) == "A")
    #expect(WorkoutRotation.nextWorkoutKey(workoutKeys: [], completions: []) == nil)
  }

  @Test func completionSnapshotCopiesPrescribedValuesAndLoads() throws {
    let workout = CurrentWorkout(
      key: "A", exerciseKeys: ["bench", "squat"],
      prescriptions: ["bench": "3 × 5–8", "squat": "2 × 10–12"]
    )
    let exercises = [
      CurrentExercise(key: "bench", name: "Flat bench", loadKind: .weight, load: .weight(pounds: 135)),
      CurrentExercise(key: "squat", name: "Squat to bench", loadKind: .bodyweight, load: .bodyweight)
    ]
    let completionID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let itemIDs = try [2, 3].map { try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000\($0)")) }
    var nextID = 0
    let snapshot = try CompletionSnapshots.make(
      workout: workout, exercises: exercises, completedAt: Date(timeIntervalSince1970: 42),
      completionID: completionID,
      makeID: {
        defer { nextID += 1 }
        return itemIDs[nextID]
      }
    )
    #expect(snapshot.items.map(\.prescription) == ["3 × 5–8", "2 × 10–12"])
    #expect(snapshot.items.map(\.load) == [.weight(pounds: 135), .bodyweight])
    #expect(snapshot.items.map(\.position) == [0, 1])
  }
}
