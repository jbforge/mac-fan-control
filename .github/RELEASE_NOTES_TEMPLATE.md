Universal build for Apple Silicon and Intel Macs, macOS 14 or later.

## Install

Download the zip, unpack it, then in Terminal from that folder:

```sh
./install.sh
```

It asks for your password — the fan daemon runs as root, because writing fan
speeds means talking to the SMC. See `INSTALL.md` in the archive for what gets
installed where, and `./uninstall.sh` to remove it.

## About the first-run warning

These binaries are **not signed by an Apple developer account**. macOS will
refuse to open `FanControl.app` if you double-click it out of your Downloads
folder, and will terminate the command-line pieces outright. `install.sh` clears
the download quarantine on the files it installs, so following the steps above
avoids the warning entirely.

If you would rather not trust a downloaded binary, build it from source — the
README covers it and it takes one command.

Verify the download against `SHA256SUMS.txt`:

```sh
shasum -a 256 -c SHA256SUMS.txt
```
