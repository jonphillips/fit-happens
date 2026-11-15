@testable import FitHappensCore
import Foundation
import Testing

struct ProgramLogicTests {
  @Test func changeSetReportsAddedRetiredRenamedReorderedAndCarriedWeights() throws {
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
    #expect(changes.exerciseOrderChanges == ["B", "A"])
    #expect(changes.carriedWeights == [
      WeightCarryover(exerciseKey: "bench", load: .weight(pounds: 135)),
      WeightCarryover(exerciseKey: "row", load: .weight(pounds: 90))
    ])
    #expect(changes.prescriptionChanges.count == 2)
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
