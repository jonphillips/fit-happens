# Chat access setup

Fit Happens exposes its program, workout history, and Apple Health activity to a chat-host Mac through
the `fithappens-mcp` helper. The app writes the export only while **Program → Chat Access** is on.

## Fit Happens values

- Helper package: `FitHappensMCP/`
- Installed executable: `~/.local/bin/fithappens-mcp`
- Tunnel profile: `fithappens`
- Health port: `8084`
- iCloud Drive container: `iCloud.com.jonphillips.fithappens`
- Read tools: `get_program`, `get_history`, `get_activity`

## Install and refresh

From this repository, install or reinstall the helper with jon-platform's `scripts/install-mcp-helper`.
The general tunnel creation, profile, and plugin recipe is in jon-platform's `docs/ios/mcp-access.md`;
use the values above when that recipe asks for app-specific values.

On iPhone, open **Program**, turn on **Chat Access**, then tap **Refresh** after changing the program
or when a chat reports an old export. The export updates in the background when the app enters the
background, with a 15-minute throttle. If the chat-host Mac was asleep, wake it and retry after iCloud
Drive finishes downloading the export. With no export available, open Fit Happens and tap **Refresh**.

The tools only read the export. A program proposal still needs review and **Apply** in Fit Happens.
