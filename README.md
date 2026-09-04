# PinAbove

PinAbove is a small macOS menu bar app that keeps the focused window above
other windows. It uses yabai under the hood and has no network connection or
analytics.

We tested it successfully on an M1 MacBook Pro running macOS 15.7.5 with
**yabai 7.1.16**. PinAbove intentionally expects that version.

## Install yabai with Homebrew

We installed yabai 7.1.16 through a local Homebrew tap. Homebrew's
`version-install` command can install an older release into a personal tap:

```sh
brew tap asmvik/formulae
brew trust --formula asmvik/formulae/yabai
brew version-install asmvik/formulae/yabai@7.1.16
```

Make sure Homebrew links it as `/opt/homebrew/bin/yabai`, then check the
version:

```sh
yabai --version
```

The expected result is `yabai-v7.1.16`. You must also allow yabai under
**System Settings → Privacy & Security → Accessibility**.

## One-time Mac setup

The always-on-top feature needs yabai's scripting addition. On an Apple
Silicon Mac, shut down the Mac, hold the power button until startup options
appear, then open **Options → Utilities → Terminal**.

Run this in the Recovery terminal:

```sh
csrutil enable --without fs --without debug --without nvram
```

This keeps SIP partially enabled but turns off the three parts yabai needs:

- Filesystem Protections
- Debugging Restrictions
- NVRAM Protections

Kext Signing, DTrace Restrictions, BaseSystem Verification, and Authenticated
Root remain enabled. Restart normally, then run:

```sh
sudo nvram boot-args=-arm64e_preview_abi
```

Restart once more, then start yabai and load its scripting addition:

```sh
yabai --start-service
sudo yabai --load-sa
```

You can test the setup with a disposable window:

```sh
yabai -m window --sub-layer above
yabai -m window --sub-layer auto
```

Changing SIP reduces macOS security. Read the
[official yabai SIP guide](https://github.com/asmvik/yabai/wiki/Disabling-System-Integrity-Protection)
before doing it. PinAbove never changes SIP or runs `sudo` itself.

## Use PinAbove

Open PinAbove and use `Control-Command-T` to pin or unpin the focused window.
Click the menu bar pin to change the shortcut or check yabai's status.

To build it from source, run `./build.sh`. The project is licensed under MIT.
