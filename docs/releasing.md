# Releasing

From 0.2.3 on, players start the game with the "Jericho Co-op+" shortcut, which runs
`coop\coop-launcher.ps1` (`tools/launcher.ps1`). Before the game starts it reads
`https://api.github.com/repos/dolbaras/jericho-coop/releases/latest` and installs that release when
its tag is newer than `coop\version.txt`. Publishing a release therefore updates every player who
uses the shortcut the next time they start the game, so a release must be finished and tested
before it goes up.

What the launcher already out there relies on, so every later release keeps it:

- **Tag** `v<major>.<minor>.<patch>` (parsed as a .NET `[version]`), a full release: drafts and
  pre-releases are not "latest" and are never installed.
- **Asset** named `jericho-coop-<version>.zip` (the first asset matching `jericho-coop-*.zip`),
  attached to that release, so its URL is under
  `https://github.com/dolbaras/jericho-coop/releases/download/`. The launcher checks the download
  against the `sha256:` digest GitHub gives for the asset.
- **`coop-installer.ps1` at the root of the zip** (as `tools/package.ps1` builds it), taking
  `-Game <folder> -AutoClose -NoShortcut`: install into that folder with the window, close it by
  itself after a successful install, exit code 0 on success and non-zero on failure;
  `-NoShortcut` refreshes only the shortcuts the install record lists.
- **`files\coop\version.txt`** holding the version without the `v`.
- **`<game>\coop\install.txt`**, the install record the next installer reads: `version=`,
  then one line per `file=`, `backup=`, `built=` and `shortcut=`. 0.2.3-0.2.4 wrote all
  shortcuts on one `shortcut=` line joined by spaces (or an empty one with none); from 0.2.5
  the installer splits such a line after each `.lnk` and drops empty ones, and keeps doing so.

A change to any of these needs a launcher that copes with both the old and the new form, shipped
one release before the old form is dropped.

Testing an update without GitHub: serve a releases/latest-style JSON and the zip locally and run
`coop-launcher.ps1 -Feed http://127.0.0.1:<port>/latest.json -NoStart` (or set
`JERICHO_COOP_FEED` for a start through the shortcut). New shortcuts go to `-ShortcutDir <folder>`
in tests, never to the desktop. An update test should start from the previous published zip
installed with two shortcut folders (as a normal install's desktop and Start menu), so the
record looks like a player's; then check the record, that both shortcuts were refreshed, and
that uninstalling removes them.
