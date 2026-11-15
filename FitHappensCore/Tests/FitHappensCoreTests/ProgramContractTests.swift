@testable import FitHappensCore
import Foundation
import Testing

struct ProgramContractTests {
  @Test func decodesRealREADMEProgramFixture() throws {
    let url = try #require(
      Bundle.module.url(forResource: "real-program", withExtension: "json", subdirectory: "Fixtures")
    )
    let contract = try ProgramContractDecoder.decode(String(contentsOf: url, encoding: .utf8))
    #expect(contract.workouts.map(\.key) == ["A", "B"])
    #expect(contract.workouts[0].items.map(\.key) == [
      "flat-bench-press", "low-cable-row", "squat-to-bench",
      "standing-cable-hamstring-curl", "dumbbell-lateral-raise"
    ])
    #expect(contract.workouts[1].items.last?.key == "dumbbell-lateral-raise")
    #expect(contract.workouts[0].items[2].loadKind == .bodyweight)
    #expect(contract.workouts[0].items[0].startingWeight == 0)
  }

  @Test func requiresTheContractMarker() {
    #expect(throws: ProgramContractError.missingMarker) {
      try ProgramContractDecoder.decode("{\"workouts\":[]}")
    }
  }

  @Test func rejectsAContractForANewerMarker() {
    #expect(throws: ProgramContractError.unsupportedMarker("FH-PROGRAM-2")) {
      try ProgramContractDecoder.decode("FH-PROGRAM-2\n{\"workouts\":[]}")
    }
  }

  @Test func rejectsInvalidJSON() {
    #expect(throws: ProgramContractError.malformedJSON) {
      try ProgramContractDecoder.decode("FH-PROGRAM-1\nnot json")
    }
  }

  @Test func rejectsEmptyAndDuplicateWorkoutKeys() {
    let empty = ProgramContract(workouts: [])
    #expect(throws: ProgramContractError.emptyWorkouts) {
      try ProgramContractDecoder.validateShape(empty)
    }
    let duplicate = ProgramContract(workouts: [
      ProgramWorkout(key: "A", items: []), ProgramWorkout(key: "A", items: [])
    ])
    #expect(throws: ProgramContractError.duplicateWorkoutKey("A")) {
      try ProgramContractDecoder.validateShape(duplicate)
    }
  }
}
