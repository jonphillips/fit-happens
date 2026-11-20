import CloudSyncKit
import Dependencies
import FitHappensCore
import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ICloudSection: View {
  let syncModel: ICloudSyncModel
  let automaticBackupModel: AutomaticBackupModel

  @State private var backupExport = DatabaseBackupExportModel(
    configuration: FitHappensCloudSync.databaseBackupConfiguration
  )
  @State private var backupRestore = DatabaseBackupRestoreModel(
    configuration: FitHappensCloudSync.databaseBackupConfiguration
  )
  @State private var backupFolder = BackupFolderModel()
  @State private var backupExportDocument: FitHappensBackupExportDocument?
  @State private var backupExportFilename = "FitHappens-Backup.sqlite"
  @State private var isPresentingBackupExporter = false
  @State private var isPresentingBackupImporter = false
  @State private var isConfirmingRestore = false
  @State private var isConfirmingSyncEnable = false
  @State private var isPresentingRestoreRestartCover = false

  var body: some View {
    Section("iCloud") {
      Toggle("iCloud Sync", isOn: syncBinding)
      Text(syncModel.statusText)
        .font(.caption)
        .foregroundStyle(.secondary)
      BackupActionRows(
        isExporting: backupExport.isPreparing,
        isRestoring: backupRestore.isPreparing || backupRestore.isRestoring,
        hasUndoableRestore: backupRestore.hasUndoableRestore,
        backUpNow: { Task { await prepareBackupForExport() } },
        restore: {
          Task {
            await backupFolder.resolve()
            isPresentingBackupImporter = true
          }
        },
        undo: {
          Task {
            await backupRestore.prepareUndo()
            isConfirmingRestore = backupRestore.isPrepared
          }
        }
      )
      AutomaticBackupStatusRows(model: automaticBackupModel)
    }
    .task { await syncModel.refresh() }
    .onChange(of: syncModel.isSynchronizing) { _, _ in
      Task { await syncModel.refresh() }
    }
    .fileExporter(
      isPresented: $isPresentingBackupExporter,
      document: backupExportDocument,
      contentType: .fitHappensSQLiteBackup,
      defaultFilename: backupExportFilename,
      onCompletion: backupExportCompleted,
      onCancellation: clearPreparedBackup
    )
    .sheet(isPresented: $isPresentingBackupImporter) {
      BackupFileImporter(startingDirectory: backupFolder.directoryURL, onPick: backupRestoreSelected)
        .ignoresSafeArea()
    }
    .alert("Restore This Backup?", isPresented: $isConfirmingRestore) {
      Button("Restore", role: .destructive) {
        Task {
          if await backupRestore.restorePreparedBackup() {
            isPresentingRestoreRestartCover = true
          }
        }
      }
      Button("Cancel", role: .cancel) { backupRestore.discardPreparedRestore() }
    } message: {
      Text(restoreConfirmation)
    }
    .confirmationDialog(
      "Turn On iCloud Sync?",
      isPresented: $isConfirmingSyncEnable,
      titleVisibility: .visible
    ) {
      Button("Turn On Sync") { Task { await syncModel.enabledChanged(true) } }
      Button("Keep Sync Off", role: .cancel) {}
    } message: {
      Text([
        "This device was restored from a backup. Turning sync on uploads the restored program and history to iCloud, "
          + "replacing the current copy.",
        "Workouts deleted since the backup will return. Keep sync off if you only wanted to restore this device."
      ].joined(separator: "\n\n"))
    }
    .fullScreenCover(isPresented: $isPresentingRestoreRestartCover) {
      ContentUnavailableView(
        "Restart Fit Happens",
        systemImage: "arrow.clockwise",
        description: Text([
          "The backup is restored. Close and reopen Fit Happens to use it.",
          "You can undo this restore from Program after reopening. iCloud sync stays off until you turn it back on."
        ].joined(separator: " "))
      )
      .interactiveDismissDisabled()
    }
    .alert("Could Not Export Backup", isPresented: backupExportErrorPresented) {
      Button("OK") { backupExport.dismissError() }
    } message: {
      Text(backupExport.errorMessage ?? "")
    }
    .alert("Could Not Restore Backup", isPresented: backupRestoreErrorPresented) {
      Button("OK") { backupRestore.dismissError() }
    } message: {
      Text(backupRestore.errorMessage ?? "")
    }
  }

  private var syncBinding: Binding<Bool> {
    Binding(
      get: { syncModel.isEnabled },
      set: { enabled in
        if enabled && syncModel.isDisabledByRestore {
          isConfirmingSyncEnable = true
        } else {
          Task { await syncModel.enabledChanged(enabled) }
        }
      }
    )
  }

  private var restoreConfirmation: String {
    [
      "This replaces the program and history on this device. Fit Happens saves an automatic undo backup first.",
      "iCloud sync stays off until you turn it back on. When you do, this restored copy replaces the iCloud data,",
      "and workouts deleted since the backup return."
    ].joined(separator: " ")
  }

  private var backupExportErrorPresented: Binding<Bool> {
    Binding(
      get: { backupExport.errorMessage != nil },
      set: { newValue in
        if !newValue {
          backupExport.dismissError()
        }
      }
    )
  }

  private var backupRestoreErrorPresented: Binding<Bool> {
    Binding(
      get: { backupRestore.errorMessage != nil },
      set: { newValue in
        if !newValue {
          backupRestore.dismissError()
        }
      }
    )
  }

  private func prepareBackupForExport() async {
    guard let snapshot = await backupExport.prepareBackupForExport() else {
      return
    }
    backupExportDocument = FitHappensBackupExportDocument(snapshot: snapshot)
    backupExportFilename = backupExport.defaultFilename()
    isPresentingBackupExporter = true
  }

  private func backupExportCompleted(_ result: Result<URL, any Error>) {
    if case let .failure(error) = result { backupExport.recordExportFailure(error) }
    clearPreparedBackup()
  }

  private func clearPreparedBackup() {
    if let backupExportDocument { backupExport.discard(backupExportDocument.snapshot) }
    backupExportDocument = nil
  }

  private func backupRestoreSelected(_ result: Result<URL, any Error>) {
    switch result {
    case let .success(url):
      Task {
        await backupRestore.prepareRestore(from: url)
        isConfirmingRestore = backupRestore.isPrepared
      }
    case let .failure(error):
      backupRestore.recordImportFailure(error)
    }
  }
}

private struct BackupActionRows: View {
  var isExporting: Bool
  var isRestoring: Bool
  var hasUndoableRestore: Bool
  var backUpNow: () -> Void
  var restore: () -> Void
  var undo: () -> Void

  var body: some View {
    Group {
      Button(action: backUpNow) {
        HStack {
          Label("Back Up Now", systemImage: "externaldrive.badge.checkmark")
          if isExporting { Spacer(); ProgressView() }
        }
      }
      .disabled(isExporting)

      Button(action: restore) {
        HStack {
          Label("Restore…", systemImage: "externaldrive.badge.plus")
          if isRestoring { Spacer(); ProgressView() }
        }
      }
      .disabled(isRestoring)

      if hasUndoableRestore {
        Button(action: undo) {
          Label("Undo Last Restore", systemImage: "arrow.uturn.backward")
        }
        .disabled(isRestoring)
      }
    }
  }
}

private struct AutomaticBackupStatusRows: View {
  let model: AutomaticBackupModel

  var body: some View {
    Group {
      if model.isRunning {
        ProgressView("Automatic backup in progress…")
      } else {
        Text(statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let warning = model.shrinkWarning {
        Text(
          "Completion history shrank from \(warning.previousCount) to \(warning.currentCount). "
            + "Keeping \(warning.previousFilename)."
        )
        .font(.caption)
        .foregroundStyle(.orange)
        Button("Dismiss backup warning") { Task { await model.dismissShrinkWarning() } }
      }
    }
  }

  private var statusText: String {
    switch model.status {
    case .neverRun:
      return "No automatic backup yet."
    case let .lastBackup(date, bytes):
      let dateText = date.formatted(date: .abbreviated, time: .shortened)
      let sizeText = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
      return "Last automatic backup: \(dateText) · \(sizeText)"
    case .notRunning(.turnedOff):
      return "Automatic backup is off."
    case .notRunning(.restoreInProgress):
      return "Automatic backup is paused during restore."
    case .notRunning(.participantDevice):
      return "Automatic backup is unavailable on a participant device."
    case .notRunning(.iCloudDriveUnavailable):
      return "Automatic backup is waiting for iCloud Drive."
    case let .failed(message):
      return "Automatic backup failed: \(message)"
    }
  }
}

@MainActor
@Observable
private final class BackupFolderModel {
  @ObservationIgnored @Dependency(\.automaticBackupClient) private var client
  private(set) var directoryURL: URL?

  func resolve() async {
    do {
      guard let container = try await client.containerURL(
        FitHappensCloudSync.configuration.containerIdentifier
      ) else {
        directoryURL = nil
        return
      }
      let folder = container.appendingPathComponent("Documents/Backups", isDirectory: true)
      try await client.createDirectory(folder)
      directoryURL = folder
    } catch {
      directoryURL = nil
    }
  }
}

private final class FitHappensBackupExportDocument: WritableDocument {
  typealias Writer = FitHappensBackupExportDocumentWriter
  static let writableContentTypes: [UTType] = [.fitHappensSQLiteBackup]

  let snapshot: DatabaseBackup.Snapshot

  init(snapshot: DatabaseBackup.Snapshot) {
    self.snapshot = snapshot
  }

  func writer(configuration: sending DocumentWriteConfiguration) -> sending FitHappensBackupExportDocumentWriter {
    FitHappensBackupExportDocumentWriter()
  }

  func snapshot(contentType: UTType) async throws -> sending URL { snapshot.fileURL }
}

private struct FitHappensBackupExportDocumentWriter: DocumentWriter {
  typealias Snapshot = URL

  func write(
    snapshot: sending URL,
    to destination: sending URL,
    previous: sending URL?,
    progress: consuming Subprogress
  ) async throws {
    try FileManager.default.copyItem(at: snapshot, to: destination)
  }
}

private struct BackupFileImporter: UIViewControllerRepresentable {
  var startingDirectory: URL?
  var onPick: (Result<URL, any Error>) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [.fitHappensSQLiteBackup, .data],
      asCopy: false
    )
    picker.directoryURL = startingDirectory
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

  @MainActor
  final class Coordinator: NSObject, UIDocumentPickerDelegate {
    private let onPick: (Result<URL, any Error>) -> Void

    init(onPick: @escaping (Result<URL, any Error>) -> Void) {
      self.onPick = onPick
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
      guard let url = urls.first else {
        return
      }
      onPick(.success(url))
    }
  }
}

private extension UTType {
  static let fitHappensSQLiteBackup = UTType(
    exportedAs: "com.jonphillips.fithappens.database-backup",
    conformingTo: .data
  )
}
