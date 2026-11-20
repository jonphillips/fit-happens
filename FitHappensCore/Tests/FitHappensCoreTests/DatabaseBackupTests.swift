import CloudSyncKit
@testable import FitHappensCore
import Foundation
import SQLiteData
import Testing

struct DatabaseBackupTests {
  @Test func backupConfigurationAcceptsTheFitHappensStoreAndRejectsAnUnrelatedDatabase() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fitHappensURL = directory.appendingPathComponent("fit-happens.sqlite")
    let database = try migratedDatabase(at: fitHappensURL)

    try DatabaseBackup.validateAppSchema(
      in: fitHappensURL,
      configuration: FitHappensCloudSync.databaseBackupConfiguration
    )
    try database.close()

    let unrelatedURL = directory.appendingPathComponent("unrelated.sqlite")
    let unrelated = try DatabaseQueue(path: unrelatedURL.path)
    try unrelated.write { try $0.execute(sql: "CREATE TABLE unrelated (id TEXT PRIMARY KEY NOT NULL)") }
    try unrelated.close()

    do {
      try DatabaseBackup.validateAppSchema(
        in: unrelatedURL,
        configuration: FitHappensCloudSync.databaseBackupConfiguration
      )
      Issue.record("Expected an unrelated SQLite database to be rejected.")
    } catch {
      #expect((error as? DatabaseBackup.BackupError) == .notAppBackup("Fit Happens"))
    }
  }

  @Test func seededFitHappensStoreRoundTripsEverySyncedRowThroughRestore() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let liveStoreURL = directory.appendingPathComponent("SQLiteData.db")
    let snapshotURL = directory.appendingPathComponent("FitHappens-Backup.sqlite")
    let stagingURL = directory.appendingPathComponent("FitHappens-Restore.sqlite")
    let database = try migratedDatabase(at: liveStoreURL)
    try seedStore(database)
    let expected = try syncedRows(in: database)

    _ = try await DatabaseBackup.snapshot(
      from: database,
      to: snapshotURL,
      configuration: FitHappensCloudSync.databaseBackupConfiguration
    )
    let prepared = try await DatabaseBackup.prepareRestore(
      from: snapshotURL,
      to: stagingURL,
      currentSchemaVersion: FitHappensDatabaseMigrations.schemaVersion,
      configuration: FitHappensCloudSync.databaseBackupConfiguration,
      migrate: { try FitHappensDatabaseMigrations.migrateRestoreCandidate(at: $0) }
    )

    try database.close()
    try DatabaseBackup.replaceLiveStore(
      at: liveStoreURL,
      with: prepared,
      syncMetadataURL: directory.appendingPathComponent("sync-metadata.sqlite")
    )
    let restoredDatabase = try DatabaseQueue(path: liveStoreURL.path)
    #expect(try syncedRows(in: restoredDatabase) == expected)
    try restoredDatabase.close()
  }
}

private struct SyncedRows: Equatable {
  var exercises: [Exercise]
  var workouts: [Workout]
  var workoutItems: [WorkoutItem]
  var programRevisions: [ProgramRevision]
  var completions: [Completion]
  var completionItems: [CompletionItem]
}

private func syncedRows(in database: any DatabaseReader) throws -> SyncedRows {
  try database.read { connection in
    SyncedRows(
      exercises: try Exercise.all.fetchAll(connection),
      workouts: try Workout.all.fetchAll(connection),
      workoutItems: try WorkoutItem.all.fetchAll(connection),
      programRevisions: try ProgramRevision.all.fetchAll(connection),
      completions: try Completion.all.fetchAll(connection),
      completionItems: try CompletionItem.all.fetchAll(connection)
    )
  }
}

private func seedStore(_ database: DatabaseQueue) throws {
  try insertExercise(in: database)
  try insertWorkout(in: database)
  try insertWorkoutItem(in: database)
  try insertProgramRevision(in: database)
  try insertCompletion(in: database)
  try insertCompletionItem(in: database)
}

private func insertExercise(in database: DatabaseQueue) throws {
  let exercise = Exercise(
    id: BackupFixture.exerciseID,
    key: "bench",
    name: "Bench press",
    loadKind: .weight,
    currentLoadPounds: 135,
    increment: 5,
    loadLabel: "barbell",
    notes: "Pause at the chest"
  )
  try database.write { connection in
    try Exercise.insert { Exercise.Draft(exercise) }.execute(connection)
  }
}

private func insertWorkout(in database: DatabaseQueue) throws {
  let workout = Workout(id: BackupFixture.workoutID, key: "A", position: 0)
  try database.write { connection in
    try Workout.insert { Workout.Draft(workout) }.execute(connection)
  }
}

private func insertWorkoutItem(in database: DatabaseQueue) throws {
  let item = WorkoutItem(
    id: BackupFixture.workoutItemID,
    workoutID: BackupFixture.workoutID,
    exerciseID: BackupFixture.exerciseID,
    position: 0,
    prescription: "3 × 5–8",
    ramp: "10 @ 115 · 8 @ 125 · 6 @ 135"
  )
  try database.write { connection in
    try WorkoutItem.insert { WorkoutItem.Draft(item) }.execute(connection)
  }
}

private func insertProgramRevision(in database: DatabaseQueue) throws {
  let revision = ProgramRevision(
    id: BackupFixture.revisionID,
    acceptedAt: Date(timeIntervalSince1970: 1_700_000_000),
    contractText: "Fit Happens backup fixture"
  )
  try database.write { connection in
    try ProgramRevision.insert { ProgramRevision.Draft(revision) }.execute(connection)
  }
}

private func insertCompletion(in database: DatabaseQueue) throws {
  let completion = Completion(
    id: BackupFixture.completionID,
    workoutKey: "A",
    completedAt: Date(timeIntervalSince1970: 1_700_000_100),
    healthWorkoutID: BackupFixture.healthWorkoutID
  )
  try database.write { connection in
    try Completion.insert { Completion.Draft(completion) }.execute(connection)
  }
}

private func insertCompletionItem(in database: DatabaseQueue) throws {
  let item = CompletionItem(
    id: BackupFixture.completionItemID,
    completionID: BackupFixture.completionID,
    exerciseID: BackupFixture.exerciseID,
    position: 0,
    name: "Bench press",
    prescription: "3 × 5–8",
    loadKind: .weight,
    loadPounds: 135
  )
  try database.write { connection in
    try CompletionItem.insert { CompletionItem.Draft(item) }.execute(connection)
  }
}

private enum BackupFixture {
  static let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
  static let workoutID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
  static let workoutItemID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
  static let revisionID = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
  static let completionID = UUID(uuidString: "00000000-0000-0000-0000-000000000105")!
  static let completionItemID = UUID(uuidString: "00000000-0000-0000-0000-000000000106")!
  static let healthWorkoutID = UUID(uuidString: "00000000-0000-0000-0000-000000000107")!
}

private func migratedDatabase(at url: URL) throws -> DatabaseQueue {
  let database = try DatabaseQueue(path: url.path)
  try FitHappensDatabaseMigrations.makeMigrator().migrate(database)
  return database
}

private func temporaryDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("FitHappensDatabaseBackup-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}
