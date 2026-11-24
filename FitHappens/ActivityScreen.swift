import FitHappensCore
import SwiftUI

struct ActivityScreen: View {
  @State private var model = ActivityScreenModel()
  @State private var path: [ActivityDestination] = []
  @Environment(CompletionCorrectionsModel.self) private var correctionsModel
  var isActive: Bool
  @Environment(\.calendar) private var calendar

  var body: some View {
    NavigationStack(path: $path) {
      Group {
        if model.hasLoaded {
          activity
        } else {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .navigationTitle("Activity")
      .navigationDestination(for: ActivityDestination.self) { destination in
        switch destination {
        case .history:
          CompletionHistoryScreen(model: correctionsModel, path: $path)
        case let .correctDate(completionID):
          CompletionDateCorrectionDestination(model: correctionsModel, completionID: completionID)
        }
      }
      .task {
        if isActive {
          await model.screenAppeared(calendar: calendar)
        }
      }
      .onChange(of: isActive) { _, active in
        guard active else {
          return
        }
        Task { await model.screenAppeared(calendar: calendar) }
      }
    }
  }

  private var activity: some View {
    List {
      HealthAccessSection(access: model.healthReadAccess) {
        Task { await model.connectToHealthButtonTapped(calendar: calendar) }
      }
      calendarSection
      bodyWeightSection
      progressionSection
      Section {
        NavigationLink(value: ActivityDestination.history) {
          Label("Fix a workout", systemImage: "calendar.badge.exclamationmark")
        }
      }
    }
  }

  private var calendarSection: some View {
    Section("Last four weeks") {
      calendarGrid
      if model.healthReadAccess == .ready, !model.hasHealthActivity {
        Text("Nothing from Health yet.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("Check Settings → Health → Data Access & Devices → Fit Happens if you expected activity.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      calendarKey
    }
  }

  private var bodyWeightSection: some View {
    Section("Body weight") {
      if let bodyMass = model.latestBodyMass {
        LabeledContent {
          Text("\(bodyMass.pounds.formatted(.number.precision(.fractionLength(0...1)))) lb")
        } label: {
          Text(bodyMass.date.formatted(date: .abbreviated, time: .omitted))
        }
      } else if model.healthReadAccess == .ready {
        Text("Nothing from Health yet.")
          .foregroundStyle(.secondary)
        Text("Check Settings → Health → Data Access & Devices → Fit Happens if you expected a reading.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var progressionSection: some View {
    Section("Progression") {
      if model.orderedWeightedExercises.isEmpty {
        Text("No weighted exercises in the current program.")
          .foregroundStyle(.secondary)
      } else {
        Picker("Exercise", selection: Binding(model.$selectedExerciseKey)) {
          ForEach(model.orderedWeightedExercises, id: \.key) { exercise in
            Text(exercise.name).tag(Optional(exercise.key))
          }
        }
        if let progression = model.progression(calendar: calendar) {
          Text(progressionText(progression))
            .accessibilityIdentifier("activity.progression")
        }
      }
    }
  }

  private var calendarGrid: some View {
    let days = model.calendarDays(calendar: calendar)
    let symbols = calendar.veryShortStandaloneWeekdaySymbols
    let orderedSymbols = Array(symbols[(calendar.firstWeekday - 1)...]) + Array(symbols[..<(calendar.firstWeekday - 1)])
    let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    return LazyVGrid(columns: columns, spacing: 8) {
      ForEach(orderedSymbols, id: \.self) { symbol in
        Text(symbol)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
          .accessibilityHidden(true)
      }
      ForEach(days) { day in
        CalendarDayCell(day: day)
      }
    }
    .padding(.vertical, 4)
  }

  private var calendarKey: some View {
    HStack(spacing: 12) {
      keyItem("dumbbell.fill", label: "Strength")
      keyItem("figure.walk", label: "Walk")
      Label {
        Text("Both")
      } icon: {
        HStack(spacing: 2) {
          Image(systemName: "dumbbell.fill")
          Image(systemName: "figure.walk")
        }
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.top, 8)
  }

  private func keyItem(_ symbol: String, label: String) -> some View {
    Label(label, systemImage: symbol)
  }

  private func progressionText(_ progression: ExerciseProgression) -> String {
    let current = progression.currentPounds.formatted(.number.precision(.fractionLength(0...1)))
    guard let previous = progression.previousPounds, let previousDate = progression.previousDate else {
      return "\(progression.exerciseName) \(current) lb"
    }
    let change = (progression.currentPounds - previous).formatted(
      .number.sign(strategy: .always()).precision(.fractionLength(0...1))
    )
    let date = previousDate.formatted(.dateTime.month(.abbreviated).day())
    return "\(progression.exerciseName) \(current) lb · \(change) lb since \(date)"
  }
}

private struct CalendarDayCell: View {
  var day: ActivityDay
  @ScaledMetric(relativeTo: .caption2) private var markerSize = 8

  var body: some View {
    VStack(spacing: 2) {
      Text(day.date.formatted(.dateTime.day()))
        .font(.caption2)
        .foregroundStyle(day.isFuture ? .tertiary : .primary)
      if day.isFuture {
        Color.clear.frame(height: markerSize)
      } else {
        HStack(spacing: 1) {
          if day.training == .strength || day.training == .both {
            Image(systemName: "dumbbell.fill")
          }
          if day.training == .walking || day.training == .both {
            Image(systemName: "figure.walk")
          }
          if day.training == .neither {
            Circle().fill(.quaternary).frame(width: markerSize * 0.375, height: markerSize * 0.375)
          }
        }
        .font(.system(size: markerSize, weight: .medium))
        if let miles = day.walkingMiles {
          Text("\(miles.formatted(.number.precision(.fractionLength(1)))) mi")
            .font(.caption2.weight(.medium))
            .lineLimit(1)
        } else {
          Color.clear.frame(height: markerSize)
        }
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityDescription)
  }

  private var accessibilityDescription: String {
    let date = day.date.formatted(date: .complete, time: .omitted)
    if day.isFuture {
      return "\(date), future date"
    }
    let activity: String = switch day.training {
    case .neither: "No recorded activity"
    case .strength: "Strength workout"
    case .walking: "Walk"
    case .both: "Strength workout and walk"
    }
    guard let miles = day.walkingMiles else {
      return "\(date), \(activity)"
    }
    return "\(date), \(activity), \(miles.formatted(.number.precision(.fractionLength(1)))) miles"
  }
}
