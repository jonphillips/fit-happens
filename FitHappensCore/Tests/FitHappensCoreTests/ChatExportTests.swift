@testable import FitHappensCore
import Foundation
import Testing

struct ChatExportTests {
  @Test func builderExportsProgramHistoryWalksAndLatestDailyWeights() throws {
    let day = Date(timeIntervalSince1970: 1_790_000_000)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let benchID = UUID()
    let curlID = UUID()
    let completionID = UUID()
    let bench = Exercise(id: benchID, key: "bench", name: "Bench", loadKind: .weight, currentLoadPounds: 145)
    let curl = Exercise(
      id: curlID, key: "curl", name: "Curl", loadKind: .weight,
      currentLoadPounds: 20, isRetired: true
    )
    let program = CurrentProgram(
      exercises: [CurrentExercise(key: "bench", name: "Bench", loadKind: .weight, load: .weight(pounds: 145))],
      retiredExercises: [CurrentExercise(key: "curl", name: "Curl", loadKind: .weight, load: .weight(pounds: 20))],
      workouts: [CurrentWorkout(key: "A", exerciseKeys: ["bench"], prescriptions: ["bench": "3 × 5"])]
    )
    let completion = Completion(id: completionID, workoutKey: "A", completedAt: day)
    let item = CompletionItem(
      id: UUID(), completionID: completionID, exerciseID: benchID, position: 0,
      name: "Bench", prescription: "3 × 5", loadKind: .weight, loadPounds: 140
    )
    let mass = [
      HealthBodyMass(pounds: 180, date: day),
      HealthBodyMass(pounds: 179, date: day.addingTimeInterval(3600))
    ]
    let export = FitHappensChatExportBuilder.make(
      program: program, completions: [completion], completionItems: [item], exercises: [bench, curl],
      walks: [HealthWalkingWorkout(id: UUID(), start: day, end: day, distanceMeters: nil)],
      bodyMass: mass, generatedAt: day.addingTimeInterval(7200), device: "iPhone", calendar: calendar
    )
    #expect(export.program.nextWorkoutKey == "A")
    #expect(export.program.exercises.first?.increment == 5)
    #expect(export.program.retiredExercises.first?.currentWeight == 20)
    #expect(export.program.workouts.first?.items.first?.prescription == "3 × 5")
    #expect(export.completions.first?.items.first?.loadPounds == 140)
    #expect(export.walks.first?.miles == nil)
    #expect(export.bodyMass.count == 1)
    #expect(export.bodyMass.first?.pounds == 179)
  }

  @Test func exportRoundTripsAndRejectsANewerVersion() throws {
    let export = FitHappensChatExport(
      generatedAt: Date(timeIntervalSince1970: 1), device: "iPhone",
      program: ChatProgram(workouts: [], exercises: [], retiredExercises: [], nextWorkoutKey: nil, lastCompletion: nil),
      completions: [], walks: [], bodyMass: []
    )
    let data = try export.encoded()
    #expect(try FitHappensChatExport.decode(data) == export)
    let json = String(decoding: data, as: UTF8.self)
      .replacingOccurrences(of: "\"version\":1", with: "\"version\":2")
    let newer = Data(json.utf8)
    #expect(throws: FitHappensChatExport.DecodeError.unsupportedVersion(2)) {
      try FitHappensChatExport.decode(newer)
    }
  }

  @Test func historyAndActivityReportFilteredDataAndLatestWeight() throws {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let recent = ChatBodyMass(date: now.addingTimeInterval(-10), pounds: 175)
    let export = FitHappensChatExport(
      generatedAt: now, device: "iPhone",
      program: ChatProgram(workouts: [], exercises: [], retiredExercises: [], nextWorkoutKey: nil, lastCompletion: nil),
      completions: [ChatCompletion(date: now, workoutKey: "A", items: [])],
      walks: [ChatWalk(date: now, miles: 2)], bodyMass: [recent]
    )
    #expect(FitHappensChatProjection.history(export, days: 90).count == 1)
    #expect(FitHappensChatProjection.history(export, days: 1, exercise: "missing").isEmpty)
    let activity = FitHappensChatProjection.activity(export, days: 90)
    #expect(activity.bodyMass == [recent])
    #expect(activity.latestBodyMass == recent)
  }

  @Test func historyProjectionIdentifiesSnapshotLoadChangeDates() throws {
    let firstDate = Date(timeIntervalSince1970: 1_790_000_000)
    let laterDate = firstDate.addingTimeInterval(10 * 86_400)
    let export = FitHappensChatExport(
      generatedAt: laterDate, device: "iPhone",
      program: ChatProgram(workouts: [], exercises: [], retiredExercises: [], nextWorkoutKey: nil, lastCompletion: nil),
      completions: [
        ChatCompletion(date: firstDate, workoutKey: "A", items: [
          ChatCompletionItem(exerciseKey: "bench", loadKind: .weight, loadPounds: 135)
        ]),
        ChatCompletion(date: laterDate, workoutKey: "B", items: [
          ChatCompletionItem(exerciseKey: "bench", loadKind: .weight, loadPounds: 145)
        ])
      ], walks: [], bodyMass: []
    )
    let history = FitHappensChatProjection.historyDetails(export, days: 30, exercise: "bench")
    #expect(history.completions.count == 2)
    #expect(history.loadChanges == [ChatLoadChange(exerciseKey: "bench", date: laterDate, pounds: 145)])
  }

  @Test func rotationStillUsesTheLastCompletionOutsideTheExportWindow() throws {
    let yearAgo = Date(timeIntervalSince1970: 1_700_000_000)
    let now = yearAgo.addingTimeInterval(400 * 86_400)
    let program = CurrentProgram(
      exercises: [], workouts: [
        CurrentWorkout(key: "A", exerciseKeys: [], prescriptions: [:]),
        CurrentWorkout(key: "B", exerciseKeys: [], prescriptions: [:])
      ]
    )
    let oldCompletion = Completion(id: UUID(), workoutKey: "A", completedAt: yearAgo)
    let export = FitHappensChatExportBuilder.make(
      program: program, completions: [oldCompletion], completionItems: [], exercises: [],
      walks: [], bodyMass: [], generatedAt: now, device: "iPhone"
    )
    #expect(export.completions.isEmpty)
    #expect(export.program.lastCompletion?.date == yearAgo)
    #expect(export.program.nextWorkoutKey == "B")
  }
}
