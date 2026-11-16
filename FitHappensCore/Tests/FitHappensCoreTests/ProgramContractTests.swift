@testable import FitHappensCore
import Foundation
import Testing

struct ProgramContractTests {
  @Test func decodesTheREADMEProgramFixture() throws {
    let url = try #require(
      Bundle.module.url(forResource: "real-program", withExtension: "json", subdirectory: "Fixtures")
    )
    let decoded = try ProgramContractDecoder.decode(String(contentsOf: url, encoding: .utf8))
    #expect(decoded.warning == nil)
    #expect(decoded.contract.workouts.map(\.key) == ["A", "B"])
    #expect(decoded.contract.workouts[0].items.map(\.key) == [
      "flat-bench-press", "low-cable-row", "squat-to-bench",
      "standing-cable-hamstring-curl", "dumbbell-lateral-raise"
    ])
    #expect(decoded.contract.workouts[1].items.last?.key == "dumbbell-lateral-raise")
    #expect(decoded.contract.workouts[0].items[2].loadKind == .bodyweight)
    #expect(decoded.contract.workouts[0].items[0].startingWeight == 0)
  }

  @Test func decodesOneFencedJSONBlockWithProseAroundIt() throws {
    let text = """
    Here is the updated plan.
    FH-PROGRAM: v1
    ```json
    {
      "workouts": [{
        "key": "A",
        "items": [{
          "key": "lift",
          "name": "Lift",
          "prescription": "3 × 5",
          "loadKind": "weight",
          "startingWeight": 135
        }]
      }]
    }
    ```
    Let me know if you want changes.
    """
    let decoded = try ProgramContractDecoder.decode(text)
    #expect(decoded.contract.workouts.first?.items.first?.startingWeight == 135)
    #expect(decoded.warning == nil)
  }

  @Test func decodesUnlabelledCodeFence() throws {
    let text = """
    ```
    {
      "workouts": [{
        "key": "A",
        "items": [{
          "key": "lift",
          "name": "Lift",
          "prescription": "3 × 5",
          "loadKind": "weight",
          "startingWeight": 135
        }]
      }]
    }
    ```
    """
    #expect(try ProgramContractDecoder.decode(text).contract.workouts.count == 1)
  }

  @Test func missingMarkerIsAnAdvisoryWarning() throws {
    let decoded = try ProgramContractDecoder.decode("""
    {
      "workouts": [{
        "key": "A",
        "items": [{
          "key": "lift",
          "name": "Lift",
          "prescription": "3 × 5",
          "loadKind": "weight",
          "startingWeight": 135
        }]
      }]
    }
    """)
    #expect(decoded.warning != nil)
    #expect(decoded.contract.workouts.first?.key == "A")
  }

  @Test func rejectsANewerMarker() {
    #expect(throws: ProgramContractError.unsupportedMarker("FH-PROGRAM: v2")) {
      try ProgramContractDecoder.decode("FH-PROGRAM: v2\n{\"workouts\":[]}")
    }
  }

  @Test func malformedFieldsReportTheirCodingPath() {
    let text = """
    FH-PROGRAM: v1
    {"workouts":[{"key":"A","items":[{"key":"lift","name":"Lift","prescription":"3 × 5","loadKind":"kg"}]}]}
    """
    do {
      _ = try ProgramContractDecoder.decode(text)
      Issue.record("Expected the unsupported load kind to fail decoding")
    } catch let ProgramContractError.malformedJSON(path, _) {
      #expect(path == "workouts[0].items[0].loadKind")
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test func reportsEmptyFieldsSpecifically() {
    #expect(throws: ProgramContractError.emptyWorkoutKey) {
      try ProgramContractDecoder.validateShape(ProgramContract(workouts: [
        ProgramWorkout(key: "", items: [
          ProgramExercise(key: "x", name: "X", prescription: "3 × 5", loadKind: .bodyweight)
        ])
      ]))
    }
    #expect(throws: ProgramContractError.emptyExerciseKey) {
      try ProgramContractDecoder.validateShape(ProgramContract(workouts: [
        ProgramWorkout(key: "A", items: [
          ProgramExercise(key: "", name: "X", prescription: "3 × 5", loadKind: .bodyweight)
        ])
      ]))
    }
    #expect(throws: ProgramContractError.emptyExerciseName("x")) {
      try ProgramContractDecoder.validateShape(ProgramContract(workouts: [
        ProgramWorkout(key: "A", items: [
          ProgramExercise(key: "x", name: "", prescription: "3 × 5", loadKind: .bodyweight)
        ])
      ]))
    }
    #expect(throws: ProgramContractError.emptyPrescription("x")) {
      try ProgramContractDecoder.validateShape(ProgramContract(workouts: [
        ProgramWorkout(key: "A", items: [
          ProgramExercise(key: "x", name: "X", prescription: "", loadKind: .bodyweight)
        ])
      ]))
    }
  }

  @Test func rejectsEmptyAndDuplicateWorkoutOrExerciseMembership() throws {
    #expect(throws: ProgramContractError.emptyWorkouts) {
      try ProgramContractDecoder.validateShape(ProgramContract(workouts: []))
    }
    #expect(throws: ProgramContractError.emptyWorkout("A")) {
      try ProgramContractDecoder.validateShape(ProgramContract(workouts: [
        ProgramWorkout(key: "A", items: [])
      ]))
    }
    #expect(throws: ProgramContractError.duplicateWorkoutKey("A")) {
      try ProgramContractDecoder.validateShape(ProgramContract(workouts: [
        ProgramWorkout(key: "A", items: [.init(key: "x", name: "X", prescription: "3 × 5", loadKind: .bodyweight)]),
        ProgramWorkout(key: "A", items: [.init(key: "y", name: "Y", prescription: "3 × 5", loadKind: .bodyweight)])
      ]))
    }
    #expect(throws: ProgramContractError.duplicateExerciseKey(workout: "A", exercise: "x")) {
      try ProgramContractDecoder.validateShape(ProgramContract(workouts: [
        ProgramWorkout(key: "A", items: [
          .init(key: "x", name: "X", prescription: "3 × 5", loadKind: .bodyweight),
          .init(key: "x", name: "X", prescription: "2 × 10", loadKind: .bodyweight)
        ])
      ]))
    }
  }
}
