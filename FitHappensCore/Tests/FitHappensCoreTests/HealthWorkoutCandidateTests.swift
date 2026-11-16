import CustomDump
@testable import FitHappensCore
import Foundation
import Testing

struct HealthWorkoutCandidateTests {
  @Test func candidateStartsAfterLatestCompletionAndRejectsWorkoutThatOnlyEndedAfter() {
    let latestCompletion = Date(timeIntervalSince1970: 99_970)
    let now = Date(timeIntervalSince1970: 100_000)
    let startedBeforeButEndedAfter = HealthWorkout(
      id: healthWorkoutID(1), start: Date(timeIntervalSince1970: 99_960), end: Date(timeIntervalSince1970: 99_980)
    )
    let startedAfter = HealthWorkout(
      id: healthWorkoutID(2), start: Date(timeIntervalSince1970: 99_971), end: Date(timeIntervalSince1970: 99_990)
    )

    let candidate = StrengthWorkoutCandidate.pick(
      from: [startedBeforeButEndedAfter, startedAfter],
      latestCompletionAt: latestCompletion,
      linkedWorkoutIDs: [],
      declinedWorkoutIDs: [],
      now: now
    )

    expectNoDifference(candidate, startedAfter)
  }

  @Test func candidateIncludesWorkoutAtTwelveHourBoundaryAndRejectsOlderWorkout() {
    let now = Date(timeIntervalSince1970: 100_000)
    let atBoundary = HealthWorkout(
      id: healthWorkoutID(3), start: Date(timeIntervalSince1970: 56_700), end: Date(timeIntervalSince1970: 56_800)
    )
    let outsideWindow = HealthWorkout(
      id: healthWorkoutID(4), start: Date(timeIntervalSince1970: 56_698), end: Date(timeIntervalSince1970: 56_799)
    )

    let candidate = StrengthWorkoutCandidate.pick(
      from: [outsideWindow, atBoundary],
      latestCompletionAt: nil,
      linkedWorkoutIDs: [],
      declinedWorkoutIDs: [],
      now: now
    )

    expectNoDifference(candidate, atBoundary)
  }

  @Test func candidateExcludesLinkedWorkouts() {
    let now = Date(timeIntervalSince1970: 100_000)
    let linked = HealthWorkout(
      id: healthWorkoutID(5), start: Date(timeIntervalSince1970: 99_970), end: Date(timeIntervalSince1970: 99_990)
    )
    let unlinked = HealthWorkout(
      id: healthWorkoutID(6), start: Date(timeIntervalSince1970: 99_960), end: Date(timeIntervalSince1970: 99_980)
    )

    let candidate = StrengthWorkoutCandidate.pick(
      from: [linked, unlinked],
      latestCompletionAt: nil,
      linkedWorkoutIDs: [linked.id],
      declinedWorkoutIDs: [],
      now: now
    )

    expectNoDifference(candidate, unlinked)
  }

  @Test func candidateExcludesDeclinedWorkouts() {
    let now = Date(timeIntervalSince1970: 100_000)
    let declined = HealthWorkout(
      id: healthWorkoutID(7), start: Date(timeIntervalSince1970: 99_970), end: Date(timeIntervalSince1970: 99_990)
    )
    let notDeclined = HealthWorkout(
      id: healthWorkoutID(8), start: Date(timeIntervalSince1970: 99_960), end: Date(timeIntervalSince1970: 99_980)
    )

    let candidate = StrengthWorkoutCandidate.pick(
      from: [declined, notDeclined],
      latestCompletionAt: nil,
      linkedWorkoutIDs: [],
      declinedWorkoutIDs: [declined.id],
      now: now
    )

    expectNoDifference(candidate, notDeclined)
  }

  @Test func mostRecentEligibleWorkoutWins() {
    let now = Date(timeIntervalSince1970: 100_000)
    let earlier = HealthWorkout(
      id: healthWorkoutID(9), start: Date(timeIntervalSince1970: 99_950), end: Date(timeIntervalSince1970: 99_970)
    )
    let later = HealthWorkout(
      id: healthWorkoutID(10), start: Date(timeIntervalSince1970: 99_960), end: Date(timeIntervalSince1970: 99_980)
    )

    let candidate = StrengthWorkoutCandidate.pick(
      from: [earlier, later],
      latestCompletionAt: nil,
      linkedWorkoutIDs: [],
      declinedWorkoutIDs: [],
      now: now
    )

    expectNoDifference(candidate, later)
  }
}

private func healthWorkoutID(_ value: Int) -> UUID {
  UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
}
