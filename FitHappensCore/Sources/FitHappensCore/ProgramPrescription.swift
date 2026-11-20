import Foundation

/// The single place that turns a stored prescription or ramp into display text.
public enum ProgramPrescriptionResolver {
  public static func resolve(prescription: String, ramp: [RampStep]?, workingWeight: Double?) -> String {
    guard let ramp, let workingWeight else {
      return prescription
    }
    return ramp.map { step in
      let pounds = max(0, workingWeight + step.offset)
      return "\(step.reps) @ \(pounds.formatted(.number.precision(.fractionLength(0...2))))"
    }.joined(separator: " · ")
  }

  public static func relative(ramp: [RampStep]) -> String {
    ramp.map { step in
      let offset = step.offset == 0
        ? "top"
        : "−\(abs(step.offset).formatted(.number.precision(.fractionLength(0...2))))"
      return "\(step.reps) @ \(offset)"
    }.joined(separator: " · ")
  }
}
