# BootVolume

[한국어](README.ko.md) · [Website](https://bootvolume.oodot.top)

**A Mac that always starts with the same, grand chime**

Keep your Mac's volume wherever you like, and the startup chime steady. Set a volume just for the startup chime, no matter what your Mac's usual volume is.

macOS 15 or later · Apple Silicon

The app UI is in Korean. English is planned.

## Set the startup chime volume without Terminal

### Volume after login

When you start up and log in, your Mac is set to the volume you chose. You can also have it restore the volume from before shutdown.

### Startup chime volume

You no longer need to turn the volume up before shutting down just to hear the chime. Set the chime volume, and BootVolume sets the shutdown volume to that value.

### Status check

The app checks itself: whether the chime volume can be set, update status and more, and shows you the result.

## Install

### Quick install

1. Click [Download from GitHub](https://github.com/gns13-space/BootVolume/releases/latest) to get BootVolume.
2. Unzip it and move the BootVolume app to the Applications folder.
3. Open the app.

### Build in Terminal

Enter the following in Terminal to build. It installs into the /Applications folder.

```sh
git clone https://github.com/gns13-space/BootVolume
cd BootVolume
./build.sh
```

It signs with `$BOOTVOLUME_SIGN_ID`, then the first `Apple Development` identity in your keychain, then an ad-hoc signature, in that order.

### After installing

1. Click the speaker icon in the menu bar.
2. Press **도우미 설치** (Install helper) and set the chime volume to finish setup.

## When the app doesn't work as expected

- **Forced shutdown**: If you force a shutdown by holding the power button, the app can't do its work, and the next chime may not play at the volume you set.
- **macOS updates**: After macOS updates to a new version, the chime may not play at the volume you set. In that case, reinstall the helper.
- **Intel Macs and macOS 14 or earlier**: The app may not work properly on an Intel Mac or on macOS 14 or earlier.

## FAQ

**There's no startup chime**

Check that the helper shows as working at the bottom of the panel. If you force your Mac off, the helper can't run, and the next chime may not play. Shut down normally with **Shut Down** in the Apple menu.

**Why does it need an administrator password?**

Writing to NVRAM, where the chime volume is stored, requires administrator privileges. The helper can change only that value. BootVolume is also open source, so you can use it with peace of mind.

**Does changing the chime volume change the system volume too?**

When you move the chime volume slider or change the chime volume in the BootVolume panel, the system volume is muted for about 2–3 seconds. Music or video that's playing goes silent for a moment, which is normal. Occasionally an unexpected bug may set the system volume to the chime value for those 2–3 seconds, so pausing any music or video before changing the setting is recommended.

**Which Macs does it work on?**

Apple Silicon Macs running macOS 15 or later. It hasn't been verified on Intel Macs or macOS 14 or earlier. Tested on a MacBook Air (M4) running macOS 27.

**How do I uninstall it?**

Press **도우미 지우기** (Remove helper) in the panel, quit the app and delete it from the Applications folder. To also remove settings and logs, enter the following in Terminal.

```sh
defaults delete top.oodot.bootvolume
rm -f ~/Library/Logs/BootVolume.log
sudo rm -f /var/log/bootchime.log
```

## How it works

On Apple Silicon Macs the startup chime reads the NVRAM variable `SystemAudioVolumeExtension`. It is 2 bytes, and the high bit of the second byte means muted. macOS updates it when the volume changes, but a change made during shutdown is not written in time. So BootVolume works like this:

1. **Measure**: When you set the chime volume, the app mutes the output, briefly sets the system volume to that value, reads the 2 bytes macOS writes, and restores your volume and mute state. macOS still writes the volume while muted, so nothing gets louder while measuring. The format is undocumented, so the value is always measured on your own Mac.
2. **Write at shutdown**: A helper running with administrator privileges (`top.oodot.bootchime`) waits for shutdown. When it gets the shutdown signal, it writes the measured value to `SystemAudioVolumeExtension`. It checks once after 0.5 s and writes again only if the value was overwritten.
3. **Set after login**: The app sets the volume as soon as it starts, and again after 1, 3 and 6 seconds.

The **부팅음 켜기** (Startup sound) switch also clears the two values that silence the chime (`StartupMute=%01` and the legacy `SystemAudioVolume=%80`).

### Files

| Path | Owner | Purpose |
|---|---|---|
| `/Library/Application Support/BootVolume/bootchime.sh` | root | helper script |
| `/Library/Application Support/BootVolume/chime-value` | you | measured value, 4 hex chars |
| `/Library/LaunchDaemons/top.oodot.bootchime.plist` | root | helper daemon |
| `/var/log/bootchime.log` | root | helper log |
| `~/Library/Logs/BootVolume.log` | you | app log |

Both logs and a status check are in **Settings → 기록** (Log).

### Security

Because the helper runs with administrator privileges:

- The helper only reads `chime-value`. It ignores files larger than 16 bytes and accepts exactly 4 lowercase hex characters. Otherwise it writes nothing and logs an error.
- When you install the helper, it first checks that the app bundle satisfies the running app's signing requirement. It then copies the files to a root-only temp directory, checks the signature again and compares the copies with the originals.
- The admin script is passed to `osascript` as an argument and never saved to a file.
- Values read from the app's settings are validated before they go into the admin script.

### Debug flags

```sh
open -n /Applications/BootVolume.app --args --test-poweroff   # simulate the shutdown notification
open -n /Applications/BootVolume.app --args --test-measure    # re-measure the current chime volume (updates settings)
```

## License

[MIT](LICENSE) · Languages: Korean, English (planned)
