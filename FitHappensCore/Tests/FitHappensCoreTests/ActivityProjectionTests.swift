import FitHappensCore
import Foundation
import Testing

struct ActivityProjectionTests {
  @Test func calendarHasFourLocaleWeeksAndCombinesWorkoutKinds() throws {
    let calendar = makeCalendar()
    let now = makeDate(calendar, day: 18, hour: 12)
    let strengthDay = makeDate(calendar, day: 17, hour: 8)
    let walk = HealthWalkingWorkout(
      id: UUID(), start: strengthDay, end: strengthDay.addingTimeInterval(3_600), distanceMeters: 1_609.344
    )
    let completion = Completion(id: UUID(), workoutKey: "A", completedAt: strengthDay)
    let days = ActivityProjection.calendarDays(
      now: now, calendar: calendar, completions: [completion], strengthWorkouts: [], walkingWorkouts: [walk]
    )

    #expect(days.count == 28)
    #expect(calendar.component(.day, from: days[0].date) == 26)
    #expect(days[22].training == .both)
    #expect(days[22].walkingMiles == 1)
  }

  @Test func futureDayRemainsBlankEvenWhenHealthHasWorkouts() {
    let calendar = makeCalendar()
    let now = makeDate(calendar, day: 18, hour: 12)
    let futureDate = makeDate(calendar, day: 19, hour: 8)
    let completion = Completion(id: UUID(), workoutKey: "A", completedAt: futureDate)
    let strength = HealthWorkout(id: UUID(), start: futureDate, end: futureDate.addingTimeInterval(3_600))
    let walk = HealthWalkingWorkout(
      id: UUID(), start: futureDate, end: futureDate.addingTimeInterval(3_600), distanceMeters: 1_000
    )

    let day = ActivityProjection.calendarDays(
      now: now, calendar: calendar, completions: [completion], strengthWorkouts: [strength], walkingWorkouts: [walk]
    )[24]

    #expect(day.isFuture)
    #expect(day.training == .neither)
    #expect(day.walkingMiles == nil)
  }

  @Test func healthStrengthWorkoutAloneMarksStrengthDay() {
    let calendar = makeCalendar()
    let now = makeDate(calendar, day: 18, hour: 12)
    let workoutDate = makeDate(calendar, day: 17, hour: 8)
    let strength = HealthWorkout(id: UUID(), start: workoutDate, end: workoutDate.addingTimeInterval(3_600))

    let day = ActivityProjection.calendarDays(
      now: now, calendar: calendar, completions: [], strengthWorkouts: [strength], walkingWorkouts: []
    )[22]

    #expect(day.training == .strength)
  }

  @Test func walkWithoutDistanceShowsWalkMarkWithoutMiles() {
    let calendar = makeCalendar()
    let now = makeDate(calendar, day: 18, hour: 12)
    let walkDate = makeDate(calendar, day: 17, hour: 8)
    let walk = HealthWalkingWorkout(
      id: UUID(), start: walkDate, end: walkDate.addingTimeInterval(3_600), distanceMeters: nil
    )

    let day = ActivityProjection.calendarDays(
      now: now, calendar: calendar, completions: [], strengthWorkouts: [], walkingWorkouts: [walk]
    )[22]

    #expect(day.training == .walking)
    #expect(day.walkingMiles == nil)
  }

  @Test func progressionUsesLatestSnapshotAtLeastNinetyDaysOldIncludingSyncedExerciseRows() throws {
    let calendar = makeCalendar()
    let now = makeDate(calendar, day: 19, hour: 12)
    let exercise = bench(id: "00000000-0000-0000-0000-000000000001", pounds: 145)
    let syncedExercise = bench(id: "00000000-0000-0000-0000-000000000002", pounds: 145)
    let snapshots = [-120, -95, -80].map { daysAgo in
      Completion(id: UUID(), workoutKey: "A", completedAt: calendar.date(byAdding: .day, value: daysAgo, to: now)!)
    }
    let items = zip(snapshots, [100.0, 110.0, 120.0]).map { completion, pounds in
      completionItem(completion, exercise: syncedExercise, pounds: pounds)
    }

    let progression = try #require(ActivityProjection.progression(
      exercise: exercise, exercises: [exercise, syncedExercise], completions: snapshots,
      items: items, now: now, calendar: calendar
    ))

    #expect(progression.previousPounds == 110)
    #expect(progression.previousDate == snapshots[1].completedAt)
  }

  @Test func progressionFallsBackToEarliestSnapshotWhenNoneIsNinetyDaysOld() throws {
    let calendar = makeCalendar()
    let now = makeDate(calendar, day: 19, hour: 12)
    let exercise = bench(id: "00000000-0000-0000-0000-000000000001", pounds: 145)
    let snapshots = [-80, -20].map { daysAgo in
      Completion(id: UUID(), workoutKey: "A", completedAt: calendar.date(byAdding: .day, value: daysAgo, to: now)!)
    }
    let items = zip(snapshots, [120.0, 135.0]).map { completion, pounds in
      completionItem(completion, exercise: exercise, pounds: pounds)
    }

    let progression = try #require(ActivityProjection.progression(
      exercise: exercise, exercises: [exercise], completions: snapshots,
      items: items, now: now, calendar: calendar
    ))

    #expect(progression.previousPounds == 120)
    #expect(progression.previousDate == snapshots[0].completedAt)
  }

  @Test func progressionWithoutSnapshotsShowsCurrentWeightAlone() throws {
    let calendar = makeCalendar()
    let now = makeDate(calendar, day: 19, hour: 12)
    let exercise = bench(id: "00000000-0000-0000-0000-000000000001", pounds: 145)

    let progression = try #require(ActivityProjection.progression(
      exercise: exercise, exercises: [exercise], completions: [], items: [], now: now, calendar: calendar
    ))

    #expect(progression.currentPounds == 145)
    #expect(progression.previousPounds == nil)
    #expect(progression.previousDate == nil)
  }

  @Test func defaultIsFirstEligibleWeightedExerciseInWorkoutOrder() throws {
    let retired = Exercise(
      id: UUID(), key: "retired", name: "Retired", loadKind: .weight,
      currentLoadPounds: 50, isRetired: true
    )
    let bodyweight = Exercise(id: UUID(), key: "pushup", name: "Push-up", loadKind: .bodyweight)
    let row = Exercise(id: UUID(), key: "row", name: "Row", loadKind: .weight, currentLoadPounds: 95)
    let bench = bench(id: "00000000-0000-0000-0000-000000000001", pounds: 145)
    let squat = Exercise(id: UUID(), key: "squat", name: "Squat", loadKind: .weight, currentLoadPounds: 185)
    let program = CurrentProgram(exercises: [], workouts: [
      CurrentWorkout(key: "A", exerciseKeys: ["retired", "pushup", "row", "bench"], prescriptions: [:]),
      CurrentWorkout(key: "B", exerciseKeys: ["squat"], prescriptions: [:])
    ])
    let exercises = [retired, bodyweight, row, bench, squat]

    let ordered = ActivityProjection.orderedWeightedExercises(program: program, exercises: exercises)
    let defaultExercise = try #require(ActivityProjection.defaultExercise(program: program, exercises: exercises))

    #expect(ordered.map(\.key) == ["row", "bench", "squat"])
    #expect(defaultExercise.key == "row")

    let noWeightsInFirstWorkout = CurrentProgram(exercises: [], workouts: [
      CurrentWorkout(key: "A", exerciseKeys: ["retired", "pushup"], prescriptions: [:]),
      CurrentWorkout(key: "B", exerciseKeys: ["squat"], prescriptions: [:])
    ])
    #expect(ActivityProjection.defaultExercise(program: noWeightsInFirstWorkout, exercises: exercises)?.key == "squat")
  }

  private func makeCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2
    return calendar
  }

  private func makeDate(_ calendar: Calendar, day: Int, hour: Int) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
  }

  private func bench(id: String, pounds: Double) -> Exercise {
    Exercise(
      id: UUID(uuidString: id)!, key: "bench", name: "Bench press", loadKind: .weight, currentLoadPounds: pounds
    )
  }

  private func completionItem(_ completion: Completion, exercise: Exercise, pounds: Double) -> CompletionItem {
    CompletionItem(
      id: UUID(), completionID: completion.id, exerciseID: exercise.id, position: 0,
      name: exercise.name, prescription: "3 × 5", loadKind: .weight, loadPounds: pounds
    )
  }
}
