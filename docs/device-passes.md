# Device passes

## Gates

- **testflight-renewal:** On the mini, run `~/code/jon-platform/scripts/testflight-renew install --to HANDLE --days 14 ~/code/fit-happens`, then `notify-test --to HANDLE`; confirm the message alerts Jon’s phone. Reinstall with `--days 90`, run `launchctl kickstart gui/$(id -u)/com.jonphillips.testflight-renew`, and confirm Fit Happens releases and reports by iMessage. Reinstall with the default 14-day threshold afterwards. ([brief](efforts/archive/testflight-renewal.md))
- **health-access:** On Jon’s iPhone with the TestFlight build: on a fresh install, confirm the Health prompt appears. If it does not, note whether Next Workout shows Connect to Health or the error. Tap Connect to Health and allow access; confirm Activity shows walks and body weight and Fit Happens appears in Settings → Health → Data Access & Devices. On an install that already has access, confirm no prompt or Connect to Health row appears. ([brief](efforts/archive/health-access.md))
