import CloudSyncKit
import Dependencies
import Foundation
import SQLiteData

public enum FitHappensCloudSync {
  public static let configuration = CloudSyncConfiguration(
    containerIdentifier: "iCloud.com.jonphillips.fithappens",
    enabledDefaultsKey: "FitHappensCloudKitSyncEnabled",
    enabledEnvironmentKey: "FIT_HAPPENS_CLOUDKIT_SYNC_ENABLED",
    enabledLaunchArgument: "-FitHappensCloudKitSyncEnabled",
    restoreRequiresManualEnablementDefaultsKey: "FitHappensCloudKitSyncRestoreRequiresManualEnablement"
  )

  public static let databaseBackupConfiguration = DatabaseBackupConfiguration(
    displayName: "Fit Happens",
    backupFilenamePrefix: "FitHappens-Backup-",
    preRestoreFilenamePrefix: "FitHappens-PreRestore-",
    restoreStagingFilenamePrefix: "FitHappens-Restore-",
    identifyingTableNames: [
      "exercises", "workouts", "workoutItems", "programRevisions", "completions", "completionItems"
    ],
    declaredSchemaVersion: FitHappensDatabaseMigrations.schemaVersion,
    lastPreRestoreDefaultsKey: "FitHappensDatabaseBackupLastPreRestorePath",
    cloudSync: configuration,
    liveStoreURL: { try FitHappensDatabaseStorage.liveDatabaseURL() },
    migrate: { try FitHappensDatabaseMigrations.migrateRestoreCandidate(at: $0) }
  )

  public static let automaticBackupConfiguration = AutomaticBackupConfiguration(
    filenamePrefix: "FitHappens-Auto-",
    libraryCountTableName: "completions",
    installIDDefaultsKey: "FitHappensAutomaticBackupInstallID",
    enabledDefaultsKey: "FitHappensAutomaticBackupEnabled"
  )

  public static func isManuallyEnabled() -> Bool {
    CloudSync.isManuallyEnabled(configuration: configuration)
  }

  public static func setManuallyEnabled(_ enabled: Bool) {
    CloudSync.setManuallyEnabled(enabled, configuration: configuration)
  }

  public static func isDisabledByRestore() -> Bool {
    CloudSync.isDisabledByRestore(configuration: configuration)
  }

  public static func persistManualEnablementFromLaunchEnvironment() {
    CloudSync.persistManualEnablementFromLaunchEnvironment(configuration: configuration)
  }

  public static func startIfManuallyEnabled() async -> CloudSync.StartResult {
    @Dependency(\.defaultSyncEngine) var engine
    return await CloudSync.startIfManuallyEnabled(
      configuration: configuration,
      startSyncEngine: { try await engine.start() }
    )
  }

  public static func makeSyncEngine(
    for database: any DatabaseWriter, startImmediately: Bool
  ) throws -> SyncEngine {
    try SyncEngine(
      for: database,
      tables: Exercise.self, Workout.self, WorkoutItem.self,
      ProgramRevision.self, Completion.self, CompletionItem.self,
      containerIdentifier: configuration.containerIdentifier,
      startImmediately: startImmediately
    )
  }
}

public enum FitHappensDatabaseMigrations {
  public static let schemaVersion = 2

  public static func makeMigrator() -> DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("Create Fit Happens core schema (ADR-0002, ADR-0003)") { database in
      try createProgramTables(in: database)
      try createHistoryTables(in: database)
    }
    migrator.registerMigration("Add workout item ramps (ADR-0002)") { database in
      try #sql("ALTER TABLE \"workoutItems\" ADD COLUMN \"ramp\" TEXT").execute(database)
    }
    return migrator
  }

  public static func migrateRestoreCandidate(at databaseURL: URL) throws {
    try withDependencies {
      $0.context = .live
    } operation: {
      var configuration = Configuration()
      configuration.prepareDatabase { database in
        try database.attachMetadatabase(
          containerIdentifier: FitHappensCloudSync.configuration.containerIdentifier
        )
      }
      let database = try SQLiteData.defaultDatabase(
        path: databaseURL.absoluteString,
        configuration: configuration
      )
      do {
        try makeMigrator().migrate(database)
      } catch {
        try? database.close()
        throw error
      }
      try database.close()
    }
  }

  private static func createProgramTables(in database: Database) throws {
    try #sql(
      """
      CREATE TABLE "exercises" (
        "id" TEXT PRIMARY KEY NOT NULL, "key" TEXT NOT NULL, "name" TEXT NOT NULL,
        "loadKind" TEXT NOT NULL, "currentLoadPounds" REAL, "increment" REAL,
        "loadLabel" TEXT, "notes" TEXT, "isRetired" INTEGER NOT NULL
      ) STRICT
      """
    ).execute(database)
    try #sql(
      """
      CREATE TABLE "workouts" (
        "id" TEXT PRIMARY KEY NOT NULL, "key" TEXT NOT NULL, "position" INTEGER NOT NULL
      ) STRICT
      """
    ).execute(database)
    try #sql(
      """
      CREATE TABLE "workoutItems" (
        "id" TEXT PRIMARY KEY NOT NULL,
        "workoutID" TEXT NOT NULL REFERENCES "workouts"("id") ON DELETE CASCADE,
        "exerciseID" TEXT NOT NULL REFERENCES "exercises"("id") ON DELETE CASCADE,
        "position" INTEGER NOT NULL, "prescription" TEXT NOT NULL
      ) STRICT
      """
    ).execute(database)
    try #sql("CREATE INDEX \"index_workoutItems_on_workoutID\" ON \"workoutItems\"(\"workoutID\")")
      .execute(database)
    try #sql("CREATE INDEX \"index_workoutItems_on_exerciseID\" ON \"workoutItems\"(\"exerciseID\")")
      .execute(database)
  }

  private static func createHistoryTables(in database: Database) throws {
    try #sql(
      """
      CREATE TABLE "programRevisions" (
        "id" TEXT PRIMARY KEY NOT NULL, "acceptedAt" TEXT NOT NULL, "contractText" TEXT NOT NULL
      ) STRICT
      """
    ).execute(database)
    try #sql(
      """
      CREATE TABLE "completions" (
        "id" TEXT PRIMARY KEY NOT NULL, "workoutKey" TEXT NOT NULL,
        "completedAt" TEXT NOT NULL, "healthWorkoutID" TEXT
      ) STRICT
      """
    ).execute(database)
    try #sql(
      """
      CREATE TABLE "completionItems" (
        "id" TEXT PRIMARY KEY NOT NULL,
        "completionID" TEXT NOT NULL REFERENCES "completions"("id") ON DELETE CASCADE,
        "exerciseID" TEXT NOT NULL, "position" INTEGER NOT NULL, "name" TEXT NOT NULL,
        "prescription" TEXT NOT NULL, "loadKind" TEXT NOT NULL, "loadPounds" REAL
      ) STRICT
      """
    ).execute(database)
    try #sql(
      "CREATE INDEX \"index_completionItems_on_completionID\" ON \"completionItems\"(\"completionID\")"
    ).execute(database)
  }
}

public enum FitHappensDatabaseStorage {
  public static func liveDatabaseURL(fileManager: FileManager = .default) throws -> URL {
    let applicationSupportDirectory = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return applicationSupportDirectory.appendingPathComponent("SQLiteData.db", isDirectory: false)
  }
}

extension DependencyValues {
  public mutating func bootstrapDatabase() throws {
    var configuration = Configuration()
    configuration.prepareDatabase { database in
      try database.attachMetadatabase(
        containerIdentifier: FitHappensCloudSync.configuration.containerIdentifier
      )
    }
    let database = try SQLiteData.defaultDatabase(configuration: configuration)
    try FitHappensDatabaseMigrations.makeMigrator().migrate(database)
    defaultDatabase = database
    defaultSyncEngine = try FitHappensCloudSync.makeSyncEngine(for: database, startImmediately: false)
  }
}
