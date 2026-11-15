import Foundation

public enum ProgramContractRules {
  public static let instructions = """
  Return a complete program as plain JSON preceded by the line FH-PROGRAM-1. Use this shape:
  {
    "workouts": [{
      "key": "A",
      "items": [{
        "key": "flat-bench-press",
        "name": "Flat barbell bench press",
        "prescription": "3 × 5–8",
        "loadKind": "weight",
        "startingWeight": 0,
        "increment": null,
        "loadLabel": null,
        "notes": null
      }]
    }]
  }
  Keep units in pounds. Reuse a stable readable exercise key for the same lift; a new name is a rename.
  New weighted exercises need a startingWeight. Do not include startingWeight for existing keys; the app
  keeps their working weights. Use loadKind bodyweight for exercises without a working weight. Missing
  exercise keys retire those exercises. Include every workout and item in order.
  """
}
