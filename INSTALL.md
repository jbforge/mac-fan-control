# Installing Fan Control

## The first-run warning

This build is **not signed by an Apple developer account**, and macOS quarantines
anything downloaded from the internet. If you double-click `FanControl.app`
straight out of your Downloads folder, macOS refuses to open it — it cannot
verify the app is free of malware, because nobody paid Apple to vouch for it.

The same applies to the command-line pieces: macOS terminates an unsigned
quarantined binary the moment it starts.

**Use the installer below.** It clears the quarantine flag on the files it
installs, so you never hit the warning at all. Build it yourself from source if
you would rather not take a downloaded binary's word for it — that is the point
of the project.

## Install

Open Terminal, `cd` into this folder, and run:

```sh
./install.sh
```

It will ask for your password. That is not optional and not incidental: writing
fan speeds requires talking to the SMC as root, so a small daemon (`fanctld`)
gets installed as a system LaunchDaemon. The menu bar app itself runs as you and
talks to that daemon over a local socket.

The installer puts three things in place:

| Path | What |
|---|---|
| `/Applications/FanControl.app` | the menu bar app |
| `/usr/local/libexec/fanctld` | the root daemon, started at boot |
| `/usr/local/bin/fanctl` | the CLI |

Then start it:

```sh
open /Applications/FanControl.app
```

To have it start at login: System Settings → General → Login Items → add
FanControl.

## Uninstall

```sh
./uninstall.sh
```

Fans return to macOS automatic control when the daemon stops.

## If you still see "cannot be opened"

You most likely opened the app directly instead of running `./install.sh`. If you
want to approve it by hand anyway: System Settings → Privacy & Security, scroll
to Security, and use **Open Anyway** next to the message about FanControl.
