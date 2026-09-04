# PinAbove

PinAbove is a tiny, open-source macOS menu bar app that toggles the focused
window between yabai's `above` and `auto` sub-layers.

## Features

- Global, user-configurable shortcut (`Control-Command-T` by default)
- Compact menu bar popover
- Red/green yabai status indicator and a Start/Check button
- No Dock icon, network access, analytics, or screen capture
- Right-click the menu bar icon to quit

## Tested configuration

PinAbove 1.0 was built and manually tested with this configuration:

| Component | Tested value |
| --- | --- |
| Mac | M1 MacBook Pro (`arm64`) |
| macOS | 15.7.5, build 24G624 |
| yabai | 7.1.16 |
| yabai path | `/opt/homebrew/bin/yabai` |
| Default shortcut | `Control-Command-T` |
| Pin command | `yabai -m window --sub-layer above` |
| Unpin command | `yabai -m window --sub-layer auto` |

The Homebrew installation receipt on the test machine records yabai 7.1.16 as
an Apple Silicon source build from a local tap. The original release archive is:

```text
https://github.com/koekeishiya/yabai/releases/download/v7.1.16/yabai-v7.1.16.tar.gz
SHA-256: c4d5e31ad18afc8b46aa4cdaf5639088f044c72b3852787e9633db12d31a606b
```

## Requirements

- Apple Silicon Mac running macOS 13 or newer
- yabai **v7.1.16** at `/opt/homebrew/bin/yabai` or `/usr/local/bin/yabai`
- yabai enabled in **System Settings → Privacy & Security → Accessibility**
- A working yabai scripting addition

PinAbove deliberately rejects other yabai versions so a later release cannot
silently change the expected command behavior.

## Installing yabai 7.1.16

The test machine used Homebrew with a local versioned tap. Homebrew recommends
`brew version-install` for installing an older formula into a personal tap:

```sh
brew tap asmvik/formulae
brew trust --formula asmvik/formulae/yabai
brew version-install asmvik/formulae/yabai@7.1.16
```

Homebrew may install an extracted formula under a versioned name. Ensure its
binary is linked as one of the two paths supported by PinAbove, then verify it:

```sh
which yabai
yabai --version
```

The expected output is:

```text
yabai-v7.1.16
```

The archived Homebrew formula revision used for 7.1.16 is
`c9fc60dcb9746ae35a08e1fa8e6eaa2f604a3b92` in the yabai formula tap.
Freezing an old dependency means accepting responsibility for reviewing its
security fixes and compatibility changes.

## SIP and scripting addition

Controlling window layers requires yabai's scripting addition. On the tested
Apple Silicon configuration, `csrutil status` reported a custom, partially
disabled SIP configuration:

| SIP component | Tested state |
| --- | --- |
| Filesystem Protections | Disabled |
| Debugging Restrictions | Disabled |
| NVRAM Protections | Disabled |
| Kext Signing | Enabled |
| DTrace Restrictions | Enabled |
| BaseSystem Verification | Enabled |
| Authenticated Root Requirement | Enabled |

The boot arguments contained:

```text
-arm64e_preview_abi
```

This configuration weakens macOS protections. Do not copy commands blindly.
Read the official yabai documentation, make an informed decision, and perform
Recovery Mode changes yourself. PinAbove never changes SIP, invokes `sudo`, or
installs the scripting addition.

- [yabai SIP documentation](https://github.com/asmvik/yabai/wiki/Disabling-System-Integrity-Protection)
- [yabai installation documentation](https://github.com/asmvik/yabai/wiki/Installing-yabai-(latest-release))

After following yabai's official scripting-addition instructions, these are the
relevant yabai configuration lines:

```sh
yabai -m signal --add event=dock_did_restart action="sudo yabai --load-sa"
sudo yabai --load-sa
```

The official guide requires a narrowly scoped sudoers entry for `--load-sa`.
Its SHA-256 value must be regenerated whenever the yabai binary changes.

## Testing the setup

Check the installed version and daemon connection:

```sh
yabai --version
yabai -m query --windows --window
```

With a disposable window focused, test both operations:

```sh
yabai -m window --sub-layer above
yabai -m query --windows --window
yabai -m window --sub-layer auto
```

The query should report `"sub-layer":"above"` after the first command and
`"sub-layer":"auto"` or the normal automatic state after the last command.

If the daemon does not connect, inspect its service log:

```sh
tail -50 /tmp/yabai_$(whoami).err.log
```

An `accessibility features` error means yabai must be enabled under macOS
Accessibility settings before restarting the service.

## Installing PinAbove from GitHub Releases

1. Download `PinAbove.zip` from the release.
2. Extract it and move `PinAbove.app` to `/Applications`.
3. On first launch, right-click the app and select **Open**. Depending on macOS
   policy, **Privacy & Security → Open Anyway** may also be required for an
   ad-hoc signed, non-notarized community build.
4. Click the menu bar pin. A green light means the yabai daemon is reachable.
5. Focus a window and press the configured shortcut.

You do not need to publish PinAbove in the Mac App Store. GitHub can host both
the source code and a release zip. Developer ID signing and notarization remain
optional improvements for reducing Gatekeeper warnings.

## Building from source

Install Apple's Command Line Tools and run:

```sh
./build.sh
```

The app and zip are written to `dist/`. The default build is ad-hoc signed with
Hardened Runtime. If a Developer ID identity is available:

```sh
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

Run the built-in parser check with:

```sh
dist/PinAbove.app/Contents/MacOS/PinAbove --self-test
```

## Security and privacy

PinAbove executes only yabai v7.1.16 found at one of its two documented paths.
It does not use a shell, interpolate user input into commands, contact a server,
collect analytics, read screen contents, or run as root. See
[SECURITY.md](SECURITY.md) for vulnerability reporting instructions.

## License

MIT
