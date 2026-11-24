import Dependencies
import Foundation

public struct HealthWorkout: Equatable, Identifiable, Sendable {
  public var id: UUID
  public var start: Date
  public var end: Date

  public init(id: UUID, start: Date, end: Date) {
    self.id = id
    self.start = start
    self.end = end
  }
}

public struct HealthWalkingWorkout: Equatable, Identifiable, Sendable {
  public var id: UUID
  public var start: Date
  public var end: Date
  public var distanceMeters: Double?

  public init(id: UUID, start: Date, end: Date, distanceMeters: Double?) {
    self.id = id
    self.start = start
    self.end = end
    self.distanceMeters = distanceMeters
  }
}

public struct HealthBodyMass: Equatable, Sendable {
  public var pounds: Double
  public var date: Date

  public init(pounds: Double, date: Date) {
    self.pounds = pounds
    self.date = date
  }
}

public enum HealthReadAccess: Equatable, Sendable {
  case ready
  case needsRequest
  case failed(String)
}

public enum HealthAuthorizationRequestStatus: Equatable, Sendable {
  case shouldRequest
  case unnecessary
  case unknown
}

public actor HealthAuthorizationCoordinator {
  private let requestStatus: @Sendable () async throws -> HealthAuthorizationRequestStatus
  private let requestAuthorization: @Sendable () async throws -> Void
  private var inFlight: Task<HealthReadAccess, Error>?

  public init(
    requestStatus: @escaping @Sendable () async throws -> HealthAuthorizationRequestStatus,
    requestAuthorization: @escaping @Sendable () async throws -> Void
  ) {
    self.requestStatus = requestStatus
    self.requestAuthorization = requestAuthorization
  }

  public func requestReadAccess() async throws -> HealthReadAccess {
    try Task.checkCancellation()
    if let inFlight {
      let result = try await inFlight.value
      try Task.checkCancellation()
      return result
    }

    let task = Task { try await self.checkAndRequest() }
    inFlight = task
    defer { inFlight = nil }
    let result = try await task.value
    try Task.checkCancellation()
    return result
  }

  private func checkAndRequest() async throws -> HealthReadAccess {
    do {
      let status = try await requestStatus()
      guard status == .shouldRequest else {
        return status == .unnecessary ? .ready : .failed("Health authorization status is unavailable.")
      }

      try await requestAuthorization()
      try Task.checkCancellation()
      let updatedStatus = try await requestStatus()
      return switch updatedStatus {
      case .shouldRequest: .needsRequest
      case .unnecessary: .ready
      case .unknown: .failed("Health authorization status is unavailable.")
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return .failed(error.localizedDescription)
    }
  }
}

public struct HealthClient: Sendable {
  public var requestReadAuthorization: @Sendable () async throws -> HealthReadAccess
  public var strengthWorkouts: @Sendable (Date, Date) async throws -> [HealthWorkout]
  public var walkingWorkouts: @Sendable (Date, Date) async throws -> [HealthWalkingWorkout]
  public var latestBodyMass: @Sendable () async throws -> HealthBodyMass?
  public var bodyMassSamples: @Sendable (Date, Date) async throws -> [HealthBodyMass]

  public init(
    requestReadAuthorization: @escaping @Sendable () async throws -> HealthReadAccess,
    strengthWorkouts: @escaping @Sendable (Date, Date) async throws -> [HealthWorkout],
    walkingWorkouts: @escaping @Sendable (Date, Date) async throws -> [HealthWalkingWorkout],
    latestBodyMass: @escaping @Sendable () async throws -> HealthBodyMass?,
    bodyMassSamples: @escaping @Sendable (Date, Date) async throws -> [HealthBodyMass]
  ) {
    self.requestReadAuthorization = requestReadAuthorization
    self.strengthWorkouts = strengthWorkouts
    self.walkingWorkouts = walkingWorkouts
    self.latestBodyMass = latestBodyMass
    self.bodyMassSamples = bodyMassSamples
  }

  public static let unimplemented = Self(
    requestReadAuthorization: { fatalError("HealthClient is not configured") },
    strengthWorkouts: { _, _ in fatalError("HealthClient is not configured") },
    walkingWorkouts: { _, _ in fatalError("HealthClient is not configured") },
    latestBodyMass: { fatalError("HealthClient is not configured") },
    bodyMassSamples: { _, _ in fatalError("HealthClient is not configured") }
  )

  public static let preview = Self(
    requestReadAuthorization: { .ready },
    strengthWorkouts: { _, _ in [] },
    walkingWorkouts: { _, _ in [] },
    latestBodyMass: { nil },
    bodyMassSamples: { _, _ in [] }
  )

  public static let test = Self(
    requestReadAuthorization: { .ready },
    strengthWorkouts: { _, _ in [] },
    walkingWorkouts: { _, _ in [] },
    latestBodyMass: { nil },
    bodyMassSamples: { _, _ in [] }
  )
}

private enum HealthClientKey: DependencyKey {
  static var liveValue: HealthClient { .unimplemented }
  static var previewValue: HealthClient { .preview }
  static var testValue: HealthClient { .test }
}

public extension DependencyValues {
  var healthClient: HealthClient {
    get { self[HealthClientKey.self] }
    set { self[HealthClientKey.self] = newValue }
  }
}

public enum StrengthWorkoutCandidate {
  public static func pick(
    from workouts: [HealthWorkout],
    latestCompletionAt: Date?,
    linkedWorkoutIDs: Set<UUID>,
    declinedWorkoutIDs: Set<UUID>,
    now: Date
  ) -> HealthWorkout? {
    workouts
      .filter { workout in
        workout.start > (latestCompletionAt ?? .distantPast)
          && workout.end >= now.addingTimeInterval(-12 * 60 * 60)
          && workout.end <= now
          && !linkedWorkoutIDs.contains(workout.id)
          && !declinedWorkoutIDs.contains(workout.id)
      }
      .max { $0.end < $1.end }
  }
}
