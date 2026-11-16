# Product — Fit Happens

*Status: **Live** · written 2026-11-15 from a ChatGPT brief, reworked against the jon-platform house stack
in conversation with Jon. Decisions: [decisions/](decisions/).*

Summary: A persistent workout prescription with one-tap completion, plus a glanceable view of what
Jon has been doing physically. Success is about one interaction per workout, plus the occasional
weight change, and an app that is essentially finished once built.

## Who and why

One user (Jon), one iPhone, following a fixed strength program that alternates Workout A and
Workout B, usually every other day. He doesn't want to log sets or reps, or touch the phone during
a workout. Strong and Hevy are logging products; this is not.

## The two experiences

### 1. Next Workout (the launch screen)

- Which workout is next (A, B, …) and when the previous one was done.
- The exercises in order: name, prescription as written ("3 × 5–8"), and the working weight.
- Weight changes by stepper, in each exercise's own increment. Bodyweight exercises show no weight.
- A prominent **Complete Workout**. It records a snapshot and advances the rotation.
- Corrections: undo the last completion, and change a completion's date ("I did it yesterday").
- When Apple Health has a strength workout that ended recently and isn't linked yet, the app offers
  to mark the next workout done with that workout's time (ADR-0004). This makes the Watch session Jon
  already starts the usual path to completion.

### 2. Activity (read-only)

"What have I been doing physically over the last few weeks?" with no extra logging:

- A four-week calendar: strength days, recorded-walk days, both, neither.
- The latest body weight.
- One strength progression line (e.g. bench today vs. 90 days ago).

No streaks, goals, badges, or exhortations. Totals beyond what the calendar shows are deliberately
left out until they're missed.

## How the program changes

Jon discusses the program with ChatGPT. The result comes back as a **program contract** (ADR-0002):
pasted into the app, or staged by ChatGPT through the chat-access MCP tunnel. The app shows what
changes (added, removed, renamed, new prescriptions, which weights carry over), and one tap applies
it. The first program arrives the same way: ChatGPT converts the existing Markdown program into the
contract. After that the app, not the Markdown, is the source of truth.

## The scale

A Bluetooth scale in the house is read by a headless listener on the always-on Mac mini. Readings
reach the iPhone app, which writes Jon's into Apple Health as body mass (ADR-0005). Other people use
the scale too, so readings are matched to Jon by weight band, and borderline ones ask.

## Phases

1. **M1 — Core loop.** Program as data (paste import), Next Workout, completion, corrections, sync.
   Useful on its own, without Health.
2. **Health.** The Activity view and Watch-workout linking (ADR-0004).
3. **Chat access.** Read tools and `propose_program` over the MCP tunnel (ADR-0002, jon-platform ADR-0007).
4. **Scale.** The Mac listener and body-mass writes (ADR-0005). Waits on buying a suitable scale.

Health comes before chat access (Jon, 2026-11-16): it pays off every day.

## Non-goals

Don't build: set-by-set logging; an in-app program designer; an exercise database, videos, or
search; timers or rest periods; a Watch app (revisit only if starting the workout on the Watch
becomes a nuisance, see ADR-0004); social or gamification; AI inside the app or automated progression
advice; goals, reminders, or notifications; an analytics engine; any server or proxy; a custom store
of Health data; writing strength workouts to Health.

A feature gets in only if its use clearly exceeds its interface and maintenance cost.
