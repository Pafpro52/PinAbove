# PinAbove

PinAbove is a small macOS menu bar app that keeps the focused window above
other windows. It uses yabai under the hood.

## Install yabai

Install yabai 7.1.16 with Homebrew:

```sh
brew tap asmvik/formulae
brew trust --formula asmvik/formulae/yabai
brew version-install asmvik/formulae/yabai@7.1.16
```

Versions 7.1.13, 7.1.14, and 7.1.15 did not work in this setup. Version 7.1.16
works. Newer versions have not been tested.

## One-time Mac setup

The always-on-top feature needs yabai's scripting addition. On an Apple
Silicon Mac, shut down the Mac and hold the power button until startup options
appear. Open **Options → Utilities → Terminal** and run:

```sh
csrutil enable --without fs --without debug --without nvram
```

This keeps SIP partially enabled while disabling the three parts required by
yabai:

- Filesystem Protections
- Debugging Restrictions
- NVRAM Protections

Kext Signing, DTrace Restrictions, BaseSystem Verification, and Authenticated
Root remain enabled.

Restart normally and run:

```sh
sudo nvram boot-args=-arm64e_preview_abi
```

Restart once more, then start yabai and load its scripting addition:

```sh
yabai --start-service
sudo yabai --load-sa
```

This setup weakens some macOS security protections. Read the
[official yabai SIP guide](https://github.com/asmvik/yabai/wiki/Disabling-System-Integrity-Protection)
before continuing. PinAbove does not change SIP itself.
