# ToonRepeater

ToonRepeater lets one keyboard and mouse drive up to four Toontown Rewritten windows on macOS. It has
multi-toon keyboard control, a mirror mode, a click repeater for battles, and Quickstart, which logs in four
saved accounts and arranges their windows. It runs natively on Apple Silicon and Intel, has no third-party
dependencies, and builds with SwiftPM.

ToonRepeater is an independent project. It isn't affiliated with or endorsed by Toontown Rewritten or Disney.
Check Toontown Rewritten's current rules on third-party tools before you use it.

## Build & run

```sh
./build.sh                 # -> build/ToonRepeater.app
open build/ToonRepeater.app
swift test                 # key-routing and click-mapping tests
```

Requires macOS 11 or later and Xcode (or the Command Line Tools) to build.

On first launch, grant **Accessibility** permission (System Settings › Privacy & Security › Accessibility).
macOS needs it before the app can send keys and clicks to other apps.

**Signing:** `build.sh` signs with the code-signing certificate named by `SIGN_IDENTITY` (set it in the
environment, e.g. `SIGN_IDENTITY="My Cert" ./build.sh`) if your keychain has it, which keeps the
Accessibility permission across rebuilds. Otherwise it signs ad-hoc, which works, but you have to re-grant
Accessibility after every rebuild.

**Downloading a release:** release builds aren't notarized by Apple, so macOS blocks them on first open.
Right-click ToonRepeater.app, choose **Open**, then **Open** again (on newer macOS: System Settings ›
Privacy & Security › **Open Anyway**).

## How to use

1. Open up to four game windows, or use Quickstart.
2. Link each window to a slot, either with **Controller › Link Open Game Windows** (⌘L), which links them by
   screen position, or by clicking a red target and then a game window. A target turns green when its window
   is linked. Top row = group 1, bottom row = group 2; left = left toon, right = right toon.
3. Keep ToonRepeater focused and play. It only sends keys while its own window is the active one.

| Key | Action |
|---|---|
| `` ` `` | Toggle Multi / Mirror mode |
| `⌘` `` ` `` | Toggle the controller on/off |
| `1` / `2` | Switch active group (Multi mode) |
| `fn` (Toggle Throw) | Switch Charge / Low throw |
| `Esc` | Sent to both toons of the active group |

**Multi mode:** the active group's two toons each follow their own keybinds. Defaults: left toon WASD,
Left Shift jump, `\` throw; right toon arrow keys, Right Shift jump, `\` throw. Keys are translated into
the game's own controls (arrow keys, Control = jump, Forward Delete = throw) and sent to that toon's window.

**Mirror mode:** every key goes unchanged to all four windows. The Mirror Throw key (`\`) throws.

**Throw modes:** *Charge* holds throw for as long as you hold the key. *Low* sends a quick tap, which makes
an uncharged throw.

Preferences (`⌘,`) has three tabs. General: Keep Alive (taps Home in every window once a minute), keep
window on top, auto-update and Click Repeater settings. Keybinds: every action is rebindable. Theme: all
indicator colours.

## Click Repeater

The **Click Repeater** toggle at the bottom of the controller window turns it on and off; the menu item
**Controller › Click Repeater** does the same. While it's on, every left click you make in one linked game
window is repeated at the same spot in the other linked windows, so every toon picks the same gag, target or
button.

Toontown ignores clicks on a window that isn't in front, so each other window is briefly brought forward and
clicked, then focus returns to the window you clicked. For the same reason, if your click is the one that
brings a game window to the front, Toontown never receives it, so ToonRepeater clicks that window again at
the end. A click on a window that was already in front isn't repeated, because it registered, and repeating
it could undo a toggle such as opening the Shticker Book. Clicks you make while a repeat is still running are
ignored. **Preferences › General › Pause per step** sets how long it waits at each stage (default 0.25 s);
raise it if repeated clicks don't register. Positions are measured within each window's game area, so they
line up exactly when the windows are the same size (⌘G) and are scaled otherwise.

## Quickstart (⌘K)

Click **Quickstart 4 Toons** in the small Quickstart window docked under the controller (shown at launch;
it closes once used, or close it yourself and bring it back with **Controller › Show Quickstart Button**), or
choose **Controller › Quickstart 4 Toons**. It logs in four of the launcher's saved accounts one after another:

1. The first time, ToonRepeater opens the Toontown Launcher and reads the accounts saved in its username list
   (about 10 seconds for six accounts). It remembers the list, so later runs open the picker instantly; click
   **Refresh Accounts** in the picker after adding or removing accounts in the launcher.
2. You choose an account for each slot: Group 1 left/right, Group 2 left/right. Your choices are remembered.
3. For each slot it reopens the launcher, picks the account (opens the list, arrows down to it and clicks it,
   as you would), presses GO, waits for the game window, links it to the slot, then quits the launcher.
4. Finally the four windows are arranged in a 2×2 grid. **Controller › Arrange Game Windows** (⌘G)
   re-arranges them at any time. To leave room for other windows, set **Preferences › General › Arrange
   Game Windows uses** to part of the screen, for example the right 70%.

Don't use the mouse or keyboard while it runs, because it clicks inside the launcher. Cancel stops it after
the current step. Passwords never leave the launcher: ToonRepeater only stores the usernames you picked.
Accounts must already be saved in the launcher (log in once with **Remember Me** ticked).

## Privacy

ToonRepeater asks once, on first launch, whether to share **anonymous usage statistics**; you can change
your answer any time in Preferences › General. If you allow it, it sends to
[TelemetryDeck](https://telemetrydeck.com):

- that it was installed (once);
- per session: minutes the app ran, the most game windows it controlled at once, and how many times Quickstart
  and Click Repeater were used;
- TelemetryDeck's standard session details: app version, macOS version and Mac model type;
- a random install ID created on first launch, which TelemetryDeck hashes before it leaves your Mac.

It never sends launcher usernames, passwords, file names, process IDs or hardware serial numbers. Launcher
passwords never leave the Toontown Launcher at all; Quickstart only stores the usernames you choose, on your
Mac. Builds without a TelemetryDeck app ID (`TELEMETRYDECK_APP_ID` in `build.sh`) send nothing.

## Troubleshooting

ToonRepeater keeps a log in `~/Library/Logs/ToonRepeater/` (**Help › Show Log Folder**). To report a
problem, choose **Help › Export Diagnostic Report…** and attach the zip to a GitHub issue. It contains the
logs, any ToonRepeater crash reports from the last 30 days and basic system details; no account names.

## Updates

ToonRepeater checks GitHub for a newer release on startup (turn this off in Preferences › General) and from
**ToonRepeater › Check for Updates**. If one is available, it shows the release notes and offers **Update**,
**Later** or **Skip This Version**. Choosing Update downloads the release, checks that it's genuine (same app,
intact code signature, signed with the same certificate as the copy you have), replaces the app and restarts
it. If ToonRepeater was opened straight from Downloads, macOS runs it from a temporary read-only location;
move it to Applications first so it can update itself.

## Releasing

1. Bump `VERSION` (and `BUILD_NUMBER`) in `build.sh`, then run `./build.sh --release`. Sign releases with the
   same certificate every time, or existing installs will refuse the update.
2. On GitHub, create a release with a tag matching the version (e.g. `v1.1`), write the release notes (shown
   in the update prompt), and attach `build/ToonRepeater.app.zip`. Don't mark it as a pre-release; drafts and
   pre-releases are ignored by the updater.

## License

MIT; see [LICENSE](LICENSE).

## Credits

ToonRepeater is based on [SaltyTT's MultiController](https://github.com/saltyTT/MultiController)
([ttmulti.com](https://www.ttmulti.com)), the original Toontown MultiController for Mac. Thank you, SaltyTT!

**How it was made:** ToonRepeater was reverse engineered and programmed with AI. MultiController 1.3's
published app was analysed (its compiled code, interface files and settings) with the help of Anthropic's
Claude, and the behaviour it found was reimplemented from scratch in Swift. The original's source code was
never published, and ToonRepeater contains none of its code or artwork. Click Repeater, Quickstart, window
linking and arranging, the GitHub updater, diagnostics and analytics are new.
