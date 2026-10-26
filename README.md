# T3 Pulse

A tiny native macOS menu bar companion for T3 Code. See which agents are working, waiting for you, or finished without switching windows.

About 400 lines of Swift, using AppKit, SwiftUI, and the system SQLite library. No third-party packages, API keys, or network requests. The interface is currently in Turkish.

[Türkçe](README.tr.md)

## What it shows

| Icon | State |
| --- | --- |
| Animated blue dotted ring | Working |
| Orange pause | Waiting for input or approval |
| Green check | Completed |
| Red exclamation | Failed |
| Gray circle | Idle or T3 Code is closed |

The menu bar shows counts by state. Click it for job titles, agent models, elapsed times, and native subagents across your local projects. Status refreshes every two seconds. Recent results cover the last 24 hours; archived threads and settled, inactive threads are excluded. A completion sound is optional and off by default. No Dock icon or automatic launch-at-login setup.

“Completed” means the latest agent run finished, rather than a guarantee that every project requirement is done.

## Build and run

Requires macOS 14 or newer and Xcode Command Line Tools (`xcode-select --install`). Build on Apple Silicon or Intel for the current machine's architecture.

```sh
git clone https://github.com/se7enbyte/t3-pulse.git
cd t3-pulse
zsh build.sh
open 'build/T3 Pulse.app'
```

Optional installation:

```sh
mkdir -p "$HOME/Applications"
ditto 'build/T3 Pulse.app' "$HOME/Applications/T3 Pulse.app"
open "$HOME/Applications/T3 Pulse.app"
```

Quit any running copy before starting another one. Use the power button in the panel to quit. To uninstall, quit and remove the app bundle.

## Data and compatibility

This is an independent companion app, not a T3 Code source modification or official integration. It opens `~/.t3/userdata/statev2.sqlite` with `SQLITE_OPEN_READONLY` and reads local thread/run metadata. It does not read conversation message contents or credentials, and does not change T3 Code's data.

Tested against the local database schema shipped with **T3 Code 0.1.2**. This is an internal schema, so a future T3 Code update may require a reader update. Missing or incompatible databases show an error. When the T3 Code desktop app is closed, the panel labels results as last-known state; interrupted work may remain recorded as running until T3 updates it.

For a custom data directory, launch the executable directly so it receives the environment variable:

```sh
T3CODE_HOME="/path/to/.t3" 'build/T3 Pulse.app/Contents/MacOS/T3Pulse'
```

## Check the reader

Python 3 is needed only for the fixture tests:

```sh
python3 tests/check_store.py
```

These exercise the compiled Swift reader against a temporary database: latest-run selection, completion transitions, approval/input states, nonblocking questions, archived threads, and subagent deduplication. They do not touch your live T3 database.

To inspect your real local statuses once:

```sh
'build/T3 Pulse.app/Contents/MacOS/T3Pulse' --check
```

This diagnostic prints local job titles to your terminal; review its output before sharing it.

## License

[MIT](LICENSE)
