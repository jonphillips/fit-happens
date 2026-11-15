# ADR-0005 — Scale readings: a Mac listener, the iCloud Drive inbox, and Jon's weight band

*Status: **proposed** — 2026-11-15, ratified by Jon merging the plan PR that adds it. Seam: jon-platform
`SEAM-LEDGER.md` § Headless Mac listener on the always-on host (Vinyl Fever's listening poller).*

Summary: A small headless Mac app on the always-on mini listens for a Bluetooth scale and drops one
file per reading into the app's iCloud Drive container. The iPhone app picks them up, decides by
weight band whether each is Jon's, and writes his into Health as body mass. Nothing is stored in
the app's database.

## Context

Jon is buying a Bluetooth scale and wants the M6 mini (arriving per jon-platform `always-on-mac.md`)
to receive readings automatically. Other people will use the scale (2026-11-15). As far as we know,
a Mac can't write into the iPhone's Health store, so readings have to pass through the phone.

## Decision

### D1 — Which scale (decides the effort)

Buy a scale that either implements the standard Bluetooth Weight Scale Service (0x181D, Weight
Measurement 0x2A9D) or broadcasts readings unencrypted in its advertisements, so the mini can listen
without pairing and without blocking the vendor's own app. Avoid Wi-Fi-only scales with a vendor
cloud, and closed or encrypted protocols. Weight only; body-composition figures depend on vendor
formulas and are out. Check Bluetooth range from the scale's spot to the mini before committing.

### D2 — The listener

A separate headless macOS app bundle in this repo, built from the Core package, with
`NSBluetoothAlwaysUsageDescription`. It starts from a LaunchAgent embedded in its bundle (Vinyl
Fever's `VinylFeverListeningPoller` pattern) and stays running (`KeepAlive`), not on an interval,
since readings come whenever someone steps on. It holds the Bluetooth grant, which is why it's an app
bundle and not a bare helper.

### D3 — Transport

One small file per reading, with a fresh UUID, timestamp, and weight, written into the app's iCloud
Drive container through ChatAccessKit's helper-side folder and `HandoffInbox`, as its own item kind.
The listener runs no sync engine. The iPhone app's inbox watcher processes reading files
automatically: readings are facts, not proposals, so they skip review. Processed files move to
`Processed/` and follow the kit's retention. Readings reach Health the next time the app runs; each
keeps its own timestamp, so history is still right.

### D4 — Whose reading

Attribution uses a band around Jon's **last confirmed** weight, so it moves with him:

- Inside the inner band: Jon's. Written to Health automatically.
- Between the inner and outer band: listed under "Is this you?" in the app. Yes writes it; No
  discards it.
- Outside the outer band: not Jon's. Never written, never shown.
- No confirmed weight yet: every reading asks.

The band widths are open (a starting point: ±3 lb inner, ±8 lb outer). Other people's weights are
never written to Health and are kept only as the raw file until retention removes it.

### D5 — Writing to Health

Each sample is written with Health's sync identifier set to the reading's UUID (version 1), so a
retry or a second device can't duplicate it. The Activity view then reads body mass from Health like
any other source (ADR-0004).

## Open

- Whether macOS 27 can write to the user's Health store. If it can, the phone hop could go, but D3
  still works either way.
- Which scale. This ADR's listener slice isn't planned until one is chosen against D1.
