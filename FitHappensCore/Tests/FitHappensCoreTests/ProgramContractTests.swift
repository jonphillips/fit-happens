@testable import FitHappensCore
import Foundation
import Testing

struct StagedProgramTests {
  @Test func stagedProgramChecksAgainstAnExportAndSummarizesChanges() throws {
    let export = try FitHappensChatExport.decode(Data(Self.exportJSON.utf8))
    let text = """
    FH-PROGRAM: v1
    {
      "workouts": [{
        "key": "A",
        "items": [{"key": "bench", "name": "Bench", "prescription": "3 × 5",
          "loadKind": "weight", "newWeight": 150}]
      }]
    }
    """

    #expect(
      StagedProgram.check(text: text, export: export)
        == .valid(.init(changeSummary: "bench 145 → 150 lb"))
    )
  }

  @Test func stagedProgramWithoutExportChecksContractShapeOnly() {
    let text = """
    {
      "workouts": [{
        "key": "A",
        "items": [{"key": "new", "name": "New", "prescription": "3 × 5",
          "loadKind": "weight", "startingWeight": 10}]
      }]
    }
    """
    #expect(StagedProgram.check(text: text, export: nil) == .valid(.init(changeSummary: nil)))
  }

  @Test func stagedProgramReportsS1ValidationErrorsAndNewerMarkers() throws {
    let export = try FitHappensChatExport.decode(Data(Self.emptyExportJSON.utf8))
    let invalid = """
    FH-PROGRAM: v1
    {"workouts":[{"key":"A","items":[{"key":"new","name":"New","prescription":"3 × 5","loadKind":"weight"}]}]}
    """
    #expect(
      StagedProgram.check(text: invalid, export: export)
        == .invalid("New weighted exercise new needs a startingWeight.")
    )
    #expect(
      StagedProgram.check(text: "FH-PROGRAM: v2\n{}", export: nil)
        == .invalid("Unsupported program marker: FH-PROGRAM: v2.")
    )
  }

  @Test func stagedProgramRejectsNewWeightOnANewKeyAndAllowsARename() throws {
    let export = try FitHappensChatExport.decode(Data(Self.exportJSON.utf8))
    let newKey = """
    FH-PROGRAM: v1
    {"workouts":[{"key":"A","items":[
      {"key":"bench","name":"Bench","prescription":"3 × 5","loadKind":"weight"},
      {"key":"new","name":"New","prescription":"3 × 5","loadKind":"weight",
        "startingWeight":10,"newWeight":15}
    ]}]}
    """
    let rename = """
    FH-PROGRAM: v1
    {"workouts":[{"key":"A","items":[
      {"key":"bench","name":"Barbell Bench","prescription":"3 × 5","loadKind":"weight"}
    ]}]}
    """

    #expect(
      StagedProgram.check(text: newKey, export: export)
        == .invalid("New exercise new must use startingWeight instead of newWeight.")
    )
    #expect(
      StagedProgram.check(text: rename, export: export)
        == .valid(.init(changeSummary: "1 other change"))
    )
  }

  private static let exportJSON = """
  {"version":1,"generatedAt":"2026-11-19T12:00:00Z","device":"iPhone",
   "program":{"workouts":[{"key":"A","items":[{"exerciseKey":"bench","prescription":"3 × 5",
   "name":"Bench","loadKind":"weight","currentWeight":145,"increment":5,"loadLabel":null,"notes":null}]}],
   "exercises":[{"key":"bench","name":"Bench","loadKind":"weight","currentWeight":145,
   "increment":5,"loadLabel":null,"notes":null}],"retiredExercises":[],"nextWorkoutKey":"A","lastCompletion":null},
   "completions":[],"walks":[],"bodyMass":[]}
  """

  private static let emptyExportJSON = """
  {"version":1,"generatedAt":"2026-11-19T12:00:00Z","device":"iPhone",
   "program":{"workouts":[],"exercises":[],"retiredExercises":[],"nextWorkoutKey":null,"lastCompletion":null},
   "completions":[],"walks":[],"bodyMass":[]}
  """
}

struct ProgramContractTests {

  @Test func reportsWeightAndDetailChangesWithDefaultResolved() throws {
    let current = CurrentProgram(
      exercises: [CurrentExercise(
        key: "bench", name: "Bench", loadKind: .weight, load: .weight(pounds: 135),
        increment: nil, loadLabel: "each", notes: "pause"
      )],
      workouts: [CurrentWorkout(key: "A", exerciseKeys: ["bench"], prescriptions: ["bench": "3 × 5"])]
    )
    let proposal = ProgramContract(workouts: [ProgramWorkout(key: "A", items: [
      ProgramExercise(
        key: "bench", name: "Bench", prescription: "3 × 5", loadKind: .weight,
        newWeight: 145, increment: 2.5, loadLabel: nil, notes: "touch and go"
      )
    ])])
    let changes = try ProgramChanges.make(current: current, proposal: proposal)
    #expect(changes.weightChanges == [WeightChange(exerciseKey: "bench", oldPounds: 135, newPounds: 145)])
    #expect(changes.incrementChanges == [IncrementChange(exerciseKey: "bench", oldPounds: 5, newPounds: 2.5)])
    #expect(changes.loadLabelChanges == [OptionalTextChange(exerciseKey: "bench", oldValue: "each", newValue: nil)])
    #expect(changes.notesChanges == [
      OptionalTextChange(exerciseKey: "bench", oldValue: "pause", newValue: "touch and go")
    ])
  }

  @Test func explicitDefaultIncrementAndEqualNewWeightAreNotChanges() throws {
    let current = CurrentProgram(
      exercises: [CurrentExercise(
        key: "bench", name: "Bench", loadKind: .weight, load: .weight(pounds: 135)
      )],
      workouts: [CurrentWorkout(key: "A", exerciseKeys: ["bench"], prescriptions: ["bench": "3 × 5"])]
    )
    let proposal = ProgramContract(workouts: [ProgramWorkout(key: "A", items: [
      ProgramExercise(
        key: "bench", name: "Bench", prescription: "3 × 5", loadKind: .weight,
        newWeight: 135, increment: 5
      )
    ])])
    let changes = try ProgramChanges.make(current: current, proposal: proposal)
    #expect(changes.weightChanges.isEmpty)
    #expect(changes.incrementChanges.isEmpty)
  }

  @Test func newWeightRequiresAnExistingWeightedKeyWithSameLoadKind() throws {
    let current = CurrentProgram(
      exercises: [CurrentExercise(
        key: "dip", name: "Dip", loadKind: .bodyweight, load: .bodyweight
      )],
      workouts: [CurrentWorkout(key: "A", exerciseKeys: ["dip"], prescriptions: ["dip": "3 × 5"])]
    )
    let newKey = ProgramContract(workouts: [ProgramWorkout(key: "A", items: [
      ProgramExercise(
        key: "new", name: "New", prescription: "3 × 5", loadKind: .weight,
        startingWeight: 10, newWeight: 15
      )
    ])])
    #expect(throws: ProgramContractError.newWeightOnNewExercise("new")) {
      try ProgramChanges.make(current: current, proposal: newKey)
    }
    let bodyweight = ProgramContract(workouts: [ProgramWorkout(key: "A", items: [
      ProgramExercise(
        key: "dip", name: "Dip", prescription: "3 × 5", loadKind: .bodyweight,
        newWeight: 15
      )
    ])])
    #expect(throws: ProgramContractError.newWeightOnBodyweight("dip")) {
      try ProgramChanges.make(current: current, proposal: bodyweight)
    }
  }

  @Test func newWeightMustBePositive() throws {
    let text = """
    FH-PROGRAM: v1
    {
      "workouts": [{"key":"A","items":[{"key":"bench","name":"Bench",
        "prescription":"3 × 5","loadKind":"weight","newWeight":0}]}]
    }
    """
    #expect(throws: ProgramContractError.invalidWeight("bench")) {
      try ProgramContractDecoder.decode(text)
    }
  }

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
