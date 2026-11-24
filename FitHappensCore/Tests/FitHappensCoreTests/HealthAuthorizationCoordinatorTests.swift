import FitHappensCore
import Foundation
import Testing

@Suite
struct HealthAuthorizationCoordinatorTests {
  @Test
  func answersUnnecessaryWithoutRequesting() async throws {
    let requests = CallCounter()
    let coordinator = HealthAuthorizationCoordinator(
      requestStatus: { .unnecessary },
      requestAuthorization: { await requests.increment() }
    )

    #expect(try await coordinator.requestReadAccess() == .ready)
    #expect(await requests.value == 0)
  }

  @Test
  func remainsNeedsRequestWhenStatusDoesNotChange() async throws {
    let statusChecks = CallCounter()
    let requests = CallCounter()
    let coordinator = HealthAuthorizationCoordinator(
      requestStatus: {
        await statusChecks.increment()
        return .shouldRequest
      },
      requestAuthorization: { await requests.increment() }
    )

    #expect(try await coordinator.requestReadAccess() == .needsRequest)
    #expect(await statusChecks.value == 2)
    #expect(await requests.value == 1)
  }

  @Test
  func repeatsRequestOnEachActivationUntilAnswered() async throws {
    let statusChecks = CallCounter()
    let requests = CallCounter()
    let coordinator = HealthAuthorizationCoordinator(
      requestStatus: {
        await statusChecks.increment()
        return .shouldRequest
      },
      requestAuthorization: { await requests.increment() }
    )

    #expect(try await coordinator.requestReadAccess() == .needsRequest)
    #expect(try await coordinator.requestReadAccess() == .needsRequest)
    #expect(await statusChecks.value == 4)
    #expect(await requests.value == 2)
  }

  @Test
  func propagatesCancellationFromRequest() async {
    let coordinator = HealthAuthorizationCoordinator(
      requestStatus: { .shouldRequest },
      requestAuthorization: { throw CancellationError() }
    )

    do {
      _ = try await coordinator.requestReadAccess()
      Issue.record("Expected CancellationError")
    } catch is CancellationError {
      // Expected.
    } catch {
      Issue.record("Expected CancellationError, received \(error)")
    }
  }

  @Test
  func reportsRequestFailureWithItsDescription() async throws {
    let coordinator = HealthAuthorizationCoordinator(
      requestStatus: { .shouldRequest },
      requestAuthorization: { throw TestFailure.denied }
    )

    #expect(try await coordinator.requestReadAccess() == .failed("The request failed."))
  }

  @Test
  func overlappingCallsShareOneRequest() async throws {
    let requests = CallCounter()
    let statusChecks = StatusSequence()
    let coordinator = HealthAuthorizationCoordinator(
      requestStatus: { await statusChecks.next() },
      requestAuthorization: {
        await requests.increment()
        try await Task.sleep(for: .milliseconds(50))
      }
    )

    async let first = coordinator.requestReadAccess()
    async let second = coordinator.requestReadAccess()
    #expect(try await first == .ready)
    #expect(try await second == .ready)
    #expect(await requests.value == 1)
    #expect(await statusChecks.value == 2)
  }
}

private actor CallCounter {
  private(set) var value = 0

  func increment() {
    value += 1
  }
}

private actor StatusSequence {
  private(set) var value = 0

  func next() -> HealthAuthorizationRequestStatus {
    value += 1
    return value == 1 ? .shouldRequest : .unnecessary
  }
}

private enum TestFailure: Error, LocalizedError {
  case denied

  var errorDescription: String? { "The request failed." }
}
