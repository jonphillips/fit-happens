import FitHappensCore
import HealthKit

enum HealthKitClient {
  static var live: HealthClient {
    let store = HealthStore()
    return HealthClient(
      requestReadAuthorization: { try await store.requestReadAuthorization() },
      strengthWorkouts: { start, end in try await store.strengthWorkouts(start: start, end: end) },
      walkingWorkouts: { start, end in try await store.walkingWorkouts(start: start, end: end) },
      latestBodyMass: { try await store.latestBodyMass() }
    )
  }
}

private actor HealthStore {
  private let store = HKHealthStore()

  func requestReadAuthorization() async throws {
    guard HKHealthStore.isHealthDataAvailable() else {
      return
    }
    let distance = HKQuantityType(.distanceWalkingRunning)
    let bodyMass = HKQuantityType(.bodyMass)
    try await store.requestAuthorization(
      toShare: [],
      read: [HKObjectType.workoutType(), distance, bodyMass]
    )
  }

  func strengthWorkouts(start: Date, end: Date) async throws -> [HealthWorkout] {
    guard HKHealthStore.isHealthDataAvailable() else {
      return []
    }
    let workouts = try await queryWorkouts(start: start, end: end)
    return workouts
      .filter {
        $0.workoutActivityType == .traditionalStrengthTraining
          || $0.workoutActivityType == .functionalStrengthTraining
      }
      .map { HealthWorkout(id: $0.uuid, start: $0.startDate, end: $0.endDate) }
  }

  func walkingWorkouts(start: Date, end: Date) async throws -> [HealthWalkingWorkout] {
    guard HKHealthStore.isHealthDataAvailable() else {
      return []
    }
    let distance = HKQuantityType(.distanceWalkingRunning)
    return try await queryWorkouts(start: start, end: end)
      .filter { $0.workoutActivityType == .walking }
      .map { workout in
        HealthWalkingWorkout(
          id: workout.uuid,
          start: workout.startDate,
          end: workout.endDate,
          distanceMeters: workout.statistics(for: distance)?.sumQuantity()?.doubleValue(for: .meter())
        )
      }
  }

  func latestBodyMass() async throws -> HealthBodyMass? {
    guard HKHealthStore.isHealthDataAvailable() else {
      return nil
    }
    let type = HKQuantityType(.bodyMass)
    let descriptor = HKSampleQueryDescriptor(
      predicates: [.quantitySample(type: type)],
      sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
      limit: 1
    )
    guard let sample = try await descriptor.result(for: store).first else {
      return nil
    }
    return HealthBodyMass(pounds: sample.quantity.doubleValue(for: .pound()), date: sample.endDate)
  }

  private func queryWorkouts(start: Date, end: Date) async throws -> [HKWorkout] {
    let datePredicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictEndDate])
    let descriptor = HKSampleQueryDescriptor(
      predicates: [.workout(datePredicate)],
      sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
      limit: nil
    )
    return try await descriptor.result(for: store)
  }
}
