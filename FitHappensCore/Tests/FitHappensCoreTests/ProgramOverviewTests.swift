@testable import FitHappensCore
import Foundation
import Testing

struct ProgramOverviewTests {
  @Test func projectsEveryWorkoutInProgramOrderAndMarksTheNext() throws {
    let program = CurrentProgram(
      exercises: [
        CurrentExercise(key: "bench", name: "Bench press", loadKind: .weight, load: .weight(pounds: 135)),
        CurrentExercise(key: "chin", name: "Chin-up", loadKind: .bodyweight, load: .bodyweight)
      ],
      workouts: [
        CurrentWorkout(key: "A", exerciseKeys: ["bench"], prescriptions: ["bench": "3 × 5"]),
        CurrentWorkout(key: "B", exerciseKeys: ["chin"], prescriptions: ["chin": "3 × 8"])
      ]
    )
    let latest = CompletionSummary(id: UUID(), workoutKey: "A", completedAt: .now)
    let overview = try #require(ProgramOverview.make(program: program, latestCompletion: latest))

    #expect(overview.workouts.map(\.key) == ["A", "B"])
    #expect(overview.nextWorkoutKey == "B")
    #expect(overview.workouts[0].exercises[0].loadPounds == 135)
    #expect(overview.workouts[1].exercises[0].loadPounds == nil)
    let nextWorkout = WorkoutOverview.make(program: program, latestCompletion: latest)
    #expect(nextWorkout?.exercises == overview.workouts[1].exercises)
  }

  @Test func removedLatestWorkoutFallsBackToTheFirstAndEmptyProgramIsNil() throws {
    let program = CurrentProgram(
      exercises: [],
      workouts: [CurrentWorkout(key: "B", exerciseKeys: [], prescriptions: [:])]
    )
    let latest = CompletionSummary(id: UUID(), workoutKey: "A", completedAt: .now)
    #expect(ProgramOverview.make(program: program, latestCompletion: latest)?.nextWorkoutKey == "B")
    #expect(
      ProgramOverview.make(program: CurrentProgram(exercises: [], workouts: []), latestCompletion: nil) == nil
    )
  }
}
