# BootVolume

[한국어](README.ko.md) · [Website](https://bootvolume.oodot.top)

A macOS menu bar app that keeps your Mac silent after login but still plays the startup chime.

On Apple silicon Macs the startup chime follows the volume your Mac had when it was shut down. If you keep the volume at 0, there is no chime. BootVolume solves this:

- **After login** it sets the volume to the value you choose (default 0), or restores the volume from before shutdown.
- **At shutdown** a small root helper writes the chime volume you chose straight into NVRAM, so the chime plays at that volume. Your normal volume is not touched.

The UI is in Korean.

## Requirements

- macOS 15 or later
- Apple silicon
- Tested only on a MacBook Air (M4) running macOS 27. Other models may behave differently. See [How it works](#how-it-works).

## Build and install

```sh
./build.sh
```

This builds a release binary and installs `/Applications/BootVolume.app`. It signs with, in order:

1. `$BOOTVOLUME_SIGN_ID`
2. the first `Apple Development` identity in your keychain
3. an ad-hoc signature

Then open the app, click the speaker icon in the menu bar and press **도우미 설치** (Install helper). You will be asked for an administrator password.

## How it works

The startup chime reads the NVRAM variable `SystemAudioVolumeExtension` (2 bytes; the high bit of the second byte means muted). macOS updates it when the volume changes. A volume change made during shutdown, however, is not written in time.

So BootVolume does this:

1. **Measure.** When you set the chime volume, the app mutes the output, briefly sets the system volume to that value, reads the 2 bytes macOS writes, clears the mute bit, and restores your volume and mute state. macOS still writes the volume while muted (it only sets the mute bit), so nothing becomes audible; audio that is already playing is muted for about 4 seconds. The format is undocumented, so the value is always measured on your Mac and never hard-coded.
2. **Write at shutdown.** A root LaunchDaemon (`top.oodot.bootchime`) waits for shutdown. When launchd sends `SIGTERM`, it writes the measured value to `SystemAudioVolumeExtension`. It checks once after 0.5 s and writes again only if the value was overwritten.
3. **Login.** The app sets the volume as soon as it starts, and again after 1, 3 and 6 seconds.

The **부팅음 켜기** (startup sound) switch also clears `StartupMute=%01` and the legacy `SystemAudioVolume=%80`, either of which silences the chime.

## Files

| Path | Owner | Purpose |
|---|---|---|
| `/Library/Application Support/BootVolume/bootchime.sh` | root | helper script |
| `/Library/Application Support/BootVolume/chime-value` | you | measured value, 4 hex chars |
| `/Library/LaunchDaemons/top.oodot.bootchime.plist` | root | helper daemon |
| `/var/log/bootchime.log` | root | helper log |
| `~/Library/Logs/BootVolume.log` | you | app log |

Both logs and a status check are shown in **Settings → 기록** (Log).

## Security notes

The helper runs as root, so:

- The helper only reads `chime-value`. It ignores files larger than 16 bytes and accepts exactly 4 lowercase hex characters. Otherwise it writes nothing and logs an error.
- When you install the helper, the root script first checks that the app bundle still satisfies the designated requirement of the running app. It then copies the files to a root-only temp directory, checks the signature again, and compares the copies with the originals.
- The admin script is passed to `osascript` as an argument. It is never written to a file.
- Values read from user defaults are validated before they are used in the admin script.

## Limitations

- A forced power-off (holding the power button) does not give the helper a chance to run, so the next boot may be silent.
- The NVRAM format is undocumented and may change with macOS updates.

## Uninstall

1. Press **도우미 지우기** (Remove helper) in the menu bar panel.
2. Quit the app and delete `/Applications/BootVolume.app`.
3. Optionally remove the leftovers:

```sh
defaults delete top.oodot.bootvolume
rm -f ~/Library/Logs/BootVolume.log
sudo rm -f /var/log/bootchime.log
```

## Debug flags

```sh
open -n /Applications/BootVolume.app --args --test-poweroff   # simulate the shutdown notification
open -n /Applications/BootVolume.app --args --test-measure    # measure the current chime volume (updates settings)
```

## License

[MIT](LICENSE)
