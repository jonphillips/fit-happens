# Device passes

## Gates

- **testflight-renewal:** On the mini, run `~/code/jon-platform/scripts/testflight-renew install --to HANDLE --days 14 ~/code/fit-happens`, then `notify-test --to HANDLE`; confirm the message alerts Jon’s phone. Reinstall with `--days 90`, run `launchctl kickstart gui/$(id -u)/com.jonphillips.testflight-renew`, and confirm Fit Happens releases and reports by iMessage. Reinstall with the default 14-day threshold afterwards. ([brief](efforts/archive/testflight-renewal.md))
