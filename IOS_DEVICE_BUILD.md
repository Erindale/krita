# Krita on the iPad: Phase 5 build record

Phase 5 of the personal iPadOS port (see `IOS_PORT_PLAN.md`): Krita built for the device SDK, signed with a personal development team and installed on a real iPad. Phase 4 (the simulator) is in `IOS_KRITA_BUILD.md`.

**Result:**
- Krita runs on an iPad mini (A17 Pro, iPadOS 27.0.1), installed over Wi-Fi.
- The device build needed no source changes beyond Phase 4.
- The first real-device issue, a settings dialog that could not be closed, is fixed and confirmed on the iPad.
- **Still open:** Apple Pencil pressure and tilt, and behaviour with large documents.

## Device and signing

| | |
|---|---|
| iPad | iPad mini (A17 Pro), `iPad16,1`, UDID `00008130-000E41323A04001C`, iPadOS 27.0.1. Developer Mode on; paired with this Mac over the local network (`devicectl`, no cable) |
| Team | Personal (free) team `5U93YR33HD`; identity `Apple Development: erindalewoodford@gmail.com (K9MZBDAJ5W)` |
| Bundle id | `xyz.erindale.krita`, set with the new CMake option `KRITA_IOS_BUNDLE_IDENTIFIER` (default `org.krita.ipad`). App IDs are unique across all developer accounts, so a personal build should use its own |
| Profile | Xcode only creates free-team profiles itself. One was obtained by building a throwaway Qt example in Xcode with the same bundle id, `-allowProvisioningUpdates -allowProvisioningDeviceRegistration` and the iPad as destination. The result, `iOS Team Provisioning Profile: xyz.erindale.krita`, covers this iPad, has `get-task-allow`, and is **valid for 7 days** (this one expires 2026-11-12) |
| Signing | The Ninja-built `krita.app` (with `share/` and `lib/qml` copied in) gets `embedded.mobileprovision`, an entitlements file (`application-identifier`, team id, `get-task-allow`), and `codesign` with the identity |
| Install and launch | `xcrun devicectl device install app --device <udid> krita.app`, then `xcrun devicectl device process launch --device <udid> xyz.erindale.krita` |

All of this is `/Volumes/Krita/krita-ios/scripts/run-krita-device.sh`. It finds the profile for the bundle id, prints its expiry, assembles and signs the app, installs it and launches it. To renew the 7-day signature, rerun it after Xcode has refreshed the profile; if the profile has expired, rebuild the throwaway example first, as above.

## Build

- Configured as for the simulator, with `KDECI_IOS_SDK=iphoneos` against `deps-iphoneos`, plus `-DKRITA_IOS_BUNDLE_IDENTIFIER=xyz.erindale.krita`, in `build/krita-configure-iphoneos`.
- The first compile took 18 minutes at 4 jobs, with no errors. `ninja all` builds the translations; building `krita` alone leaves `share/locale` empty.
- The executable is 160 MB, arm64 with `platform 2` (iOS device) and `minos 17.0`; the app is 242 MB.

## What the device showed

| Finding | Fix | Status |
|---|---|---|
| Settings › Configure Krita opened larger than the iPad mini's screen (744 × 1133 points), with its buttons off screen, so it could not be closed | `krita/ios/KisIosDialogFitter.cpp`: an application event filter that, on iOS, fits any dialog bigger than the available screen area when it is shown or the screen rotates. It relaxes the layout minimum if needed and centres the dialog; dialogs that fit are left alone. iOS has no window manager to do this, while Android's Qt fork had window-management patches | Fixed, confirmed on the iPad; reproduced and checked on the iPad mini simulator first |
| The keyboard appears when Configure Krita opens, because its search field takes focus | none yet | Cosmetic; the keyboard's dismiss key hides it |

## Still to check on the iPad

- **Pencil:** pressure and tilt with the default pen and a tilt-aware preset, and hover.
- **Memory:** a large document, to see whether iPadOS kills the app (the plan's 500 MB test).
- **Behaviour:** rotation, multitasking (Split View), and saving and opening through the Files picker on the device.
- **Phase 6:** bundles dropped into the Krita folder in the Files app.
