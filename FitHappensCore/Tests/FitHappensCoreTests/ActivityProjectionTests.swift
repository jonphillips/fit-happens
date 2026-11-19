import FitHappensCore
import Foundation
import Testing

struct ActivityProjectionTests {
  @Test func calendarHasFourLocaleWeeksAndCombinesWorkoutKinds() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12)))
    let strengthDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 8)))
    let walkDay = HealthWalkingWorkout(
      id: UUID(), start: strengthDay, end: strengthDay.addingTimeInterval(3_600), distanceMeters: 1_609.344
    )
    let completion = Completion(id: UUID(), workoutKey: "A", completedAt: strengthDay)
    let days = ActivityProjection.calendarDays(
      now: now, calendar: calendar, completions: [completion], strengthWorkouts: [],
      walkingWorkouts: [walkDay]
    )

    #expect(days.count == 28)
    #expect(calendar.component(.day, from: days[0].date) == 26)
    #expect(days[22].training == .both)
    #expect(days[22].walkingMiles == 1)
    #expect(days[24].training == .neither)
  }

  @Test func progressionUsesLatestSnapshotAtLeastNinetyDaysOld() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 12)))
    let exercise = Exercise(
      id: UUID(), key: "bench", name: "Bench press", loadKind: .weight, currentLoadPounds: 145
    )
    let snapshots = [-120, -95, -80].map { daysAgo in
      Completion(id: UUID(), workoutKey: "A", completedAt: calendar.date(byAdding: .day, value: daysAgo, to: now)!)
    }
    let items = zip(snapshots, [100.0, 110.0, 120.0]).map { completion, pounds in
      CompletionItem(
        id: UUID(), completionID: completion.id, exerciseID: exercise.id, position: 0,
        name: exercise.name, prescription: "3 × 5", loadKind: .weight, loadPounds: pounds
      )
    }

    let progression = try #require(ActivityProjection.progression(
      exercise: exercise, completions: snapshots, items: items, now: now, calendar: calendar
    ))
    #expect(progression.previousPounds == 110)
    #expect(progression.previousDate == snapshots[1].completedAt)
  }
}
