import Foundation

public enum ProgramContractRules {
  public static let instructions = """
  Return the complete program as JSON. Prefix it with FH-PROGRAM: v1 when possible. One fenced JSON
  block is okay; short prose around it is okay. Use this shape:
  {
    "workouts": [{
      "key": "A",
      "items": [{
        "key": "flat-bench-press",
        "name": "Flat barbell bench press",
        "prescription": "3 × 5–8",
        "loadKind": "weight",
        "startingWeight": 135,
        "loadLabel": null,
        "notes": null
      }]
    }]
  }
  Keep units in pounds. Reuse a stable readable exercise key for the same lift; a new name is a rename.
  Omit increment when the exercise uses the default 5 lb step; include increment only for a different step.
  New weighted exercises need startingWeight. A startingWeight on an existing or restored key is ignored;
  the app keeps its working weight.
  A change from bodyweight to weight needs a startingWeight; a change from weight to bodyweight omits it.
  Missing exercise keys retire the exercise. Include all workouts and items in order.
  """
}
