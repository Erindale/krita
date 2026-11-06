# Krita on the iPad: Phase 5 build record

Phase 5 of the personal iPadOS port (see `IOS_PORT_PLAN.md`): Krita built for the device SDK, signed with a personal development team and installed on a real iPad. Phase 4 (the simulator) is in `IOS_KRITA_BUILD.md`.

**Result:**
- Krita runs on an iPad mini (A17 Pro, iPadOS 27.0.1), installed over Wi-Fi.
- The device build needed no source changes beyond Phase 4.
- The first real-device issue, a settings dialog that could not be closed, is fixed and confirmed on the iPad.
- Apple Pencil pressure, tilt and Pencil Pro barrel roll work. Roll needed a Qt patch; its first version ran the wrong way and was reversed.
- Bundles import through Settings › Manage Resource Libraries, or load from the Krita › Resources folder in the Files app (Phase 6, below).
- Large documents: about 30 layers of 2500 × 3500 (about 1 GB of 8-bit RGBA pixels) open without iPadOS closing the app.

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
| The keyboard (or, with a hardware keyboard, the suggestion bar) kept popping up and pushing the window up while working, e.g. picking a brush from the toolbar's preset popup or opening Configure Krita. Qt for iOS shows it whenever the focused widget accepts text, and Krita moves focus into search fields and spin boxes all the time | `krita/ios/KisIosKeyboardPolicy.cpp` ("tap to type"): an application event filter that answers `ImEnabled = false` to the input method query for every focus object except a text field the user tapped. A press on a text field unlocks it before it gets focus, so tapping a field still brings the keyboard up. Spin boxes, sliders and programmatic focus never do. Setting `WA_InputMethodEnabled` is not enough: `QLineEdit` and the text edits answer `ImEnabled` themselves | Fixed on the iPad mini simulator: Configure Krita and New Document open without the keyboard, the brush popup opens and a brush can be picked without it, and tapping Search brings it up and typing filters the pages. Confirmed on the iPad |
| The brush editor (toolbar "Edit brush settings") opened wider than the iPad mini, with the right side clipped and everything squeezed into one strip. Its minimum width is 947 points; the dialog fitter shrank the window, but the content kept its minimum | `libs/widgetutils/KisPopupButton.cpp`, iOS only: popup contents (not menus) go into a `QScrollArea`, and `adjustPosition()` sizes the popup from the content's size hint, capped at the screen. The editor now opens at full height and scrolls sideways to the Save buttons and the Scratchpad | Verified on the iPad mini simulator; installed on the iPad. Touch-dragging inside the popup moves sliders rather than scrolling; use the scrollbar |
| With an autosave file left over, the launch stayed black: the recovery dialog ran a nested event loop inside UIKit's "did become active" callback, and UIKit can't finish activating the scene until that returns | `krita/ios/KisIosApplicationState.mm` now starts Krita with a queued call from Qt's event loop after the notification, instead of inside it | Verified on the iPad mini simulator: the recovery dialog appears and recovering works |
| The brush editor, once fitted, could fill the whole screen in detached mode (a borderless window on iOS), leaving no way to close it | `KisPopupButton` on iOS: popups are always attached (`setPopupWidgetDetached()` ignores detach), and capped to the space below their button, so the toolbar stays visible. Tapping the button again or anywhere outside the popup closes it | Verified on the iPad mini simulator; confirmed on the iPad |
| No app icon | `krita/CMakeLists.txt` (iOS): compiles the same Icon Composer icon as macOS (`pics/branding/<branding>/krita.icon`) with `actool` for the SDK in use, and copies `Assets.car` and the fallback PNGs into the bundle after the link. `Info.plist.in` declares `CFBundleIcons`/`CFBundleIcons~ipad` (icon name `krita`) | Shows on the simulator's home screen and Dock (Liquid Glass style); confirmed on the iPad |
| Apple Pencil Pro barrel roll did nothing: Qt for iOS passed a rotation of 0 with every Pencil event | Deps fork, `ext_qt/0003-iOS-pass-Apple-Pencil-Pro-barrel-roll-as-tablet-rotation.patch`: `quiview.mm` passes `UITouch.rollAngle` (and the hover recognizer's `rollAngle`, iOS 17.5+) converted to degrees and negated as `QTabletEvent::rotation()` (UIKit counts anticlockwise, Qt and Krita clockwise; the first version had it the wrong way round on the iPad), and the Pencil device reports the `Rotation` capability. Krita's Rotation sensor reads it from there | Pressure and tilt confirmed on the iPad; roll reached Krita but was inverted, so the sign is flipped. Reversed roll confirmed on the iPad |
| In New Document, the dropdowns (unit, colour model) did not open, and tapping a number field (width, resolution) gave no keyboard | Both came from the keyboard policy. Qt shows a dropdown's list as a native picker in the keyboard's place, and it asks for that with the same input method query the policy was answering "no" to; non-editable combo boxes are now left alone. Number fields now unlock on a tap (released within 12 points of the press), so dragging a slider spin box still never brings the keyboard up | Verified on the iPad mini simulator: the unit dropdown opens the picker, and tapping Resolution brings up the keyboard on its numbers page |
| Memory with a large document (the plan's 500 MB test) | None needed. A document duplicated up to about 30 layers of 2500 × 3500 (about 1 GB of 8-bit RGBA pixels, possibly less in memory, since duplicated layers share tiles until painted on) | Done on the iPad: iPadOS did not close Krita |
| The main window kept the screen size it had at launch | `libs/ui/KisMainWindow.cpp` (iOS): the window follows the screen's `availableGeometryChanged`, e.g. on rotation | Built; not specifically checked |

## What does not work yet

Most of what is missing comes from one decision in Phase 4. iOS cannot load plugins at runtime, so the build links plugins into the executable, and only those in `KRITA_STATIC_PLUGINS_ALLOWLIST` (`cmake/modules/KritaStaticBuild.cmake`). Phase 4 kept the list to the 17 needed to start, paint, save and reopen a `.kra`. Phase 6 (bundles, below) added the resource manager and every brush engine, for 31:
- the colour engine
- all 14 brush-engine plugins, MyPaint included
- the resource manager (Settings › Manage Resource Libraries and Manage Resources)
- the default, selection, transform and flake tools
- image and path shapes
- KRA and PNG import and export
- the Layers, Brush Presets, Advanced Colour Selector and Undo History dockers

Anything else that Krita implements as a plugin is absent. Its menu entries either do nothing or, where Krita assumes the plugin exists, crash.

| Area | On the iPad | Plugins it needs (`plugins/…`) |
|---|---|---|
| Filters | The Filter menu is empty | `filters/*`: about 30 plugins (blur, colors, colorsfilters, levelfilter, unsharp, …) |
| Fill layers | **Layer › New › Fill Layer crashes the app** (reported on the iPad). It has no generators to offer | `generators/*` (solid, gradient, pattern, screentone, simplexnoise, multigridpattern, seexpr) |
| Filter layers and masks | Need filters, so empty at best; not tried | as Filters |
| File formats | Only `.kra` and `.png` open and save: no JPEG, PSD, ORA, WebP, TIFF, EXR, GIF, PDF, SVG | `impex/*` (jpeg, psd, ora, qimageio, exr, …) |
| Image and layer commands | Rotate, shear and offset image, colour-space conversion, split layer and image, wavelet decompose and similar are missing | `extensions/*` |
| Dockers | Only Layers, Brush Presets, Advanced Colour Selector and Undo History. No palette, pattern, overview, touch, animation timeline, recorder, snapshot, etc. | `dockers/*` |
| Assistants | No painting assistants | `assistants` |
| Filter brush engine | Linked, but has no filters to apply until filters are linked | `filters/*` |
| Python scripting | Absent. There is no Python on iOS in this build, so it stays out | `extensions/pykrita` |

**What adding plugins costs:** add a target name to `KRITA_STATIC_PLUGINS_ALLOWLIST` (or set it to `ALL`) and rebuild. Each new plugin may need dependencies the iOS prefix lacks (e.g. libheif, OpenEXR, poppler, SeExpr). It may also have code that assumes desktop features (`QProcess`, file dialogs) and need the same kind of guards as in Phase 4. Plugins that assumed another plugin was there, like the fill-layer dialog, should come back with the plugin they wanted rather than get a separate fix.

## Still to check on the iPad

- **Pencil:** hover.
- **Behaviour:** rotation, multitasking (Split View), and saving and opening through the Files picker on the device.

## Phase 6: bundles

Bundles were the one missing piece for the user's own work.

| | |
|---|---|
| Change | `KRITA_STATIC_PLUGINS_ALLOWLIST` adds `kritaresourcemanager` and the 13 brush-engine plugins that were missing: curve, deform, experiment (shape), filter, grid, hairy, hatching, MyPaint, particle, round marker (quick), sketch, spray, tangent normal. They need no new dependencies (libmypaint was already in the prefix). The simulator app grew from 249 MB to 256 MB |
| Existing build trees | The allowlist is a cache variable, so a tree configured earlier keeps its old list: reconfigure with `cmake -U KRITA_STATIC_PLUGINS_ALLOWLIST .` in the build directory |
| Import through Krita | Settings › Manage Resource Libraries › Import opens the iOS Files picker. A `.bundle` anywhere the picker reaches (On My iPad, iCloud Drive) is copied into Krita's resources and listed at once |
| Drop into the Files app | Krita loads every `.bundle` in **On My iPad › Krita › Resources** at startup, the same folder its own default bundles live in. Copy one there in the Files app and restart Krita |
| Tested with | Expressive Inks v2.1 (18 presets: 15 pixel brush, 1 colour smudge, 1 sketch, 1 hatching). Before the engines were added, the sketch and hatching presets failed to load ("Could not load the resource from the bundle"); after, all 18 load and the sketch preset paints |
| Status | Both routes verified on the iPad mini simulator; installed on the iPad |

## Simulator note

Installing a new build over the old one and launching it sometimes left the simulator window black: the root view was never laid out. A fresh install always works, so `run-krita-sim.sh` now uninstalls first. Relaunching after `simctl terminate` can do it too; rebooting the simulator (`simctl shutdown` and `boot`) brings it back without losing the app's files. The device has not shown it.
