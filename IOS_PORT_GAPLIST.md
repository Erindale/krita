# iPadOS port: gap list (Phase 1 audit)

This is the Phase 1 audit for a personal, sideloaded iPadOS build of Krita that reuses the Android build's mobile code paths. Nothing in it has been compiled for iOS. Every claim was checked against this tree on Linux.

The three commits that come before this file are the changes that could be made and tested on Linux now (section 8).

## Sources

| Tag | Repository | Revision audited |
|---|---|---|
| `K:` (or no tag) | this repository (Krita master) | `1cb9083` (2026-11-03) |
| `D:` | [krita-deps-management](https://github.com/KDE/krita-deps-management), branch `master` | `aad563b` (2026-10-26) |
| `D6:` | same repo, branch `transition.now/qt6` | `2ba042f` (2026-10-27) |
| `L:` | same repo, default `HEAD` of the GitHub mirror (stale `kazakov/android-sdp` branch) | `a7ed8a9` (2024-03-20) |
| `CIU:` | [krita-ci-utilities](https://github.com/KDE/krita-ci-utilities) GitHub mirror (may lag invent) | `621fcee` (2024-04-22) |

`invent.kde.org` was not reachable from the Linux session. Every outside repository came from its GitHub mirror, and the Qt5 fork at `invent.kde.org/szaman/qt5` could not be read. The GitHub mirror of krita-deps-management has its `HEAD` on a stale 2024 branch, so **clone `master` explicitly** (`git clone -b master ...`); Krita's CI uses master too.

## Summary: what the audit changes in the plan

1. **Use Qt 6 for iOS, not the patched Qt 5.15.** Krita's default and Android builds use a patched Qt 5.15 fork that lives on invent and was unreachable here. That fork's iOS backend has never been tried against a current Xcode. Krita master already builds with Qt 6 (`-DBUILD_WITH_QT6=ON -DALLOW_UNSTABLE=QT6`), against a fork at `github.com/dimula73/qt5` branch `for-krita/6.11.3`. That fork carries none of the Android patches, so the stylus, storage and windowing fixes have to be ported for either Qt version (section 7).
2. **QtQuick is required, not optional.** `qmlmodules/` builds unconditionally, and the Text Properties docker and SVG text tool link QtQuick Controls 2. A Linux configure without QtQuickControls2 fails. Qt for iOS needs qtdeclarative and qtquickcontrols2, and their QML plugins have to be imported statically (section 7.4). The touch docker is QWidget-only.
3. **Dependencies live in krita-deps-management, not `3rdparty/`.** It is not a superbuild. Each of the 96 `ext_*` recipes is its own CMake project, and per-platform sets come from `latest/krita-deps.yml`. 28 recipes are needed for a painting-only build. Eight recipes have `if (APPLE)` branches that would fire on iOS (section 3).
4. **Everything must be static, and the plugin loader now supports that.** There are 171 plugin targets, all `kis_add_library(... MODULE)`. `KoJsonTrader` now also loads plugins registered with `Q_IMPORT_PLUGIN`, and every plugin factory, `Plugin` class and `.qrc` has a unique name. What remains for a static build is in section 8.
5. **Android-specific code mostly carries over to iOS.**
   - 144 of 286 Android sites can be reused on iOS behind a shared guard.
   - 32 need an iOS version: mainly the native file picker, security-scoped bookmarks, paths inside the `.app` bundle, and autosave when the app goes to the background.
   - The remaining 110 are Android-only.
   - About 100 of the reusable sites are the in-process libav encoder, which would bring animation and recorder export to iOS later (section 1).
6. **There are hidden iOS breakages outside the Android guards.**
   - `Q_OS_MAC` is also defined on iOS. One site was an outright build break; it is fixed in this branch.
   - CMake's `APPLE` is true on iOS, so about 25 macOS-only blocks would be pulled in.
   - `totalRAM()` falls back to 1000 MiB on iOS, which caps Krita's memory far below what an M-series iPad has.
   - Resource paths assume a `../share` layout that a flat `.app` doesn't have (sections 1, 2.2 row 32, 6.7).
7. **The resource folder is a small change.** `KoResourcePaths::getAppDataLocation()` (`libs/resources/KoResourcePaths.cpp:220`) would return `Documents/Resources` on iOS, and the resource database stays outside Documents as on Android. Bundles dropped there in the Files app are then picked up (section 6.6).

## 1. Q_OS_ANDROID sites

> **Status:** every **reuse** row below now reads `KRITA_MOBILE` instead of `Q_OS_ANDROID` / `ANDROID` (section 8, step 7); the line numbers are from the audited revision. **ios-twin** and **android-only** rows are unchanged.

The 275 `Q_OS_ANDROID` occurrences in 75 files collapse into **255 rows**: **135 reuse**, **27 ios-twin**, **93 android-only**. Most reuse rows are the "no ffmpeg subprocess, in-process libav encoder" animation/recorder path, single-window/no-detach UI, and the save-in-place file semantics. The table also has 31 more rows: 25 CMake `if(ANDROID)` sites and 6 Android-only JNI sources (`KisAndroid*.cpp`/`.h`), split 9 reuse / 5 ios-twin / 17 android-only, for 286 rows in total (144 / 32 / 110). There are no `__ANDROID__` uses; every JNI/`<QtAndroid>` use is either inside a `Q_OS_ANDROID` block or in a file compiled only under CMake `ANDROID`.

| File:line | What it does | Class |
|---|---|---|
| krita/CMakeLists.txt:7 | Adds Qt5AndroidExtras include dirs for main.cc | android-only |
| krita/CMakeLists.txt:104 | Uses `splash-android.qrc` (HD JPEG splash) instead of `splash.qrc` | android-only |
| krita/CMakeLists.txt:196 | Builds `krita` as a SHARED library (Qt5 Android loads `libkrita.so`), links AndroidExtras | android-only |
| krita/CMakeLists.txt:235 | `NOT ANDROID`: builds the `krita_version` CLI executable; a command-line tool is pointless on mobile | reuse |
| krita/CMakeLists.txt:279 | Installs `kritamenu_android.action` (in-app-purchase actions) | android-only |
| krita/data/CMakeLists.txt:24 | Android installs `donation/` banners; non-Android installs `windowlayouts/` (multi-window layouts unsupported on mobile). Split it: the windowlayouts skip is reuse, donation is android-only | reuse |
| krita/data/bundles/CMakeLists.txt:8 | Leaves out the large `Krita_3_Default_Resources.bundle` on Android | reuse |
| krita/main.cc:58 | Includes `<QtAndroid>`, KisAndroidCrashHandler, KisAndroidUtils | android-only |
| krita/main.cc:161 | JNI exports: `saveState` (autosave all docs on pause + mark GL OK), `hasMainWindowLoaded`, `openFileFromIntent` (queue `fileOpenRequested`); also MAIN_EXPORT/MAIN_FN for the .so entry | ios-twin |
| krita/main.cc:219 | `KisAndroidUtils::performInitialSetup()`: installs the logcat handler and copies APK assets via JNI | ios-twin |
| krita/main.cc:282 | Requests WRITE_EXTERNAL_STORAGE at runtime, starts the native crash handler, sets FONTCONFIG_PATH (app root share/etc/fonts) and XDG_CACHE_HOME | ios-twin |
| krita/main.cc:320 | `Q_OS_LINUX && !ANDROID`: AppImage MLT/fontconfig env setup (Q_OS_LINUX is false on iOS anyway) | android-only |
| krita/main.cc:367 | `ALLOW_FALLBACK_LANGUAGES=false` because KF I18n catalog loading is very slow on Android (paired with kswitchlanguagedialog_p.cpp:35) | android-only |
| krita/main.cc:515 | `Q_OS_LINUX && !ANDROID` XDG_DATA_DIRS branch; iOS hits the generic `#else` (root/share) | android-only |
| krita/main.cc:572 | Falls back to `java.util.Locale.getDefault()` via JNI when QLocale gives "C" (Qt's Darwin locale backend works on iOS) | android-only |
| krita/main.cc:688 | `Qt::AA_DontUseNativeMenuBar` | reuse |
| krita/main.cc:759 | Sets MLT_REPOSITORY/MLT_DATA/MLT_PROFILES_PATH/MLT_PRESETS_PATH/MLT_PLUGIN_FILTER_STRING from Android app/home dirs | ios-twin |
| krita/main.cc:1015 | Loads translation `.qm` catalogs from `assets:/locale/...` | ios-twin |
| libs/global/CMakeLists.txt:58 | Adds KisAndroidCrashHandler/ExitInfo/LogHandler/Utils sources, unwindstack and AndroidExtras includes | ios-twin |
| libs/global/CMakeLists.txt:105 | Links kritaglobal to unwindstack, `log`, (Qt5) AndroidExtras | android-only |
| libs/global/KisAndroidCrashHandler.h:10 | `<jni.h>`; signal-based native crash handler (unwindstack) that writes `kritacrashlog.txt` | ios-twin |
| libs/global/KisAndroidExitInfo.cpp:6 | JNI: reads ActivityManager ApplicationExitInfo (last exit reason, LMK kills) | android-only |
| libs/global/KisAndroidLogHandler.cpp:12 | `#ifndef Q_OS_ANDROID #error`; Qt message handler that writes to `__android_log_write` | android-only |
| libs/global/KisAndroidUtils.cpp:12 | JNI helpers: Xiaomi detection, LMK-report support, JNI exception clearing, immersive fullscreen get/set, SAF-safe `copyFile`/`copyFileToTemporary` (fullscreen is the only part iOS needs a twin for) | ios-twin |
| libs/global/KisUsageLogger.cpp:36 | Includes KisAndroidExitInfo and `<QtAndroidExtras/QtAndroid>` | android-only |
| libs/global/KisUsageLogger.cpp:155 | Logs device manufacturer + model from `android.os.Build` via JNI | ios-twin |
| libs/global/KisUsageLogger.cpp:280 | Logs last Android exit reason (KisAndroidExitInfo) | android-only |
| libs/global/kis_config_notifier.cpp:78 | Notifier slots for the Android input workarounds (PageUp/Down and high-F-key mouse-button emulation, ignore historic tablet events) | android-only |
| libs/global/kis_config_notifier.h:45 | Declarations of the same notify slots and signals (also :63) | android-only |
| libs/koplugin/KisMimeDatabase.cpp:16 | `sanitizeSuffix()` helper | android-only |
| libs/koplugin/KisMimeDatabase.cpp:29 | Strips SAF "name.kra (1)" duplicate suffixes; an empty suffix defaults to `kra` | android-only |
| libs/koplugin/KisMimeDatabase.cpp:56 | Looks up the MIME type with basename + sanitized suffix | android-only |
| libs/koplugin/KoJsonTrader.cpp:52 | Extra `cdUp()` from applicationDirPath to find the plugin search root | ios-twin |
| libs/koplugin/KoJsonTrader.cpp:76 | Plugin dir is the ABI subdir (`arm64-v8a`/`armeabi-v7a`/`x86_64`/`x86`) | ios-twin |
| libs/koplugin/KoJsonTrader.cpp:145 | Plugin filename filter `lib_krita*` (NDK loading rules) | ios-twin |
| libs/resources/KoResourcePaths.cpp:145 | `getInstallationPrefix()` returns the internal AppDataLocation[1]; iOS currently falls into the `#else` (`applicationDirPath()/../`), which is wrong for an .app bundle | ios-twin |
| libs/resources/KoResourcePaths.cpp:700 | Doesn't append "/krita" to standard locations, which are already app-specific | reuse |
| libs/ui/CMakeLists.txt:2 | `-DQT_OPENGL_ES_3` (Qt doesn't set it for Android) + AndroidExtras includes. The ES3 define is the part to share | reuse |
| libs/ui/CMakeLists.txt:518 | Adds KisDonationManagementDialog/Widget and KisAndroidScaling sources | android-only |
| libs/ui/CMakeLists.txt:577 | Adds KisAndroidDonations, KisAndroidMediaEncoderRunnable, **KisLibavMediaEncoderRunnable, KisMediaEncoderFormatPreferencesDialog, KisMediaEncoderWrapper**. The bold part is the in-process libav encoder iOS needs. Split it | reuse |
| libs/ui/CMakeLists.txt:690 | Wraps the donation `.ui` files | android-only |
| libs/ui/CMakeLists.txt:760 | Qt private Gui includes for KisAndroidScaling (patched density adjustment) | android-only |
| libs/ui/CMakeLists.txt:807 | Links GLESv3, Qt Gui, AndroidExtras, LibAV. LibAV is shared; GLESv3 becomes OpenGLES.framework through Qt on iOS | reuse |
| libs/ui/KisAndroidDonations.cpp:9 | JNI to Play Billing / Java splash (setLoaded, setLoadingText, products, subscriptions) | android-only |
| libs/ui/KisAndroidScaling.cpp:16 | JNI and patched-Qt UI density scaling dialog | android-only |
| libs/ui/KisApplication.cpp:22 | Includes KisAndroidDonations.h | android-only |
| libs/ui/KisApplication.cpp:141 | Includes KisAndroidScaling.h | android-only |
| libs/ui/KisApplication.cpp:197 | Private members `androidDonations` / `androidScaling` | android-only |
| libs/ui/KisApplication.cpp:230 | `QT_QUICK_BACKEND=software` so QtQuick widgets don't stack behind dialogs (Android QPA bug; check on iOS) | reuse |
| libs/ui/KisApplication.cpp:253 | Defaults the widget style to Fusion (shared with Win/macOS) | reuse |
| libs/ui/KisApplication.cpp:446 | Resource DB (sqlite) always lives in writable AppDataLocation, not in the configurable resource folder | reuse |
| libs/ui/KisApplication.cpp:485 | `KisAndroidDonations::showDonationDialog(true)` at start | android-only |
| libs/ui/KisApplication.cpp:525 | Creates KisAndroidScaling | android-only |
| libs/ui/KisApplication.cpp:540 | `#ifndef`: doesn't show the Qt splash because the Java splash covers loading (iOS should keep the Qt splash) | android-only |
| libs/ui/KisApplication.cpp:641 | Tells the Java splash loading is done | android-only |
| libs/ui/KisApplication.cpp:881 | Forwards splash loading text to the Java splash | android-only |
| libs/ui/KisApplication.cpp:888 | `hideSplashScreen()` closes the Java splash | android-only |
| libs/ui/KisApplication.cpp:1336 | `androidDonations()` / `androidScaling()` accessors | android-only |
| libs/ui/KisApplication.h:100 | Declarations of those accessors | android-only |
| libs/ui/KisAsyncAnimationFramesSavingRenderer.cpp:19 | Includes KisAndroidUtils.h | android-only |
| libs/ui/KisAsyncAnimationFramesSavingRenderer.cpp:124 | Copies duplicate frames with `KisAndroidUtils::copyFile` (QFile::copy fails on SAF); QFile::copy works on iOS | android-only |
| libs/ui/KisAutoSaveRecoveryDialog.cpp:279 | Autosave location = `DocumentsLocation/krita-backup` (iOS currently gets `QDir::homePath()`, the container root, which isn't writable) | reuse |
| libs/ui/KisDocument.cpp:785 | Skips the `isWritable()` check; treats a 0-byte existing file (SAF placeholder) as not existing | android-only |
| libs/ui/KisDocument.cpp:811 | Backup files go to the autosave location, not next to the document ("may not be a directory") | reuse |
| libs/ui/KisDocument.cpp:1109 | `setReadWrite(true)` without asking QFileInfo (see the "ANDROID NOTES" comment at :742) | android-only |
| libs/ui/KisDocument.cpp:1910 | Autosave dir for `content://` docs is the autosave location. iOS needs the same thing keyed on "outside app container / security-scoped" | ios-twin |
| libs/ui/KisDocument.cpp:2019 | `setReadWrite(true)` after open (ANDROID NOTES) | android-only |
| libs/ui/KisImportExportManager.cpp:802 | Turns off QSaveFile (rename-over) on Win/macOS/Android. Needed on iOS too: you can't create sibling files next to security-scoped files | reuse |
| libs/ui/KisImportExportManager.cpp:855 | Saves via temp file, then opens the target `WriteOnly\|Truncate` and copies in BUFSIZ chunks with size check (overwrite in place, keeps the file identity) | reuse |
| libs/ui/KisImportExportManager.cpp:955 | "Also save as .kra" asks the user for a location (no sibling write permission) | reuse |
| libs/ui/KisLongPressEventFilter.cpp:20 | Includes `<QtAndroid>` | android-only |
| libs/ui/KisLongPressEventFilter.cpp:31 | Reads the long-press timeout from `MainActivity.getLongPressTimeout()` via JNI | android-only |
| libs/ui/KisLongPressEventFilter.cpp:86 | Uses that timeout instead of `QStyleHints::mousePressAndHoldInterval()` (iOS can use the hint or a fixed 500 ms) | android-only |
| libs/ui/KisLongPressEventFilter.h:47 | `m_longPressTimeout` member | android-only |
| libs/ui/KisMainWindow.cpp:101 | Includes donations, donation dialog, `<QtAndroid>`, KisAndroidUtils | android-only |
| libs/ui/KisMainWindow.cpp:167 | Includes KisAndroidScaling.h | android-only |
| libs/ui/KisMainWindow.cpp:244 | `flashWindowHackInProgress` member | android-only |
| libs/ui/KisMainWindow.cpp:269 | Donation/subscription/interface-scale action members; `#else` has toggleDetachCanvas/newWindow (harmless to keep) | android-only |
| libs/ui/KisMainWindow.cpp:387 | `setAnimated(false)`: dock/menu animations are slow and can crash | reuse |
| libs/ui/KisMainWindow.cpp:448 | `#ifndef`: no widget-style chooser menu | reuse |
| libs/ui/KisMainWindow.cpp:639 | Main window fixed to screen available size, orientation mask + `orientationChanged` hookup (reuse); scaling-change hookup and JNI `QtNative.setApplicationState` at :665 are android-only | reuse |
| libs/ui/KisMainWindow.cpp:1047 | `setCanvasDetached`: "Detach Canvas is unsupported" | reuse |
| libs/ui/KisMainWindow.cpp:1205 | Hides and re-shows the window after a document opens, to fix a repaint bug (skipped on Xiaomi) | android-only |
| libs/ui/KisMainWindow.cpp:1685 | Shows the pending donation-management dialog after load | android-only |
| libs/ui/KisMainWindow.cpp:1886 | `slotChangeInterfaceScale()` opens the Android scaling dialog | android-only |
| libs/ui/KisMainWindow.cpp:1918 | `slotShowDonationManagementDialog()` + `slotFlashWindowHack()` | android-only |
| libs/ui/KisMainWindow.cpp:2264 | `#ifndef`: no video import (needs an ffmpeg subprocess) | reuse |
| libs/ui/KisMainWindow.cpp:2445 | `viewFullscreen` calls `KisAndroidUtils::setFullScreen` (immersive mode) instead of window state | ios-twin |
| libs/ui/KisMainWindow.cpp:2719 | `#ifndef`: no "New Window" entry in the Window menu | reuse |
| libs/ui/KisMainWindow.cpp:2974 | `newWindow()` refuses a second main window | reuse |
| libs/ui/KisMainWindow.cpp:3098 | `#ifndef`: no `file_import_video_animation` action | reuse |
| libs/ui/KisMainWindow.cpp:3144 | `#ifndef`: no `view_detached_canvas` action | reuse |
| libs/ui/KisMainWindow.cpp:3172 | Creates manage_donations / manage_subscriptions / change_interface_scale actions. Its `#else` creates `view_newwindow`, which iOS must also skip, so split the guard | android-only |
| libs/ui/KisMainWindow.cpp:3279 | Saves window state using `KisAndroidUtils::isInFullScreen()` (JNI) | ios-twin |
| libs/ui/KisMainWindow.h:261 | Declarations of the donation slot and flash-hack slot | android-only |
| libs/ui/KisPlaybackEngineMLT.cpp:35 | Includes KisAndroidFileProxy.h | android-only |
| libs/ui/KisPlaybackEngineMLT.cpp:410 | Copies the audio file from a content URI to the cache dir before opening it in MLT | android-only |
| libs/ui/KisViewManager.cpp:981 | `canonicalPath()`: if the document dir isn't accessible, asks the user to pick a directory | reuse |
| libs/ui/KisViewManager.cpp:1236 | Closes expanded toolbar overflow popups before toggling canvas-only mode (crash workaround) | reuse |
| libs/ui/KisViewManager.cpp:1383 | `#ifndef`: reuses the toolbar list from :1236 | reuse |
| libs/ui/KisWelcomePageWidget.cpp:84 | Includes donations + painting headers for banners | android-only |
| libs/ui/KisWelcomePageWidget.cpp:187 | Calls `initDonations()` | android-only |
| libs/ui/KisWelcomePageWidget.cpp:197 | `#ifndef` (to :235) inside ENABLE_UPDATERS: no version updater. Without it iOS falls into the `#else` "always create updater for MacOS" | reuse |
| libs/ui/KisWelcomePageWidget.cpp:320 | Extra `QPushButton { padding: 10px }` for touch | reuse |
| libs/ui/KisWelcomePageWidget.cpp:800 | `initDonations()` implementation (supporter banner/badge) | android-only |
| libs/ui/KisWelcomePageWidget.h:83 | `slotUpdateDonationState()` declaration (also :113 `initDonations()`) | android-only |
| libs/ui/KisWindowLayoutResource.cpp:388 | Rejects workspaces with more than one window | reuse |
| libs/ui/animation/KisAndroidMediaEncoderRunnable.cpp:16 | JNI to the Java MediaCodec `VideoEncoder` (hardware encode) | android-only |
| libs/ui/animation/KisAnimationRender.cpp:27 | Includes QTemporaryDir / `<memory>` for the in-process encoder path | reuse |
| libs/ui/animation/KisAnimationRender.cpp:37 | `looksLikeMp4`/`looksLikeMatroska` match encoder format keys instead of MIME (also :46) | reuse |
| libs/ui/animation/KisAnimationRender.cpp:58 | Bails if no video file / frames dir was picked; frames go to a temp dir when encoding video | reuse |
| libs/ui/animation/KisAnimationRender.cpp:93 | Video type comes from `videoFormatKey` | reuse |
| libs/ui/animation/KisAnimationRender.cpp:146 | `#ifndef`: skips resolve/mkpath of the video output dir | reuse |
| libs/ui/animation/KisAnimationRender.cpp:178 | `#ifndef`: skips the test-open of the video file | reuse |
| libs/ui/animation/KisAnimationRender.cpp:210 | `shouldDeleteSequence=false` (temp frames handled separately) | reuse |
| libs/ui/animation/KisAnimationRender.cpp:235 | `#ifndef`: no ffmpeg palette temp files to clean | reuse |
| libs/ui/animation/KisAnimationRenderingOptions.cpp:14 | Includes QJsonDocument | reuse |
| libs/ui/animation/KisAnimationRenderingOptions.cpp:23 | `#ifndef`: the resolveAbsolute*Path helpers (desktop path model) | reuse |
| libs/ui/animation/KisAnimationRenderingOptions.cpp:61 | `renderMode()` is video-only or frames-only | reuse |
| libs/ui/animation/KisAnimationRenderingOptions.cpp:93 | `#ifndef`: no `delete_sequence` property | reuse |
| libs/ui/animation/KisAnimationRenderingOptions.cpp:104 | Serializes `video_format_key` + format preferences JSON instead of mimetype/ffmpeg path/options | reuse |
| libs/ui/animation/KisAnimationRenderingOptions.cpp:128 | Default `encode_video=true` | reuse |
| libs/ui/animation/KisAnimationRenderingOptions.cpp:134 | `#ifndef`: doesn't read `delete_sequence` | reuse |
| libs/ui/animation/KisAnimationRenderingOptions.cpp:145 | Deserializes format key + preferences | reuse |
| libs/ui/animation/KisAnimationRenderingOptions.h:21 | `videoFormatKey` / `videoFormatPreferencesJson` members vs `videoMimeType` | reuse |
| libs/ui/animation/KisAnimationRenderingOptions.h:41 | `#ifndef`: shouldDeleteSequence, ffmpegPath, customFFMpegOptions, resolve* helpers, RENDER_FRAMES_AND_VIDEO (also :47, :56, :61, :74) | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:47 | Includes the MediaEncoder prefs dialog + wrapper instead of VideoExportOptionsDialog/KisFFMpegWrapper | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:81 | Images/Video become exclusive radio buttons (touch-friendly layout) | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:138 | Fills the format combo from `KisMediaEncoderWrapper::getSupportedFormats()` ("No ffmpeg here") | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:153 | `#ifndef`: video filename / ffmpeg location requesters | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:164 | Connects the button group instead of the checkboxes | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:179 | `#ifndef`: ffmpeg path signal | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:211 | `#ifndef`: ffmpeg location discovery | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:263 | Start dir = document path only (no video filename field) | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:277 | Same, for the no-previous-options case | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:303 | Last video type = `videoFormatKey` | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:316 | Restores the Images/Video radio state | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:329 | `#ifndef`: ffmpeg encoder option defaults | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:380 | `wantImageSequenceExport`/`wantVideoExport` from radio buttons (also :389) | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:396 | `#ifndef`: `getDefaultVideoEncoderOptions` (ffmpeg) | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:426 | `#ifndef`: ffmpeg MIME list / encoder filtering | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:507 | Loads/saves video format preferences as JSON | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:543 | `looksLikeGif` by `:gif` key | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:552 | `supportsAudio` asks the encoder format | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:575 | `#ifndef`: `setFFmpegPath` | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:681 | `#ifndef`: ffmpeg version warning | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:732 | `#ifndef`: `defaultVideoFileName` | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:788 | Render options open KisMediaEncoderPreferencesDialog | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:829 | `#ifndef`: custom ffmpeg options / HDR flag | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:859 | `#ifndef`: PNG HDR handling | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:873 | `#ifndef`: read HDR from the frame config | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:896 | `getEncoderOptions` builds options for the in-process encoder | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:948 | `#ifndef`: force HDR PNG settings | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:963 | `#ifndef`: `validateFFmpeg` | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:984 | `#ifndef`: `slotButtonClicked` overwrite/filename checks | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:1013 | On accept, asks for the output file/dir via KoFileDialog (save picker) | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.cpp:1067 | Switches the stacked Images/Video page | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.h:16 | Includes QVariantMap | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.h:56 | `#ifndef`: ffmpeg-only slots/enums/helpers (also :71, :81, :88, :104, :118) | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.h:124 | Format-preference load/save declarations | reuse |
| libs/ui/animation/KisDlgAnimationRenderer.h:141 | Members: button group, image dir, video filename, format prefs (vs ffmpeg members) | reuse |
| libs/ui/animation/KisMediaEncoderWrapper.cpp:22 | Includes KisAndroidMediaEncoderRunnable.h | android-only |
| libs/ui/animation/KisMediaEncoderWrapper.cpp:304 | Adds MediaCodec formats before the libav formats | android-only |
| libs/ui/animation/KisMediaEncoderWrapper.cpp:326 | Tries the MediaCodec runnable before libav (iOS would just use libav; a VideoToolbox runnable could be added later) | android-only |
| libs/ui/animation/KisVideoSaver.cpp:32 | Includes the wrapper + KisAndroidUtils instead of KisFFMpegWrapper | reuse |
| libs/ui/animation/KisVideoSaver.cpp:62 | Encodes through KisMediaEncoderWrapper. Audio is copied to temp with `KisAndroidUtils::copyFileToTemporary`; use QFile on iOS | reuse |
| libs/ui/dialogs/KisAsyncAnimationFramesSaveDialog.cpp:79 | Splits the path by hand because QFileInfo can't parse content URIs | android-only |
| libs/ui/dialogs/KisAsyncAnimationFramesSaveDialog.cpp:102 | `#ifndef`: doesn't `mkpath` the output dir (SAF forbids it) | android-only |
| libs/ui/dialogs/kis_dlg_preferences.cc:541 | Native file dialogs on by default | reuse |
| libs/ui/dialogs/kis_dlg_preferences.cc:604 | Resource folder is a combobox of AppDataLocation entries instead of a free path requester | reuse |
| libs/ui/dialogs/kis_dlg_preferences.cc:827 | "Use native file dialog" checkbox defaults to checked | reuse |
| libs/ui/dialogs/kis_dlg_preferences.cc:3140 | Saves the resource folder from that combobox | reuse |
| libs/ui/input/kis_input_manager.cpp:568 | `#ifndef`: Enter/Leave events don't drive the shortcut matcher (no hover cursor on touch/stylus) | reuse |
| libs/ui/input/kis_input_manager_p.cpp:63 | Xiaomi multi-finger-cancel workaround enabled | android-only |
| libs/ui/input/kis_shortcut_matcher.cpp:201 | `actionsSuppressed()` ignores `cursorEntered` (pairs with :568 above) | reuse |
| libs/ui/kis_config.cc:51 | Includes KisAndroidUtils.h | android-only |
| libs/ui/kis_config.cc:1614 | Default pressure curve `0,0;0.7,1;` on Xiaomi. The comment itself says iPads need their own (≈`0,0;0.5,1.0;`) | ios-twin |
| libs/ui/kis_config.cc:1683 | Getters/setters for the Android input workarounds + androidScaling* settings | android-only |
| libs/ui/kis_config.cc:2471 | Default kinetic-scroll gesture = left button/touch (1) instead of middle (2) | reuse |
| libs/ui/kis_config.cc:2999 | Long press enabled by default | reuse |
| libs/ui/kis_config.h:453 | Declarations for :1683 above | android-only |
| libs/ui/kis_file_layer.cpp:176 | File-layer path used as-is (URI) instead of resolving relative to the document dir | android-only |
| libs/ui/kis_layer_manager.cc:380 | Layer dialog uses `Qt::Dialog` without `Qt::Tool` (Tool windows don't get keyboard focus) | reuse |
| libs/ui/kis_splash_screen.cpp:140 | Splash image `:/splash/hd.jpg` (from splash-android.qrc) | android-only |
| libs/ui/opengl/KisOpenGLContextSwitchLock.cpp:18 | Always uses the strict GL context-switch lock (shared with macOS) | reuse |
| libs/ui/opengl/kis_opengl.cpp:920 | `#ifndef`: doesn't probe the Desktop GL renderer (GLES only) | reuse |
| libs/ui/utils/KisRecentDocumentsModelWrapper.cpp:48 | Recent-doc tooltip = `toLocalFile()`; the generic fallback is fine on iOS | android-only |
| libs/ui/widgets/KisGrabKeyboardFocusRecoveryWorkaround.cpp:21 | `LINUX && !ANDROID`: X11 focus-recovery dummy widget (also :43); Q_OS_LINUX is false on iOS | android-only |
| libs/widgetutils/CMakeLists.txt:148 | Links AndroidExtras | android-only |
| libs/widgetutils/KisKineticScroller.cpp:14 | Includes `<QtAndroid>` | android-only |
| libs/widgetutils/KisKineticScroller.cpp:110 | Caps the press delay with the JNI long-press timeout (falls back to QStyleHints elsewhere) | android-only |
| libs/widgetutils/KisKineticScroller.cpp:145 | Default `KineticScrollingGesture=1` (touch) | reuse |
| libs/widgetutils/KisPopupButton.cpp:43 | `hide()` before `destroy()` when detaching a popup (window-stack corruption; shared with macOS; check on iOS) | reuse |
| libs/widgetutils/KisRecentFilesManager_p.h:42 | Reads recent entries with `readEntry` (URIs) instead of `readPathEntry`. iOS needs persistent security-scoped bookmarks instead | ios-twin |
| libs/widgetutils/KisRecentFilesManager_p.h:108 | Writes recent entries as URI strings (same concern) | ios-twin |
| libs/widgetutils/KoFileDialog.cpp:156 | Native dialog by default | reuse |
| libs/widgetutils/KoFileDialog.cpp:217 | `#ifndef`: no name filters on the native picker (MIME-based SAF); iOS needs UTType filtering | ios-twin |
| libs/widgetutils/KoFileDialog.cpp:266 | Save: QInputDialog list asks for the format first, then sets the picker title to "name.ext". iOS needs an export/save picker (UIDocumentPicker forExporting) | ios-twin |
| libs/widgetutils/KoFileDialog.cpp:311 | `#ifndef`: skips suffix validation/append after the picker returns | ios-twin |
| libs/widgetutils/KoFileDialog.cpp:358 | Doesn't append an extension to the returned URL (no permission to rename; shared with macOS) | reuse |
| libs/widgetutils/KoFileDialog.cpp:594 | `#ifndef`: no `setDefaultSuffix` (Qt 5.12 Android bug) | android-only |
| libs/widgetutils/kis_cursor_cache.cpp:25 | Loads cursors unscaled (large cursors glitch) | android-only |
| libs/widgetutils/xmlgui/kkeysequencewidget.cpp:948 | Clears the released modifier from the key-release modifiers (Android key-event quirk) | android-only |
| libs/widgetutils/xmlgui/kmainwindow.cpp:591 | Forces MenuBar "Enabled" so a stale config can't hide the non-native menubar | reuse |
| libs/widgetutils/xmlgui/kswitchlanguagedialog_p.cpp:35 | `ALLOW_FALLBACK_LANGUAGES=false` (pairs with main.cc:367) | android-only |
| plugins/CMakeLists.txt:19 | `NOT ANDROID`: platforms (xcb/wayland, already gated on HAVE_X11/HAVE_WAYLAND) | android-only |
| plugins/dockers/CMakeLists.txt:2 | No smallcolorselector (KisGLImageWidget) on Android | reuse |
| plugins/dockers/CMakeLists.txt:17 | No OCIO LUT docker on Android | reuse |
| plugins/dockers/compositiondocker/compositiondocker_dock.cpp:48 | Includes KisAndroidMediaEncoderRunnable.h only to get KisMediaEncoderWrapper (include the wrapper header directly) | reuse |
| plugins/dockers/compositiondocker/compositiondocker_dock.cpp:345 | Composition animation export resolves the encoder format (falls back to the first one) | reuse |
| plugins/dockers/compositiondocker/compositiondocker_dock.cpp:389 | Video extension from the encoder format | reuse |
| plugins/dockers/recorder/CMakeLists.txt:27 | `NOT ANDROID`: ffmpeg profile settings dialog | reuse |
| plugins/dockers/recorder/recorder_config.cpp:45 | Default snapshot dir is empty ("no user-visible directory"). iOS has one: app Documents is visible in Files | ios-twin |
| plugins/dockers/recorder/recorder_config.cpp:162 | `defaultInternalSnapshotDirectory()` (legacy migration) | android-only |
| plugins/dockers/recorder/recorder_config.h:57 | Declaration of the above | android-only |
| plugins/dockers/recorder/recorder_export.cpp:35 | Includes wrapper/prefs dialog/KisAndroidUtils instead of KisFFMpegWrapper/profile settings | reuse |
| plugins/dockers/recorder/recorder_export.cpp:54 | `using Exporter = KisMediaEncoderWrapper` | reuse |
| plugins/dockers/recorder/recorder_export.cpp:88 | `#ifndef`: ffmpeg check | reuse |
| plugins/dockers/recorder/recorder_export.cpp:125 | Profile combo filled with encoder formats | reuse |
| plugins/dockers/recorder/recorder_export.cpp:167 | Caches the input frame list (slow entryList) | reuse |
| plugins/dockers/recorder/recorder_export.cpp:179 | `#ifndef`: `updateVideoFilePath` | reuse |
| plugins/dockers/recorder/recorder_export.cpp:243 | `#ifndef`: `splitCommand` (ffmpeg args) | reuse |
| plugins/dockers/recorder/recorder_export.cpp:289 | `#ifndef`: ffmpeg preprocessor pass | reuse |
| plugins/dockers/recorder/recorder_export.cpp:304 | Builds KisMediaEncoderWrapperSettings | reuse |
| plugins/dockers/recorder/recorder_export.cpp:345 | `#ifndef`: `applyVariables` (ffmpeg templates) | reuse |
| plugins/dockers/recorder/recorder_export.cpp:457 | `desktopServicesOpenPath` clears JNI exceptions around `QDesktopServices::openUrl` | android-only |
| plugins/dockers/recorder/recorder_export.cpp:476 | Hides ffmpeg path / export path / show-in-folder widgets | reuse |
| plugins/dockers/recorder/recorder_export.cpp:529 | `#ifndef`: connects for those widgets | reuse |
| plugins/dockers/recorder/recorder_export.cpp:596 | `#ifndef`: `checkExporter` / `updateVideoFilePath` on show | reuse |
| plugins/dockers/recorder/recorder_export.cpp:728 | `#ifndef`: browse-ffmpeg slot | reuse |
| plugins/dockers/recorder/recorder_export.cpp:745 | Profile index change stores the format key | reuse |
| plugins/dockers/recorder/recorder_export.cpp:758 | Edit profile opens KisMediaEncoderPreferencesDialog | reuse |
| plugins/dockers/recorder/recorder_export.cpp:785 | `#ifndef`: video path edited slot | reuse |
| plugins/dockers/recorder/recorder_export.cpp:795 | `#ifndef`: browse-export slot | reuse |
| plugins/dockers/recorder/recorder_export.cpp:816 | Export asks for the output file via the picker | reuse |
| plugins/dockers/recorder/recorder_export.cpp:883 | `#ifndef`: show-in-folder slot | reuse |
| plugins/dockers/recorder/recorder_export.cpp:923 | `#ifndef`: eventFilter for the path edit | reuse |
| plugins/dockers/recorder/recorder_export.h:45 | `#ifndef`: ffmpeg/path slots + eventFilter declarations (also :50, :64, :71) | reuse |
| plugins/dockers/recorder/recorder_export_config.cpp:15 | Includes QJsonDocument | reuse |
| plugins/dockers/recorder/recorder_export_config.cpp:22 | `#ifndef`: ffmpeg path / video dir keys | reuse |
| plugins/dockers/recorder/recorder_export_config.cpp:36 | selectedformat/formatpreferences keys vs ffmpeg profiles | reuse |
| plugins/dockers/recorder/recorder_export_config.cpp:212 | Loads the format key + prefs into settings | reuse |
| plugins/dockers/recorder/recorder_export_config.cpp:330 | selectedFormat / formatPreferences accessors | reuse |
| plugins/dockers/recorder/recorder_export_config.h:56 | Declarations of those accessors vs profile accessors | reuse |
| plugins/dockers/recorder/recorder_export_config.h:86 | `#ifndef`: RecorderProfile comparison operators | reuse |
| plugins/dockers/recorder/recorder_export_settings.h:17 | QVariantMap vs the `RecorderProfile` struct | reuse |
| plugins/dockers/recorder/recorder_export_settings.h:41 | Settings: selectedFormat/formatPreferences vs ffmpeg profile fields | reuse |
| plugins/dockers/recorder/recorder_export_settings.h:60 | `inputFilePaths` vs `videoFileName` | reuse |
| plugins/dockers/recorder/recorderdocker_dock.cpp:40 | Includes for the internal-snapshot mover | android-only |
| plugins/dockers/recorder/recorderdocker_dock.cpp:109 | `internalMoveInProgress` flag | android-only |
| plugins/dockers/recorder/recorderdocker_dock.cpp:153 | Calls `fixInternalSnapshotDirectory()` | android-only |
| plugins/dockers/recorder/recorderdocker_dock.cpp:405 | `fixInternalSnapshotDirectory()` clears the legacy internal path | android-only |
| plugins/dockers/recorder/recorderdocker_dock.cpp:706 | `#ifndef`: no export videoFileName from the document caption | reuse |
| plugins/dockers/recorder/recorderdocker_dock.cpp:886 | Moves legacy internal snapshots in the background | android-only |
| plugins/dockers/recorder/recorderdocker_dock.h:14 | Includes for the mover (also :69 slots, :81 `RecorderDockerInternalSnapshotsMover` class) | android-only |
| plugins/extensions/CMakeLists.txt:21 | Builds the `spensettings` plugin (maps Samsung S-Pen button gestures to actions). iOS twin: Apple Pencil double-tap/squeeze via UIPencilInteraction | ios-twin |
| plugins/extensions/buginfo/CMakeLists.txt:8 | Adds DlgAndroidLogcatDumper.cpp | android-only |
| plugins/extensions/buginfo/CMakeLists.txt:12 | `WIN32 OR ANDROID`: DlgCrashLog.cpp | ios-twin |
| plugins/extensions/buginfo/CMakeLists.txt:25 | Links (Qt5) AndroidExtras | android-only |
| plugins/extensions/buginfo/DlgCrashLog.cpp:24 | Crash log path = AppDataLocation/kritacrashlog.txt | ios-twin |
| plugins/extensions/buginfo/buginfo.cpp:20 | Includes DlgAndroidLogcatDumper.h | android-only |
| plugins/extensions/buginfo/buginfo.cpp:24 | `ANDROID \|\| WIN`: includes DlgCrashLog.h | ios-twin |
| plugins/extensions/buginfo/buginfo.cpp:48 | Creates the "logcatdump" action | android-only |
| plugins/extensions/buginfo/buginfo.cpp:53 | `ANDROID \|\| WIN`: creates the "crashlog" action | ios-twin |
| plugins/extensions/buginfo/buginfo.cpp:76 | `slotDumpLogcat()` | android-only |
| plugins/extensions/buginfo/buginfo.cpp:84 | `ANDROID \|\| WIN`: `slotCrashLog()` | ios-twin |
| plugins/extensions/buginfo/buginfo.h:28 | `slotDumpLogcat` declaration | android-only |
| plugins/extensions/buginfo/buginfo.h:32 | `WIN \|\| ANDROID`: `slotCrashLog` declaration | ios-twin |
| plugins/extensions/buginfo/dlg_buginfo.cpp:30 | Includes `<QtAndroid>` | android-only |
| plugins/extensions/buginfo/dlg_buginfo.cpp:130 | Adds device manufacturer/model (JNI `android.os.Build`) to the bug info | ios-twin |
| plugins/extensions/resourcemanager/CMakeLists.txt:34 | Adds the KisSupporterBundles* (Play-billing supporter bundles) sources | android-only |
| plugins/extensions/resourcemanager/DlgResourceManager.cpp:59 | Hides "Open Resource Folder" (opening a dir crashes; no ContentProvider) | reuse |
| plugins/extensions/resourcemanager/dlg_bundle_manager.cpp:40 | Includes KisSupporterBundlesDialog.h | android-only |
| plugins/extensions/resourcemanager/dlg_bundle_manager.cpp:159 | "Support" button opens supporter bundles; hidden elsewhere | android-only |
| plugins/extensions/resourcemanager/dlg_bundle_manager.cpp:331 | `slotShowSupporterBundlesDialog()` | android-only |
| plugins/extensions/resourcemanager/dlg_bundle_manager.h:62 | Declaration of the above | android-only |
| plugins/extensions/resourcemanager/resourcemanager.cpp:23 | Includes KisSupporterBundlesDialog.h | android-only |
| plugins/extensions/resourcemanager/resourcemanager.cpp:49 | "Get More Resources..." action | android-only |
| plugins/extensions/resourcemanager/resourcemanager.cpp:73 | `slotManageSupporterBundles()` | android-only |
| plugins/extensions/resourcemanager/resourcemanager.h:31 | Declaration of the above | android-only |
| plugins/impex/libkra/kis_kra_loader.cpp:1137 | File-layer source used as-is (URI), not resolved against the .kra dir | android-only |
| plugins/impex/libkra/kis_kra_savexml_visitor.cpp:88 | File-layer `source` saved absolute/URI instead of relative | android-only |
| plugins/tools/svgtexttool/SvgTextCursor.cpp:47 | Includes config-qt-patches-present.h | android-only |
| plugins/tools/svgtexttool/SvgTextCursor.cpp:1050 | `Qt::ImPlatformData` returns the patched `ANDROID_INPUT_PLATFORM_DATA_SOFT_INPUT_ADJUST_NOTHING` so the soft keyboard doesn't pan the window. Qt iOS also scrolls the view to the cursor and needs its own suppression | ios-twin |
| plugins/tools/svgtexttool/SvgTextTool.cpp:83 | Includes QMenuBar | reuse |
| plugins/tools/svgtexttool/SvgTextTool.cpp:326 | Text editor window is `Qt::Dialog` with a non-native menubar | reuse |

Not tabulated: `libs/ui/KisAndroidFileProxy.cpp` (copies a content URI to the cache; it is always compiled via libs/ui/CMakeLists.txt:497 but only used by KisPlaybackEngineMLT.cpp:410), and the un-guarded `libs/widgetutils/kis_slider_spin_box_p.h:583` (blocks `ImEnabled` to suppress Android selection handles; generic code that is harmless on iOS).

### Darwin hazards

> **Status:** `kis_input_manager.cpp:684`, `KisInputEventsEater.cpp:271` and `LcmsEnginePlugin.cpp:98` are fixed in `45bb0b2`. The CMake hazards are handled by the `MACOS` variable (section 8, step 8); the `ok` rows need nothing.

No `Q_OS_IOS` or `Q_OS_DARWIN` is used anywhere under libs/, krita/ or plugins/. The 91 `Q_OS_MACOS` sites are all correctly false on iOS, so they are "ok" and not listed one by one. The hazards are the `Q_OS_MAC`/`__APPLE__` sites below, plus CMake `APPLE` (CMake sets `APPLE` for iOS too).

| File:line | What it does | Class |
|---|---|---|
| krita/CMakeLists.txt:17 | `NOT APPLE` icon glob; the APPLE branch runs `xcrun actool` on `krita.icon` into `Assets.car`/`krita.icns` (macOS asset catalog) | hazard |
| krita/CMakeLists.txt:80 | `elseif(APPLE)`: macOS icon packaging (MACOSX_PACKAGE_LOCATION Resources / icns) | hazard |
| krita/CMakeLists.txt:221 | macOS bundle props: `Info.plist.template`, `@loader_path/../Frameworks` rpaths, bundle id. iOS needs an iOS Info.plist and flat bundle layout | hazard |
| krita/CMakeLists.txt:244 | (inside `NOT ANDROID`) macOS rpath for the `krita_version` CLI | hazard |
| krita/CMakeLists.txt:253 | Copies `.icns` document icons into Resources | hazard |
| krita/integration/3rdparty/ioapi.c:19 | `unix \|\| __APPLE__`: includes `<unistd.h>` | ok |
| krita/integration/CMakeLists.txt:1 | `if(APPLE)`: xcodebuild of macOS Spotlight importer / QuickLook thumbnailer+preview appex | hazard |
| krita/main.cc:552 | `Q_OS_MAC`: `LANG=<locale>.UTF-8` (Python nl_langinfo fix) | ok |
| krita/main.cc:622 | `Q_OS_MAC`: only the first UI language is set, LANG/LANGUAGE get `.UTF-8`; this bypasses the ALLOW_FALLBACK_LANGUAGES logic | ok |
| libs/CMakeLists.txt:2 | `if(APPLE) add_subdirectory(macosutils)`: links AppKit/Security; KisMacosSecurityBookmarkManager/Entitlements/SystemProber are macOS APIs (useful reference for iOS bookmarks) | hazard |
| libs/flake/CMakeLists.txt:18 | `APPLE` sets DISABLE_CLIP_MASK_PAINTER_ON_MACOS (generic, non-SIMD clip-mask applicator) | ok |
| libs/flake/tests/CMakeLists.txt:78 | Test targets `MACOSX_BUNDLE ON` | ok |
| libs/global/CMakeLists.txt:113 | Links kritaglobal to kritamacosutils | hazard |
| libs/image/CMakeLists.txt:407 | Links kritaimage to kritamacosutils | hazard |
| libs/image/tests/CMakeLists.txt:159 | Test targets `MACOSX_BUNDLE` / `macos_test_fixrpath` | ok |
| libs/ui/CMakeLists.txt:15 | `find_library(AppKit)` | hazard |
| libs/ui/CMakeLists.txt:569 | Compiles `osx.mm` and `input/kis_extended_modifiers_mapper_osx.mm` (both `#import <AppKit/AppKit.h>`) | hazard |
| libs/ui/CMakeLists.txt:820 | Links kritaui to kritamacosutils, Foundation, AppKit | hazard |
| libs/ui/CMakeLists.txt:853 | Installs `osx.stylesheet` | hazard |
| libs/ui/input/KisInputEventsEater.cpp:271 | `#ifndef Q_OS_MAC`: on iOS synthesized (touch/pencil→mouse) events are **not** eaten, while the neighbouring `Q_OS_MACOS` guards (:260, :277) assume they are. Expect doubled input | hazard |
| libs/ui/input/kis_input_manager.cpp:684 | `#ifdef Q_OS_MAC` opens an `if {...} else {` whose closing `}` is under `#ifdef Q_OS_MACOS` at :718, so the braces don't balance on iOS and **the build breaks**. The trackpad-touch logic is macOS-only anyway | hazard |
| libs/ui/input/kis_shortcut_configuration.cpp:376 | `Q_OS_MAC`: modifier names via `QKeySequence::NativeText` symbols (cosmetic; fine with iPad hardware keyboards) | ok |
| libs/ui/thememanager.cpp:51 | `__APPLE__`: includes `<QStyle>` | ok |
| libs/ui/thememanager.cpp:239 | `Q_OS_MAC`: adds a "System" theme menu entry (system palette; check on iOS) | ok |
| libs/widgetutils/CMakeLists.txt:139 | Foundation + macosutils include/link for kritawidgetutils | hazard |
| libs/widgetutils/xmlgui/kkeysequencewidget.cpp:559 | `Q_OS_MAC`: Alt-before-Ctrl modifier display order | ok |
| plugins/color/lcms2engine/LcmsEnginePlugin.cpp:98 | `Q_OS_MAC`: scans `~/Library/ColorSync/Profiles`, `/System/Library/ColorSync/Profiles`, `/Library/ColorSync/Profiles` (harmless but dead or sandbox-denied paths on iOS; switch to `Q_OS_MACOS`) | hazard |
| plugins/dockers/lut/kis_context_thread_locale.h:8 | `__APPLE__`: `<xlocale.h>` (present on iOS) | ok |
| plugins/dockers/lut/ocio_display_filter_vfx2021.cpp:357 | `Q_OS_MAC && QT_OPENGL_3_2`: GL 3.2 core functions (also :363). Never defined in an iOS GLES build | ok |
| plugins/extensions/pykrita/kritarunner/CMakeLists.txt:45 | macOS rpath for the `kritarunner` CLI (shouldn't be built on mobile) | hazard |
| plugins/extensions/pykrita/plugin/utilities.cpp:240 | `UNIX && !Q_OS_MAC`: skips dlopen of libpython (iOS would need a static Python anyway) | ok |
| plugins/extensions/pykrita/plugin/utilities.cpp:309 | `Q_OS_MAC`: "running in bundle" if the app root contains `krita.app`, which selects the macOS Python layout | hazard |
| plugins/extensions/pykrita/plugin/utilities.cpp:382 | `Q_OS_MAC`: macOS `.dylib` Python library naming | hazard |
| plugins/extensions/pykrita/plugin/utilities.cpp:389 | `Q_OS_MAC`: system-Python fallback with `Py_GetPath()` + macOS site-packages/PyQt paths (closes at :413) | hazard |
| plugins/impex/heif/tests/CMakeLists.txt:1 | HEIF test marked broken on APPLE | ok |

Related non-Darwin gap: Android silently gets several things through `Q_OS_LINUX` (which Qt defines on Android) that iOS will not get. Examples: `KisImageConfig::totalRAM()` (`libs/image/kis_image_config.cpp:411` sysinfo; iOS falls back to 1000 MiB, so use `sysctl(HW_MEMSIZE)`/`os_proc_available_memory()`) and the GL fence-sync loader (`libs/ui/opengl/KisOpenGLSync.cpp:55`). There are 22 more `Q_OS_LINUX` lines (not counting the `&& !Q_OS_ANDROID` ones above); audit them as implicit Android sites.

### Suggested approach

- Add one shared macro in a header everything already includes, for example `libs/global/kis_global.h` (or a new `libs/global/KisPlatform.h` included from it): `#if defined(Q_OS_ANDROID) || defined(Q_OS_IOS)` → `#define KRITA_MOBILE 1`. Mirror it in CMake as `KRITA_MOBILE = ANDROID OR IOS` (`CMAKE_SYSTEM_NAME STREQUAL "iOS"`). Mechanically switch the **reuse** rows to `KRITA_MOBILE`. Most of them sit in the no-ffmpeg animation/recorder path, the single-window UI, and the file-saving semantics.
- Make the in-process encoder stack cross-platform first. In `libs/ui/CMakeLists.txt:577`, build `KisMediaEncoderWrapper`, `KisLibavMediaEncoderRunnable` and `KisMediaEncoderFormatPreferencesDialog` under `KRITA_MOBILE` (or `TARGET LibAV`), and keep `KisAndroidMediaEncoderRunnable` and the `KisMediaEncoderWrapper.cpp:304/:326` hooks Android-only. That alone turns about 100 `Q_OS_ANDROID` rows into plain mobile rows.
- Introduce a platform-neutral `KisMobileUtils` namespace (in `libs/global/`) that dispatches to `KisAndroidUtils` or a new `KisIosUtils.mm`. It would cover fullscreen get/set, device model string, initial setup/log handler, crash-log path, and app-lifecycle autosave (main.cc:161 `saveState` → `applicationWillResignActive`/`QGuiApplication::applicationStateChanged`). This covers most **ios-twin** rows without spreading `#ifdef`s.
- Treat file access as the main iOS twin: native UIDocumentPicker open/export (KoFileDialog.cpp:217/:266/:311), security-scoped bookmarks for recents (KisRecentFilesManager_p.h:42/:108; `libs/macosutils/KisMacosSecurityBookmarkManager.mm` is the closest template), and an "outside app container" predicate replacing `startsWith("content://")` (KisDocument.cpp:1910). Resource/plugin/translation/MLT paths should resolve inside the .app bundle (KoResourcePaths.cpp:145, KoJsonTrader.cpp:52/:76/:145, main.cc:759/:1015). Plugins will probably have to be static.
- Fix the Darwin hazards before the first compile. Change `Q_OS_MAC` to `Q_OS_MACOS` at kis_input_manager.cpp:684 (build break) and KisInputEventsEater.cpp:271, and preferably at LcmsEnginePlugin.cpp:98 and pykrita utilities.cpp. In CMake, replace `APPLE` with `APPLE AND NOT IOS` (or a `MACOS` variable) for macosutils, AppKit, `osx.mm`, integration, the bundle/plist/icon blocks and the CLI tools.
- Leave **android-only** rows untouched (donations/Play billing, KisAndroidScaling, Xiaomi workarounds, SAF filename/QFileInfo hacks, legacy recorder migration, logcat). Where a guard mixes kinds (KisMainWindow.cpp:639/:3172, krita/data/CMakeLists.txt:24, libs/ui/CMakeLists.txt:577/:807), split it into a `KRITA_MOBILE` part and a `Q_OS_ANDROID` part.

## 2. Android build configuration

### 2.1 How a CI Android build is driven
1. `K:build-tools/ci-scripts/android.yml:1-61` (`.android-base` job). It clones `krita-deps-management` (master) and `krita-ci-utilities`. It rewrites `.kde-ci.yml` with the dependency list (`:52-53`, via `D:tools/generate-deps-file.py:17-40`, which **keeps** Krita's `Options` block). It then runs `run-ci-build.py --platform Android/$KDECI_ANDROID_ABI/Qt5/Shared --only-build` (`:54`) and `build-android-package.py` (`:55`).
2. CMake is invoked by `CIU:run-ci-build.py:350-437`. That script adds `CMAKE_BUILD_TYPE`, `BUILD_TESTING` from `Options`, the `.kde-ci.yml` `cmake-options`, and then appends `KDECI_EXTRA_CMAKE_ARGS` at `:436-437`, so the extra args win. The toolchain comes from the `CMAKE_TOOLCHAIN_FILE` environment variable (`android.yml:19`). ECM's own Android toolchain is skipped (`KDECI_SKIP_ECM_ANDROID_TOOLCHAIN: True`, `android.yml:15`; handled at `CIU:run-ci-build.py:62-66,395`).
3. The toolchain chain is `D:tools/android-toolchain-krita.cmake` → `D:tools/android-toolchain.cmake` → `$NDK/build/cmake/android.toolchain.cmake`.

### 2.2 CMake options, cache vars and feature changes on Android, with proposed iOS defaults

| # | Setting / behaviour | Android value | Where set | Proposed iOS default |
|---|---|---|---|---|
| 1 | Qt major | Qt5 only. No Qt6 Android CI: no `DEPS_QT6_*_ANDROID` variables, while Windows, Linux and macOS have Qt6 jobs. | `K:.gitlab-ci.yml:14-25`; `K:android.yml:54` (`.../Qt5/Shared`) | Decide in §7. Recommendation: Qt6 (`-DBUILD_WITH_QT6=ON -DALLOW_UNSTABLE=QT6`, `K:CMakeLists.txt:14,369-381`). Note that the comment at `K:CMakeLists.txt:13` says "set QT_MAJOR_VERSION" but the real switch is `BUILD_WITH_QT6`. |
| 2 | `CMAKE_BUILD_TYPE` | `Release` | `K:android.yml:11` → `CIU:run-ci-build.py:354` | `RelWithDebInfo` while porting, `Release` later |
| 3 | `HIDE_SAFE_ASSERTS` | `OFF` for debug/nightly, `ON` for release. Default is `ON`. | `K:android.yml:21,73,84`; default `K:CMakeLists.txt:316` | `OFF` during bring-up, `ON` for daily use |
| 4 | `BUILD_TESTING` | `ON` for debug/nightly, `OFF` for release. Tests are never run on Android. | `K:android.yml:22,74,85`; `CIU:run-ci-build.py:84-85` | `OFF`. Tests can't run on device through ctest. |
| 5 | `KRITA_ENABLE_PCH=OFF`, `FOUNDATION_BUILD=ON` | Applied (shared `Options` for all platforms) | `K:.kde-ci.yml:12`; options defined at `K:CMakeLists.txt:331,348` | Same. `FOUNDATION_BUILD=ON` packages the bundled extras. |
| 6 | `ENABLE_UPDATERS` | Default `ON`, not overridden | `K:CMakeLists.txt:344` | `OFF` (no update channel for a sideloaded app) |
| 7 | `ANDROID_ENABLE_STDIO_FORWARDING` | Option, default `OFF`. Forwards qDebug/stdio to logcat. | `K:CMakeLists.txt:353-357` | N/A. iOS stdout/os_log reaches the Xcode console. |
| 8 | Toolchain cache vars | `ANDROID_PLATFORM=android-24`, `ANDROID_SDK_COMPILE_API=android-36`, `ANDROID_STL=c++_shared`, `ANDROID_CPUFEATURES_PATH`, `CMAKE_FIND_ROOT_PATH=${CMAKE_INSTALL_PREFIX}` | `D:tools/android-toolchain.cmake:31-45`. Krita forces `ANDROID_SDK_COMPILE_API "36"` again at `K:CMakeLists.txt:1724`. | New `D:tools/ios-toolchain.cmake`: `CMAKE_SYSTEM_NAME=iOS`, `CMAKE_OSX_ARCHITECTURES=arm64`, `CMAKE_OSX_DEPLOYMENT_TARGET=17.0` (the minimum Qt 6.11 supports), `CMAKE_FIND_ROOT_PATH=${CMAKE_INSTALL_PREFIX}` with `..._MODE_PACKAGE/LIBRARY/INCLUDE=ONLY`, `CMAKE_XCODE_ATTRIBUTE_CODE_SIGN_*` |
| 9 | Pre-seeded try-run results | `TIFF_HAS_PSD_TAGS=TRUE`, `TIFF_CAN_WRITE_PSD_TAGS=TRUE` (no try_run when cross-compiling) | `D:tools/android-toolchain-krita.cmake:9-10` (probe in `K:cmake/modules/CheckLibTIFFPSDSupport.cmake`) | Same two vars in `ios-toolchain-krita.cmake` |
| 10 | APK export | `QTANDROID_EXPORTED_TARGET=krita`, `ANDROID_APK_DIR=packaging/android/apk`. Release mode sets `ANDROIDDEPLOYQT_EXTRA_ARGS=--release`. | `D:tools/android-toolchain-krita.cmake:1-12`; `K:android.yml:82` | N/A. Use an Xcode/bundle step instead (§2.4). |
| 11 | Linker: 4 MiB stack | `-Wl,-z,stack-size=4194304` on exe/shared/module, "to prevent crashes with GMic" | `K:CMakeLists.txt:302-306`; also passed to 3rdparty plugins at `K:3rdparty_plugins/CMakeLists.txt:123-139` | No direct equivalent for secondary threads. Consider `QThreadPool/QThread::setStackSize` if deep recursion shows up (needs verification). |
| 12 | Linker: 16K pages | `-Wl,-z,max-page-size=16384` when NDK ≥ 27 on arm64/x86_64 | `K:CMakeLists.txt:308-313`; also `D:ext_qt/CMakeLists.txt:167-172`, `D:ext_openssl/CMakeLists.txt:47-52` | N/A (Apple toolchain already 16K-aligned) |
| 13 | Required Qt modules | `AndroidExtras` REQUIRED (Qt5) | `K:CMakeLists.txt:572-579`; linked in `K:libs/global/CMakeLists.txt:105-111`, `K:libs/widgetutils/CMakeLists.txt:148-150`, `K:libs/ui/CMakeLists.txt:807-814`, `K:krita/CMakeLists.txt:196-198`, `K:plugins/extensions/buginfo/CMakeLists.txt:25-29` | None. Platform glue would go in an ObjC++ helper lib (pattern: `kritamacosutils`, `K:libs/global/CMakeLists.txt:113-115`). |
| 14 | Crash handling | `find_package(unwindstack REQUIRED)`, `KisAndroidCrashHandler/ExitInfo/LogHandler/Utils` | `K:CMakeLists.txt:1153-1156`; `K:libs/global/CMakeLists.txt:58-69` | Skip unwindstack. Use system crash logs at first (KCrash is already off: see row 16). |
| 15 | Boost | `Boost_COMPILER clang` | `K:CMakeLists.txt:1154` | Header-only use should do. Verify whether any Boost lib is linked. |
| 16 | DBus / KCrash / X11 / X11Extras | Not searched (`NOT ... ANDROID`), so `HAVE_DBUS=FALSE` | `K:CMakeLists.txt:918-941` | Same automatically, because `APPLE` is true on iOS |
| 17 | FFmpeg in-process | `pkg_check_modules(LibAV REQUIRED libavcodec libavfilter libavformat libavutil libswscale)`. Android-only sources `KisLibavMediaEncoderRunnable`, `KisAndroidMediaEncoderRunnable`, `KisMediaEncoderWrapper`. | `K:CMakeLists.txt:1522-1558`; `K:libs/ui/CMakeLists.txt:577-585,811-813` | Defer animation export. iOS can't spawn an ffmpeg binary, so the Android in-process libav path is the one to reuse later. It must be made optional first. |
| 18 | QtQuick | Optional by package properties, but Android builds Quick and adds `QuickWidgets` to `ANDROID_EXTRA_LIBS`. At runtime it forces `QT_QUICK_BACKEND=software`. | `K:CMakeLists.txt:887-915`; `K:libs/ui/KisApplication.cpp:230-235` | `ON` (de facto required, see §7.4). Don't force the software backend unless stacking bugs appear. |
| 19 | GL | `-DQT_OPENGL_ES_3`, link `GLESv3`. Desktop-GL renderer not probed. | `K:libs/ui/CMakeLists.txt:2-11,808`; `K:libs/ui/opengl/kis_opengl.cpp:920-923` | Same `QT_OPENGL_ES_3` and GLES-only probe. Link `OpenGLES.framework` (Qt5) or use Qt6 RHI/Metal. |
| 20 | Plugin layout | `KRITA_PLUGIN_INSTALL_DIR=${KDE_INSTALL_LIBDIR}` (flat), `CMAKE_FIND_LIBRARY_SUFFIXES "_${ABI}.so" ".so" ".a"`. Runtime scan looks for `lib_krita*` files. | `K:CMakeLists.txt:1124-1141`; `K:libs/koplugin/KoJsonTrader.cpp:52-53,76-87,145-147` | Plugins inside the bundle (`Frameworks/` or `PlugIns/`). `KoJsonTrader` needs a `Q_OS_IOS` branch. With static Qt, plugins must become static (see §7.5). |
| 21 | Main target | `krita` is a **SHARED lib** (loaded by Java) on Android+Qt5. No `krita_version` exe. | `K:krita/CMakeLists.txt:196-205,235-250` | Executable plus `MACOSX_BUNDLE` with an iOS `Info.plist`. The current `APPLE` branch uses the macOS template at `K:krita/CMakeLists.txt:221-233` and Xcode-26 icon assets at `:17-40`. Skip `krita_version`. |
| 22 | Python scripting | Off, because the deps aren't built for Android (`base/python`, `sip`, `pyqt*` are listed for Windows/macOS/Linux only). `ext_python` has `FATAL_ERROR` on Android. | `D:latest/krita-deps.yml:121-128`; `D:ext_python/CMakeLists.txt:74-76`; gates at `K:plugins/CMakeLists.txt:14-16`, `K:plugins/extensions/pykrita/CMakeLists.txt:1` | `OFF` (defer) |
| 23 | G'MIC (3rdparty plugin) | Not built: `build-plugins.py` exits on Android. The `qmic` interface lib is still built. | `K:build-tools/ci-scripts/build-plugins.py:8-10`; `K:plugins/extensions/CMakeLists.txt:16` | Skip |
| 24 | Platform plugins (xcb/wayland) | Skipped ("breaks packaging the Qt platform plugin") | `K:plugins/CMakeLists.txt:18-21` | Skip (no X11/Wayland anyway) |
| 25 | Small colour selector docker | Off (`HAVE_OPENEXR AND NOT ANDROID`) | `K:plugins/dockers/CMakeLists.txt:2-4` | Try `ON` |
| 26 | LUT docker (OCIO) | Off (`NOT ANDROID`). OCIO not built for Android. | `K:plugins/dockers/CMakeLists.txt:17-19`; `D:latest/krita-deps.yml:88-94` | Off (defer) |
| 27 | Recorder docker | `recorder_profile_settings` removed (needs an external ffmpeg binary) | `K:plugins/dockers/recorder/CMakeLists.txt:27-30` | Same |
| 28 | Android-only plugins and data | `spensettings` extension; donation dialogs/IAP actions; supporter bundles in resource manager; `splash-android.qrc`; logcat dumper and crash log in buginfo | `K:plugins/extensions/CMakeLists.txt:21-23`; `K:libs/ui/CMakeLists.txt:518-528,690-695`; `K:krita/CMakeLists.txt:104-108,279-284`; `K:plugins/extensions/resourcemanager/CMakeLists.txt:34-44`; `K:plugins/extensions/buginfo/CMakeLists.txt:8-14` | Exclude donation/IAP/supporter bundles. Reuse the splash. Apple Pencil settings would replace `spensettings` later. |
| 29 | Removed data | No `windowlayouts`, no `Krita_3_Default_Resources.bundle` | `K:krita/data/CMakeLists.txt:24-29`; `K:krita/data/bundles/CMakeLists.txt:8-13` | Same (single-window UI, smaller bundle) |
| 30 | UI scaling | `KisAndroidScaling` if Qt has the density patch | `K:libs/ui/CMakeLists.txt:523-527,760-771`; `K:libs/ui/KisApplication.cpp:141-143,525-527` | Probe is false on iOS. Revisit if iPad scaling is wrong. |
| 31 | Runtime defaults (C++) | Fusion style; `AA_DontUseNativeMenuBar`; long-press on; kinetic scroll on left button; DB in `AppDataLocation`; no splash; Xiaomi pressure curve | `K:libs/ui/KisApplication.cpp:253-257,446-451,540-543`; `K:krita/main.cc:688-690`; `K:libs/ui/kis_config.cc:1614-1624,2471-2475,2999-3003` | Extend these `Q_OS_ANDROID` blocks to `Q_OS_IOS`. Fusion and the menubar flag are already shared with macOS/Win in the style case. The pressure-curve comment at `kis_config.cc:1618-1620` suggests a cap of about 50% for Apple Pencil. |
| 32 | Memory defaults | **Not Android-specific**: hard limit 50%, soft 2%, pool 0% of RAM. RAM detection uses the `Q_OS_LINUX` path, which Android takes. | `K:libs/image/kis_image_config.cpp:195-220,425-491` | On iOS `totalRAM()` has **no branch**: `Q_OS_MACOS` is undefined there, so it falls back to 1000 MiB (`:427-428,487-489`). Add a `Q_OS_IOS` branch (`sysctl hw.memsize` / `os_proc_available_memory()`) and a lower hard limit, for example around 30%, because of jetsam (tune by testing). |
| 33 | Static vs shared | Shared everywhere: deps platform `Android/<abi>/Qt5/Shared`; Krita libs `SHARED`, plugins `MODULE` | `K:android.yml:54`; `D:pipelines/android.yml:9`; e.g. `K:libs/global/CMakeLists.txt:71` | See §7.5. The Qt build mode drives this choice. |
| 34 | Apple-only flags that would break iOS | `-mmacosx-version-min`, `packaging/macos`, `xcodebuild -sdk macosx` all sit under plain `if (APPLE)` | `K:CMakeLists.txt:87-113`; 33 `APPLE` sites in `K:**/CMakeLists.txt` (e.g. `libs/ui/CMakeLists.txt:15,569,820,853`, `libs/widgetutils/CMakeLists.txt:139`, `krita/integration/CMakeLists.txt:1,21`) | Guard each with `APPLE AND NOT IOS` or split into `IOS` branches |
| 35 | ABIs | x86_64, arm64-v8a, armeabi-v7a | `K:android.yml:90,99,108` | arm64 only. A Simulator slice is optional. |

### 2.3 Krita-side Qt-patch probes (set Android features automatically)
`K:CMakeLists.txt:797-841,844-856` probe for `KRITA_QT_HAS_ANDROID_EMULATE_MOUSE_BUTTONS_FOR_PAGE_UP_DOWN`, `..._ANDROID_IGNORE_HISTORIC_TABLET_EVENTS`, `..._ANDROID_EMULATE_MOUSE_BUTTONS_FOR_HIGH_FUNCTION_KEYS`, `KRITA_QT_HAS_QSCROLLER_FILTER`, `..._ANDROID_INPUT_PLATFORM_DATA_SOFT_INPUT_ADJUST_NOTHING`, `..._ANDROID_QPLATFORMSCREEN_DENSITY_ADJUSTMENT` and `KRITA_QT_HEADER_VIEW_MEMORY_MODE_INITIALIZATION_FIX`. All of them are written to `K:config-qt-patches-present.h.cmake`. The cross-platform probes are at `K:CMakeLists.txt:643-687` (Enter/Leave, KeyPress/Release, update-compression). They are compile probes, so an unpatched iOS Qt just turns them off.

### 2.4 How the APK is produced (brief)
- `cmake --build . --target create-apk` (`K:build-tools/ci-scripts/build-android-package.py:69-75`). The target comes from `ecm_androiddeployqt()` (`K:CMakeLists.txt:1743-1764`), which runs `androiddeployqt` over `packaging/android/apk`.
- Non-debug builds then run `./gradlew assembleRelease|assembleNightly` in `_build/krita_build_apk` (`build-android-package.py:77-100`). The template is `K:packaging/android/apk/build.gradle` (minSdk 24, targetSdk 36, NDK 27.3: `:204-214`).
- The AAB merges per-ABI artifacts (`K:build-tools/ci-scripts/build-android-appbundle.py`, `merge-libs-xml.py`; job `K:android.yml:121-145`).
- androiddeployqt drops QML modules when `_install` sits inside the source root, hence `KDECI_WORKDIR_PATH=/tmp/wd` (`K:android.yml:27-31`).
- `K:README.android.md` is stale: it still mentions NDK r18b and `androidbuild.sh`.
- iOS needs a separate path: Xcode generator or `macdeployqt`-like bundling, plus codesign.

---

## 3. Dependencies

### 3.1 How deps are built
- **This is not a superbuild.** Each `ext_<name>/` directory is a standalone CMake project wrapping one `ExternalProject_Add`. Each includes `D:cmake/base-dep-options.cmake` (`:49-71`: ExternalProject, `KritaExternalProject`, and `krita_add_to_ci_targets()` giving `ext_build` and `ext_install`).
- **Per-recipe dependencies** live in `ext_<name>/.kde-ci.yml` (`Dependencies:` / `BuildDependencies:` with `'on': [...]` platform filters).
- **Package identity** comes from `D:repo-metadata/projects-invent/{base,ffmpeg,heif}/<name>/metadata.yaml` (e.g. `base/qt/metadata.yaml`: `identifier: ext_qt`).
- **Top-level seed lists**, which are the best evidence of per-platform sets:
  - `D:latest/krita-deps.yml`: what Krita depends on, per platform.
  - `D:latest/deps-build-tools.yml`: `nasm` on `@all`; `patch` and `strawberryperl` on Windows.
  - `D:latest/developer-packages.yml`: `qt-debug`, `mlt-debug`, `qt-asan`.
  - `D:latest/openvino-packages.yml`.
- **Driver.** Python tooling from `krita-ci-utilities` (`seed-package-registry.py`, `run-ci-build.py`) builds each dep in dependency order and publishes it as a GitLab package. The Android pipeline is `D:pipelines/android.yml:1-33`: it concatenates `deps-build-tools.yml` and `krita-deps.yml`, then seeds `--platform Android/$KDECI_ANDROID_ABI`. The Android CI base is `D:.gitlab-ci.yml:174-200` (`CMAKE_TOOLCHAIN_FILE=tools/android-toolchain.cmake`).
- **Platform matching.** Platforms are `/`-separated flavor strings matched by prefix (`CIU:components/PlatformFlavor.py:15-30`). So `'Android'` matches `Android/arm64-v8a`.
- **Where iOS would slot in:**
  1. `D:tools/ios-toolchain.cmake` and `ios-toolchain-krita.cmake`, mirroring `android-toolchain*.cmake` and `macos-toolchain*.cmake`.
  2. A new platform string `iOS` (or `iOS/arm64`) in `latest/krita-deps.yml` and in each recipe's `.kde-ci.yml` `'on'` lists.
  3. `elseif (IOS)` branches in recipes that special-case Android or Apple. Recipes with `APPLE` branches: `ext_boost`, `ext_libraw`, `ext_pkgconfig`, `ext_pyqt5`, `ext_python`, `ext_qt`, `ext_vpx`, `ext_zlib`. These **will trigger on iOS** because CMake sets `APPLE` there, and `ext_qt` uses `kis_ExternalProject_Add_macos` with per-arch builds (`D:cmake/KritaExternalProject.cmake:38-69,115`).
  4. A `pipelines/ios.yml` if you use CI. For a personal build, a local script can run each recipe's CMake in topological order against one prefix.
  5. `krita-ci-utilities` has Android special-cases (`CIU:run-ci-build.py:84,395-428`, `CIU:components/EnvironmentHandler.py:28-39`) that an iOS flavor would also need.

### 3.2 Android dependency set (from `D:latest/krita-deps.yml`)
- **Included on Android:**
  - Everything in `@all` (`:1-62`): boost, lcms2, png, eigen3, expat, exiv2, fribidi, libaom, fftw3, freetype, fontconfig, qt, imath, openexr, tiff, gsl, giflib, openjpeg, json_c, xsimd, unibreak, webp, quazip, zug, immer, lager, highway, brotli, jpegxl, ECM, kconfig, karchive, kwidgetsaddons, kcompletion, kcoreaddons, kguiaddons, ki18n, kitemmodels, kitemviews, kimageformats, kwindowsystem, mypaint, seexpr, icu, jpeg, flac, libogg, opus, sdl2, vpx, libvorbis, libtheora, openh264, lame, ffmpeg, mlt.
  - The Android block (`:130-136`): zlib, gettext, openssl, libintl-lite, libunwindstack-ndk.
  - `nasm` (`D:latest/deps-build-tools.yml:6-8`).
  - x86_64 only: libde265, libx265 (8/10/12-bit), libheif (`:96-104`).
- **Excluded on Android:**
  - iconv (`:64-77`: can't cross-compile, so exiv2 has no charset conversion).
  - lzma (`:79-86`).
  - ocio (`:88-94`).
  - vpl (`:106-109`).
  - libraw and kdcraw (`:111-119`: "doesn't work in runtime").
  - python, sip, pyqt-builder, pyqt5, pyqt5-sip, poppler (`:121-128`).
  - pkgconfig, meson (`:147-155`: "on Android the use of pkgconfig is explicitly prohibited").
  - python-modules, kcrash, fcitx-qt, appimagetool, linuxdeployqt (`:157-170`).

### 3.3 Recipe table (96 recipes on master)
Legend for "Needed for painting-only build":
- **R**: required (Krita `find_package(... REQUIRED)` / `TYPE REQUIRED`, or a hard dependency of one).
- **R?**: needed on iOS in one form.
- **Rec**: recommended (painting works, but a feature degrades).
- **Opt**: optional importer or feature; defer.
- **Unused**: not referenced by Krita.
- **N/A**: host tool, another platform, or dev-only.

`K:CML` = `K:CMakeLists.txt`.

| Recipe | Android handling | Needed for painting-only build | Notes |
|---|---|---|---|
| ext_appimagetool | Not in Android set (Linux, `krita-deps.yml:166-170`) | N/A | Linux packaging tool |
| ext_boost | `elseif(ANDROID)` b2 build `--with-libraries=system` (`ext_boost/CMakeLists.txt:101-102`); patch `0001-Add-support-for-NDK-27.X-and-30.0.patch` | R (`K:CML:1171-1175`) | Has an `APPLE` branch, so iOS needs a guard. Likely header-only on iOS. |
| ext_brotli | In @all | R (transitive: `ext_exiv2/.kde-ci.yml` @all, jpegxl) | |
| ext_dlfcn_win32 | No | N/A | Windows |
| ext_drmingw | No | N/A | Windows |
| ext_eigen3 | In @all | R (`K:CML:1411-1418`) | Header-only |
| ext_exiv2 | Separate `if (ANDROID)` ExternalProject (`ext_exiv2/CMakeLists.txt:13`); no iconv on Android | R (`K:CML:1423`) | On iOS the SDK libiconv can be used |
| ext_expat | In @all | R (transitive: exiv2, fontconfig) | iOS SDK may provide it (verify) |
| ext_extra_cmake_modules | Patches `0001-ANDROID-Find-dependencies-of-manually-specified-libr.patch`, `0001-Android-Skip-setting-up-fastlane.patch`, `0002-Android-Recursively-find-dependency-of-dependencies.patch` | R (`K:CML:466-472`) | ECM 5.101 (`ext_extra_cmake_modules/CMakeLists.txt:9`); no ECM iOS toolchain |
| ext_fcitx-qt | No (Linux) | N/A | |
| ext_ffmpeg | In @all; `if (ANDROID AND i686)` disables asm (`ext_ffmpeg/CMakeLists.txt:8-9`); nasm only on x86 (`.kde-ci.yml` BuildDependencies) | Opt on iOS (Android: **R**, `K:CML:1524-1557`) | Needed for animation/recorder export. Krita's REQUIRED check is `if(ANDROID)` only. |
| ext_fftw3 | In @all | Rec (`K:CML:1310-1319`: fast convolution) | Also an MLT dep |
| ext_flac | In @all; patch `0001-Revert-CMake-disable-fseeko-on-32-bit-Android-before.patch` | Opt | ffmpeg group |
| ext_fontconfig | In @all; `.kde-ci.yml` needs gettext on Android | R (`K:CML:1626-1630`) | iOS needs a fonts.conf pointing at accessible font dirs. The old Android font-path patch was dropped (see `L:`). |
| ext_freetype | In @all; also builds HarfBuzz 12.3.2 (`ext_freetype/CMakeLists.txt:45-87`) | R (Freetype `K:CML:1595-1600`, HarfBuzz `:1606-1619`) | |
| ext_fribidi | In @all | R (`K:3rdparty_vendor/raqm/CMakeLists.txt:28`) | |
| ext_gettext | Android block (`krita-deps.yml:130-135`); ki18n and fontconfig dep on Android | R? (ki18n runtime) | iOS: gettext or libintl-lite |
| ext_giflib | In @all | Opt (GIF filter `K:CML:1282-1286`) | Also a webp dep |
| ext_googleangle | No (Windows) | N/A | |
| ext_gperf | No (Windows) | N/A | fontconfig build tool on Windows |
| ext_gsl | In @all (the old `gsl-android.patch` is gone) | Rec (`K:CML:1198-1203`, TYPE RECOMMENDED: transform tool, gradients) | |
| ext_highway | In @all | Opt (jpegxl dep) | |
| ext_iconv | Excluded on Android (`krita-deps.yml:64-77`) | N/A | Use the iOS SDK libiconv |
| ext_icoutils | No | N/A | Windows |
| ext_icu | In @all | R (transitive: Qt `-icu`, freetype) | Possibly drop on iOS (`-no-icu`); verify |
| ext_imath | In @all ("needed for float-16", `krita-deps.yml:15-20`) | Rec | OpenEXR dep |
| ext_immer | In @all | R (`K:CML:1191`) | Header-only |
| ext_jpeg | Own `if (ANDROID)` branch: `WITH_SIMD=OFF`, `ANDROID_ARM_MODE=arm` (`ext_jpeg/CMakeLists.txt:7-13`) | R (Qt dep `ext_qt/.kde-ci.yml:2-7`; Krita marks it OPTIONAL at `K:CML:1259-1278`) | |
| ext_jpegxl | In @all | Opt (`K:CML:1303-1307`) | |
| ext_json_c | In @all | Rec (mypaint dep) | |
| ext_karchive | `if (ANDROID)` disables PkgConfig (`ext_karchive/CMakeLists.txt:7-8`) | Opt (only used by kimageformats) | |
| ext_kcompletion | In @all | R (`K:CML:548-556`) | |
| ext_kconfig | Patch `0001-Android-Fix-a-bug-where-new-file-wouldn-t-be-created.patch` | R | `0001-Patch-kconfig-to-save-the-config-to-AppConfigLocatio.patch` is relevant on iOS |
| ext_kcoreaddons | In @all | R | |
| ext_kcrash | No (Linux; Krita `K:CML:931-937`) | N/A | |
| ext_kdcraw | Excluded on Android (`krita-deps.yml:111-119`) | Opt (RAW) | |
| ext_kguiaddons | In @all | R | |
| ext_ki18n | `.kde-ci.yml`: gettext and libintl-lite on Android | R | Patches `0003-Patch-the-location-where-ki18n-looks-for-catalogs.patch` and others |
| ext_kimageformats | In @all | Opt (runtime Qt image plugins) | |
| ext_kitemmodels | In @all | Unused (no reverse dep, no Krita reference found) | Skip candidate; verify |
| ext_kitemviews | In @all | R | |
| ext_kwidgetsaddons | In @all | R | |
| ext_kwindowsystem | In @all | Unused (only kcrash depends on it) | Skip candidate; verify |
| ext_lager | In @all | R (`K:CML:1193`) | |
| ext_lame | In @all | Opt | ffmpeg group |
| ext_lcms2 | In @all | R (`K:CML:1428-1433`) | |
| ext_libaom | In @all; patch `android-cpu-features.patch` (uses `ANDROID_CPUFEATURES_PATH`) | Opt (HEIF/ffmpeg) | |
| ext_libde265 | Android x86_64 only (`krita-deps.yml:96-104`) | Opt | |
| ext_libheif | Android x86_64 only | Opt (`K:CML:1289-1293`) | |
| ext_libintl-lite | Android block (`krita-deps.yml:130-136`) | R? (ki18n libintl on iOS) | Likely the iOS choice (no libintl in the SDK) |
| ext_libogg | In @all | Opt | |
| ext_libraw | Excluded on Android; `if(APPLE OR ANDROID)` turns off OpenMP (`ext_libraw/CMakeLists.txt:6-11`) | Opt | |
| ext_libtheora | In @all | Opt | |
| ext_libunwindstack-ndk | Android-only (`krita-deps.yml:136`) | N/A on iOS (Android **R**: `K:CML:1155`) | |
| ext_libvorbis | In @all | Opt | |
| ext_libx265 / _10bit / _12bit | Android x86_64 only; nasm on x86 | Opt | 3 recipes |
| ext_linuxdeployqt | No | N/A | |
| ext_lzma | Excluded on Android (`krita-deps.yml:79-86`) | Opt | ffmpeg/python dep |
| ext_mlt | In @all; `if (ANDROID)`: `MOD_RTAUDIO=OFF` and patch `0011-android-Fix-export-table-for-FILE-arguments-with-NDK.patch`; also `0004-Android-Add-an-option-to-skip-non-plugins-in-reposit.patch` | Opt (audio/animation playback, `K:CML:1375-1386`) | Pulls in SDL2 as REQUIRED when found |
| ext_mlt-debug | No | N/A | Developer package |
| ext_mypaint | In @all | Rec (MyPaint brush engine, `K:CML:1388-1393`) | |
| ext_nasm | `@all` build tool (`deps-build-tools.yml:6-8`) | N/A | x86 asm only |
| ext_ocio | Excluded on Android (`krita-deps.yml:88-94`) | Opt (LUT docker) | |
| ext_openexr | In @all (EXR files fail on Android but half-float is needed) | Rec (`HAVE_OPENEXR` in pigment/ui, `K:CML:1244-1248`) | |
| ext_openh264 | In @all | Opt | |
| ext_openjpeg | In @all | Opt (JP2, `K:CML:1296-1300`) | |
| ext_openssl | Android block; `elseif (ANDROID)` Configure (`ext_openssl/CMakeLists.txt:46-66`); Qt `-openssl-linked` | Opt on iOS | Qt for iOS can use SecureTransport, so skip OpenSSL |
| ext_opus | In @all | Opt | |
| ext_patch | No | N/A | Windows |
| ext_pkgconfig | Not on Android ("explicitly prohibited") | N/A | Host tool; Krita still needs host pkg-config for LibAV on Android |
| ext_png | In @all | R (`K:CML:1158`) | |
| ext_poppler | Excluded (`krita-deps.yml:121-128`) | Opt (PDF import) | |
| ext_pyqt-builder | Excluded | Opt (scripting) | |
| ext_pyqt5 | Excluded | Opt | |
| ext_pyqt5-sip | Excluded | Opt | |
| ext_python | Excluded; `FATAL_ERROR` on Android (`ext_python/CMakeLists.txt:74-76`) | Opt | |
| ext_python-modules | Excluded | Opt | |
| ext_python-openvino | No | N/A | openvino-packages.yml |
| ext_qt | Android branch (`ext_qt/CMakeLists.txt:166-218`); 3 or 4 Android patches (§7) | R | |
| ext_qt-asan | No | N/A | Dev |
| ext_qt-debug | No | N/A | Dev |
| ext_quazip | In @all | R (`K:CML:1563-1568`, TYPE REQUIRED: KRA/ORA) | |
| ext_sdl2 | `if (ANDROID)` uses the `sh-zam/SDL-android-glue` fork, audio only (`ext_sdl2/CMakeLists.txt:6-18`) | Opt (needed only with MLT, `K:CML:1379-1384`) | |
| ext_seexpr | In @all | Opt (`K:CML:1223-1232`) | |
| ext_sip | Excluded | Opt | |
| ext_strawberryperl | No | N/A | |
| ext_tiff | `if(ANDROID)` patch `0001-android-Remove-windows-specifc-symbols-from-linker-s.patch` (`ext_tiff/CMakeLists.txt:6-14`) | Opt (TIFF filter `K:CML:1250-1254`; webp dep) | |
| ext_unibreak | In @all | R (`K:CML:1635-1640`) | |
| ext_vpl | No (Windows/Linux) | N/A | |
| ext_vpx | `if (ANDROID AND i686)` multithreading flags (`ext_vpx/CMakeLists.txt:8-12`) | Opt | Has an `APPLE` branch |
| ext_webp | In @all | Opt (`K:CML:1213-1218`) | |
| ext_xsimd | In @all | R (`K:CML:1464-1474`, TYPE REQUIRED) | Header-only; arm64 NEON |
| ext_zlib | Android block | R (`K:CML:1236-1240`) | iOS SDK has libz; can use system zlib like Linux |
| ext_zug | In @all | R (`K:CML:1192`) | |

**Counts (96 recipes):**

| Category | Count | Members |
|---|---|---|
| R | 28 | boost, brotli, eigen3, exiv2, expat, ECM, fontconfig, freetype(+harfbuzz), fribidi, icu, immer, jpeg, kcompletion, kconfig, kcoreaddons, kguiaddons, ki18n, kitemviews, kwidgetsaddons, lager, lcms2, png, qt, quazip, unibreak, xsimd, zlib, zug |
| R? | 1 needed, of 2 recipes | gettext or libintl-lite |
| Rec | 6 | gsl, imath, openexr, fftw3, mypaint, json_c |
| Opt | 38 | importers, ffmpeg/MLT/audio stack, HEIF/x265, RAW, PDF, Python, OCIO, SeExpr, kimageformats, openssl, … |
| Unused | 2 | kitemmodels, kwindowsystem |
| N/A | 20 | host tools, other platforms, dev-only, Android unwindstack |

Android-only hard requirements that drop out on iOS: libunwindstack-ndk, ffmpeg (LibAV), and openssl (only because Qt uses it).

## 4. Plugin loading and a static registry

Paths are relative to the repository root. "Verified" means checked against this tree or against the system headers of the Linux session: Qt 5.15.13 and KF5 KCoreAddons 5.115.0.

### 4.1 How plugins are discovered and loaded today

**Two classes in `libs/koplugin` (library `kritaplugin`, SHARED, `libs/koplugin/CMakeLists.txt:13`):**

- **`KoJsonTrader`**: a `Q_GLOBAL_STATIC` singleton (`libs/koplugin/KoJsonTrader.cpp:128-133`). Its constructor finds a single plugin directory:
  - It reads the env var `KRITA_PLUGIN_PATH` first (`KoJsonTrader.cpp:35-39`).
  - Otherwise it starts from `qApp->applicationDirPath()/..` (`:43-44`). On macOS it also tries `../../../` and a `*PlugIns*` dir (`:45-50, 59-70`).
  - It then looks for `lib*/kritaplugins` or `lib*/<triplet>/kritaplugins` (`:72-108`).
  - `initializePluginLoaderCache()` (`:135-183`) walks that directory recursively with `QDirIterator`. It takes every file whose name starts with `krita`, skipping `.debug`/`.pdb`/`.lib` (`:148-151`), and builds a `QPluginLoader` for each (`:155`).
  - It reads the embedded metadata without loading the library: `loader->metaData().value("MetaData")` (`:156`).
  - It requires `X-KDE-ServiceTypes` (`:164-168`) and collects mime types from `X-KDE-ExtraNativeMimeTypes`, `MimeType` and `X-KDE-NativeMimeType` (`:170-172`).
  - `query(serviceType, mimetype)` (`:185-203`) filters that cache. `Plugin::instance()` calls `QPluginLoader::instance()` under a mutex, and that call is the actual `dlopen` (`:215-219`).
- **`KoPluginLoader`**: a singleton (`libs/koplugin/KoPluginLoader.cpp:76-81`).
  - `load(serviceType, config, owner, cache)` (`:83-155`) does the following in order:
    1. Queries the trader (`:91`).
    2. Removes duplicate `Id`s, keeping the highest `X-Krita-Version` (`:26-31, 98-109`). That version is read as `json.value("X-Krita-Version").toString().toInt()`.
    3. Applies a KConfig blacklist (`:112-127`).
    4. Does `qobject_cast<KPluginFactory*>(plugin.instance())` and `factory->create<QObject>(owner ? owner : this)` (`:141-143`). The created object is deleted straight away when there is no owner (`:146-150`), because the plugin's constructor does its work by registering factories into a global registry (see the doc comment at `KoPluginLoader.h:17-51`).
  - `loadSinglePlugin(predicates, serviceType)` (`:157-182`) returns the highest-version `KPluginFactory*` whose JSON matches every `(key, value)` predicate.

**How plugins declare their factory.** All 171 Krita runtime plugins use `K_PLUGIN_FACTORY_WITH_JSON(<Class>, "<file>.json", registerPlugin<X>();)`. Examples are `plugins/color/lcms2engine/LcmsEnginePlugin.cpp:74` and `plugins/paintops/defaultpaintops/defaultpaintops_plugin.cc:28`. The documented pattern is in `KoPluginLoader.h:43`.
- In KF5 the macro expands to a `KPluginFactory` subclass carrying `Q_OBJECT` and `Q_PLUGIN_METADATA(IID KPluginFactory_iid FILE json)` (`/usr/include/KF5/KCoreAddons/kpluginfactory.h:63-75, 213-214`). `KPluginFactory_iid` is `"org.kde.KPluginFactory"` (`kpluginfactory.h:34`).
- moc therefore compiles the JSON into the object file. In a non-static build moc also emits the `extern "C"` symbols `qt_plugin_instance()` and `qt_plugin_query_metadata()` (`qplugin.h:184-205`).
- A typical JSON file is `plugins/paintops/defaultpaintops/kritadefaultpaintops.json`, with fields `Id`, `X-KDE-ServiceTypes: ["Krita/Paintop"]` and `X-Krita-Version: "28"`. File filters also carry `X-KDE-Import`, `X-KDE-Export` and `X-KDE-Weight`, for example `plugins/impex/png/krita_png_import.json`.

**Where loading is triggered:**

| Service type | Call site |
|---|---|
| Krita/ColorSpace, Krita/ColorSpaceExtension | `libs/pigment/KoColorSpaceRegistry.cpp:185, 190` |
| Krita/Paintop | `libs/image/brushengine/kis_paintop_registry.cc:45` |
| Krita/Filter | `libs/image/filter/kis_filter_registry.cc:46` |
| Krita/Generator | `libs/image/generator/kis_generator_registry.cpp:44` |
| Krita/Tool | `libs/flake/KoToolRegistry.cpp:34` |
| Krita/Dock | `libs/flake/KoDockRegistry.cpp:48` |
| Krita/Flake, Krita/Shape | `libs/flake/KoShapeRegistry.cpp:61, 64` |
| Krita/Metadata | `libs/metadata/kis_meta_data_backend_registry.cpp:32` |
| Krita/ViewPlugin (once per main window, `cache=false`, owner = view manager) | `libs/ui/KisMainWindow.cpp:404` |
| Krita/ApplicationPlugin (pykrita) | `libs/ui/KisMainWindow.cpp:407` |
| Krita/FileFilter, queried directly through `KoJsonTrader` | `libs/ui/KisImportExportManager.cpp:196, 211, 231-263` |
| Krita/PlatformPlugin, via `loadSinglePlugin` | `libs/ui/KisPlatformPluginInterfaceFactory.cpp:33, 63, 120`; `plugins/extensions/buginfo/DlgColorManagementInfo.cpp:23` |
| Krita/Deferred | `libs/flake/KoShapeFactoryBase.cpp:201` (no plugin in the tree provides it) |
| Krita/GMic | `plugins/extensions/qmic/QMic.cpp:52` |

- For file filters, `KisImportExportManager` creates a factory, calls `create<KisImportExportFilter>()`, picks the highest `X-KDE-Weight`, and sets `f->setObjectName(loader.fileName())` (`:263`). With static plugins `fileName()` will be empty, so give it a synthetic name.
- The registries are lazily initialised `Q_GLOBAL_STATIC`s. `KisApplication::loadPlugins()` (`libs/ui/KisApplication.cpp:466-480`) touches them in a fixed order: shape, colorspace, action, filter, generator, paintop, tool, dock, metadata. It is called from `KisApplication::start()` (`:566`), after `addResourceTypes()`.
- If the LCMS engine is missing, Krita quits: `libs/ui/KisMainWindow.cpp:3000`.

**Android has no static path.** It uses the same `QPluginLoader` and `.so` mechanism with three tweaks:
1. `KRITA_PLUGIN_INSTALL_DIR` is plain `lib` (`CMakeLists.txt:1124-1133`) instead of `lib/kritaplugins` (`:1142`).
2. Gradle copies `krita*.so` into `libs/$abi` and renames them to `lib_krita*.so` (`packaging/android/apk/build.gradle:65-73`). NDK packaging only keeps `lib*.so`.
3. `KoJsonTrader` goes up one more directory level and into `lib/<abi>` (`KoJsonTrader.cpp:52-54, 76-87`), and filters on the `lib_krita` prefix (`:145-147`).

The `krita` target itself is a SHARED library on Android, loaded by the Qt Java activity (`krita/CMakeLists.txt:196-198`). Platform plugins are not built there (`plugins/CMakeLists.txt:17-20`). None of the Android work can be reused for iOS beyond showing that the trader is the single choke point.

### 4.2 Build macro, plugin count and static feasibility

**Macro.** There is no `krita_add_plugin`, and nothing comes from ki18n or ECM.
- Plugins are built with `kis_add_library(<target> MODULE ...)`, a macro defined in the top-level `CMakeLists.txt:1076-1112`, not in `cmake/modules/`.
- It forwards everything to `add_library()` (`:1079-1080`) and only adds precompiled-header handling (`:1082-1111`).
- Install destination: `install(TARGETS <t> DESTINATION ${KRITA_PLUGIN_INSTALL_DIR})`, for example `plugins/color/lcms2engine/CMakeLists.txt:89`.
- Four plugin targets call plain `add_library(... MODULE)` instead:
  - `plugins/dockers/widegamutcolorselector/CMakeLists.txt:29`
  - `plugins/impex/rgbe/CMakeLists.txt:10`
  - `plugins/impex/webp/CMakeLists.txt:9, 19`
- `kis_add_library` is used 214 times outside tests.

**Count.**
- There are 173 `MODULE` declarations under `libs/` and `plugins/`.
  - One is the koplugin test macro (`libs/koplugin/tests/CMakeLists.txt:10`), which produces 4 dummy plugins.
  - One is the Qt Designer plugin (`plugins/qt/designer/CMakeLists.txt:13`), which is not a Krita runtime plugin.
  - That leaves **171 Krita runtime plugin targets**. This matches the 171 non-test JSON files that contain `X-KDE-ServiceTypes`.
- `K_PLUGIN_FACTORY_WITH_JSON` appears in 174 files: the 171 plugins, `DummyPlugin.cpp`, and doc comments in `KoPluginLoader.h` and `KoToolFactoryBase.h`.

| Service type (JSON) | # | Directory |
|---|---|---|
| Krita/FileFilter (impex) | 41 | `plugins/impex/*` |
| Krita/Filter | 34 | `plugins/filters/*` |
| Krita/Dock | 30 | `plugins/dockers/*` |
| Krita/ViewPlugin (extensions) | 19 | `plugins/extensions/*` |
| Krita/Paintop | 15 | `plugins/paintops/*` |
| Krita/Tool | 15 | 14 in `plugins/tools/*` + `plugins/assistants/Assistants` |
| Krita/Generator | 7 | `plugins/generators/*` |
| Krita/Metadata | 3 | `plugins/metadata/{exif,xmp,iptc}` |
| Krita/PlatformPlugin | 2 | `plugins/platforms/{xcb,wayland}` |
| Krita/ApplicationPlugin | 1 | `plugins/extensions/pykrita` |
| Krita/Flake + Krita/Shape | 1 + 1 | `plugins/flake/{imageshape,pathshapes}` |
| Krita/ColorSpace | 1 | `plugins/color/lcms2engine` |
| Krita/ColorSpaceExtension | 1 | `plugins/color/colorspaceextensions` |
| **Total** | **171** | |

**Core libraries are hard-coded SHARED.**
- Every core lib passes the keyword `SHARED` explicitly: kritaglobal, kritaimage, kritaui, kritapigment, kritaflake, kritawidgets, kritawidgetutils, kritaresources, kritaplugin and about 20 more. Examples are `libs/global/CMakeLists.txt`, `libs/ui/CMakeLists.txt` and `libs/image/CMakeLists.txt`.
- Plugin-side helper libraries are also SHARED: `plugins/paintops/libpaintop` (kritalibpaintop), `plugins/impex/libkra` (kritalibkra), `plugins/metadata/common` (kritaexifcommon), `plugins/impex/tiff` (kritatiffpsd), `plugins/extensions/qmic` (kritaqmicinterface).
- Because the keyword is explicit, `BUILD_SHARED_LIBS` has no effect. A grep for `BUILD_SHARED_LIBS`, `QT_STATICPLUGIN`, `Q_IMPORT_PLUGIN` or any static-build option outside `3rdparty` finds nothing. The only `Q_INIT_RESOURCE` is in a test (`libs/ui/tests/kis_view_signals_test.cpp:34`).
- The platform hacks that do exist go the other way. Windows builds `krita` as a DLL behind a stub EXE (`krita/CMakeLists.txt:199-202`), and Android builds it as a `.so`.

**Static looks feasible, for three reasons:**
1. Because almost every library goes through `kis_add_library`, a single rewrite of `SHARED|MODULE` to `STATIC` inside that macro covers nearly the whole tree.
2. Many plugins are already split into a `*_static` STATIC archive plus a thin MODULE that links it, so their unit tests can link the code directly. The `kis_add_library(... STATIC ...)` calls:

   | Archive | File:line |
   |---|---|
   | `kritalcmsengine_static` | `plugins/color/lcms2engine/CMakeLists.txt:82` |
   | `kritadefaultpaintops_static` | `plugins/paintops/defaultpaintops/CMakeLists.txt:26` |
   | `kritamypaintop_static` | `plugins/paintops/mypaint/CMakeLists.txt` |
   | `kritadefaulttools_static`, `kritatooltransform_static`, `kritatoolKnife_static`, `krita_tool_svgtext_static` | `plugins/tools/...` |
   | `kritalayerdocker_static`, `kritaanimationdocker_static`, `kritalutdocker_static`, `kritastoryboarddocker_static` | `plugins/dockers/...` |
   | `kritapsd_static` | `plugins/impex/psd/CMakeLists.txt` |
   | `kritaassistanttool_static` | `plugins/assistants/Assistants/CMakeLists.txt` |

   So most of the code already compiles as static archives.
3. On Apple and ELF, `generate_export_header` macros expand to `visibility("default")`, which is harmless in a static link. Unlike Windows, no `*_STATIC_DEFINE` juggling is needed.

**Gotchas for the static build itself:**
- `if(APPLE)` is true on iOS, so `libs/macosutils`, which is AppKit-only, would be built (`libs/CMakeLists.txt:2-3`). There are 17 `if (APPLE)` blocks in `libs/` and `krita/` to audit.
- `krita/CMakeLists.txt:204` falls through to `add_executable` on iOS. That is correct, but it needs `MACOSX_BUNDLE`.

### 4.3 Other runtime loading that breaks on iOS

**Qt plugins.** Qt for iOS is static-only, so every Qt plugin has to be linked and imported.
- With Qt5 CMake this means `qt5_import_plugins()` (verified at `/usr/lib/x86_64-linux-gnu/cmake/Qt5Core/Qt5CoreMacros.cmake:471`; each plugin target carries `QT_PLUGIN_CLASS_NAME`, see for example `Qt5Gui_QEglFSIntegrationPlugin.cmake:11`) or explicit `Q_IMPORT_PLUGIN(<ClassName>)`. Qt6's `qt_add_executable` does this automatically for the default set. Qt6 behaviour is unverified here because no Qt6 headers are installed.
- Required plugins:
  - **platform**: `QIOSIntegrationPlugin`.
  - **sqldrivers**: `QSQLiteDriverPlugin`. The resource cache DB hard-codes `"QSQLITE"` (`libs/resources/KisResourceCacheDb.cpp:41, 176`). Without it, `KisResourceCacheDb::initialize()` fails and Krita shows "Krita will quit now" (`KisApplication.cpp:453-455`).
  - **iconengines**: `QSvgIconPlugin`. Icons are loaded as `QIcon(":/pics/*.svg")` (`libs/widgetutils/kis_icon_utils.cpp:41-60`).
  - **imageformats**: at least `QJpegPlugin`, `QGifPlugin` and `QSvgPlugin`, which are used through QImageReader in the `plugins/impex/qimageio` filter, reference images and brushes.
  - **QML**: for Qt Quick widgets, the Qt Quick, Controls 2, Layouts and Templates QML plugins, imported with `Q_IMPORT_QML_PLUGIN` / `qt_import_qml_plugins`.
- From Qt's iOS docs and not in this repo: the app entry point is `qt_main_wrapper` (linker `-e _qt_main_wrapper`), and the user `main` (`krita/main.cc:217`) runs inside it.

**Krita's own QML module.** `qmlmodules/components` is built with `ecm_add_qml_module(kritaqmlcomponents ... SHARED GENERATE_PLUGIN_SOURCE)` on Qt6 (`qmlmodules/components/CMakeLists.txt:5-10`), or as a `CLASSNAME KritaQmlComponentsPlugin` QML plugin on Qt5 (`:34-37`). Both are loaded from `KDE_INSTALL_QMLDIR` at runtime. They must be built STATIC and imported. `qmlmodules/widgets` (kritaqmlwidgets) is SHARED (`qmlmodules/widgets/CMakeLists.txt:8`).

**KF5 frameworks.** Krita uses Config, CoreAddons, I18n, WidgetsAddons, Completion, GuiAddons (only `kcolorutils.h`), ItemViews and optional Crash (`CMakeLists.txt:548-556`).
- KCoreAddons is fine: Krita never calls `KPluginLoader` or `KPluginMetaData::findPlugins` (grep), only `KPluginFactory`.
- KI18n loads `kf5/ktranscript` through QLibrary. It exists on this machine at `/usr/lib/x86_64-linux-gnu/qt5/plugins/kf5/ktranscript.so`. Losing it degrades gracefully: you only lose scripted translations.
- KI18n catalogs (`.mo`) must be in a bundle `share/locale` directory that QStandardPaths can find.

**QLibrary / dlopen call sites** (grep over `libs`, `krita`, `plugins`):

| Call site | What it loads | iOS status |
|---|---|---|
| `libs/global/KisWindowsPackageUtils.cpp:79`, `libs/ui/qtsingleapplication/qtlocalpeer.cpp:55`, `krita/main.cc:110, 145` | Windows DLLs | Windows-only, harmless |
| `plugins/extensions/pykrita/plugin/utilities.cpp:247-248` | libpython via `QLibrary` with `ExportExternalSymbolsHint` | Must be excluded |

There are no raw `dlopen` calls. Other runtime pieces that cannot work on iOS:
- **MLT** (`CMakeLists.txt:1375-1385`) loads its own modules from `MLT_REPOSITORY` (`krita/main.cc:761` on Android). Disable it with `-DCMAKE_DISABLE_FIND_PACKAGE_Mlt7=ON`.
- **FFmpeg** is run as an external process (`libs/ui/animation/KisFFMpegWrapper.cpp:480`). iOS does not allow `QProcess`.
- **G'MIC** (`plugins/extensions/qmic`) has the same problem.
- **Platform plugins** xcb/wayland are not built on iOS anyway. `loadSinglePlugin` returning `nullptr` is already handled (`KisPlatformPluginInterfaceFactory.cpp:37-44`).

**Resources located relative to the binary:**
- `KoResourcePaths::getInstallationPrefix()` (`libs/resources/KoResourcePaths.cpp:105-153`) has `Q_OS_MACOS`, `Q_OS_HAIKU` and `Q_OS_ANDROID` branches and otherwise returns `applicationDirPath() + "/../"` (`:151`).
  - `Q_OS_MACOS` is not defined on iOS, so iOS takes the fallback. That points outside the `.app` bundle.
  - Add a `Q_OS_IOS` branch that returns the bundle root (`applicationDirPath() + "/"`) and keep `share/` inside the bundle. Writable data must go to `QStandardPaths::AppDataLocation`.
- `KoJsonTrader`'s directory scan (`KoJsonTrader.cpp:43-118`) also depends on `applicationDirPath`. In the static design it is skipped entirely.
- `krita/main.cc:750-752` calls `qFatal` when run from the build directory. Harmless.

### 4.4 Design for iOS: a static plugin registry

**Recommendation.** Use Qt's own static-plugin mechanism: `QT_STATICPLUGIN` + `Q_IMPORT_PLUGIN` + `QPluginLoader::staticPlugins()`. Do not use KF5's `K_IMPORT_PLUGIN`.
- `K_IMPORT_PLUGIN` does exist (verified in `/usr/include/KF5/KCoreAddons/kstaticpluginhelpers.h:12-36`, `@since 5.89`). It registers into KCoreAddons' namespace map, which only `KPluginMetaData::findPlugins()` reads (`kpluginmetadata.h:283`).
- Krita does not use `findPlugins`. It also only requires KF5 ≥ 5.44 (`CMakeLists.txt:21`). I could not check which KF5 version Krita's dependency builds pin, because the dependencies live in an external repo.
- The Qt path needs nothing new. `QStaticPlugin::metaData()` returns the same `{IID, className, MetaData:{...}}` object that `QPluginLoader::metaData()` returns (`qplugin.h:87-111`; `qpluginloader.h:70`). So `KoPluginLoader` and `KisImportExportManager` keep working unchanged.

**(a) CMake: build everything STATIC and collect the plugin targets**

```cmake
# top-level CMakeLists.txt, before add_subdirectory(libs)
option(KRITA_STATIC_BUILD "Link libs and plugins statically (iOS)" ${IOS})
if (KRITA_STATIC_BUILD)
    add_compile_definitions(QT_STATICPLUGIN KRITA_STATIC_PLUGINS)  # global: see pitfall (b)
endif()

macro(kis_add_library)                       # CMakeLists.txt:1076
    cmake_parse_arguments(REAL "" PCH_FILE "" ${ARGV})
    if (KRITA_STATIC_BUILD)
        list(FIND REAL_UNPARSED_ARGUMENTS MODULE _kis_is_plugin)
        list(TRANSFORM REAL_UNPARSED_ARGUMENTS REPLACE "^(SHARED|MODULE)$" "STATIC")
    endif()
    add_library(${REAL_UNPARSED_ARGUMENTS})
    if (KRITA_STATIC_BUILD AND NOT _kis_is_plugin EQUAL -1)
        list(GET REAL_UNPARSED_ARGUMENTS 0 _kis_t)
        set_property(GLOBAL APPEND PROPERTY KRITA_STATIC_PLUGIN_TARGETS ${_kis_t})
    endif()
    ... # existing PCH logic
endmacro()
```

- `list(TRANSFORM)` needs CMake 3.12. Krita already requires 3.19 (`CMakeLists.txt:1`).
- Convert the 4 plain `add_library(... MODULE)` calls listed in 4.2 to `kis_add_library`.
- Put the plugin subdirectories behind an iOS allowlist. `plugins/CMakeLists.txt` and the per-category CMakeLists are plain `add_subdirectory` lists. Wrap them in `if (NOT KRITA_STATIC_BUILD OR <name> IN_LIST KRITA_IOS_PLUGINS)`.
- Always exclude `plugins/qt/designer`, `plugins/extensions/pykrita`, `plugins/extensions/qmic` and `plugins/platforms`.
- `libs`, `qmlmodules` and `plugins` are all added before `krita` (`CMakeLists.txt:1690-1696`), so the global property is complete when `krita/CMakeLists.txt` runs.

**(b) Generated registry.** Generate `krita_static_plugins.cpp` in `krita/CMakeLists.txt`.
- `Q_IMPORT_PLUGIN` needs the **factory class name**, not the target name. For a personal port the simplest option is a hand-maintained map, `cmake/ios/KritaStaticPlugins.cmake`, with entries like `kritalcmsengine=KritaLcmsEngineFactory`. An auto-scan alternative is `file(STRINGS <src> REGEX "K_PLUGIN_FACTORY_WITH_JSON\\(")` over each target's `SOURCES`. Either way, rename the duplicate class names first (pitfall (a) in 4.5).
- Emit:

```cpp
// krita_static_plugins.cpp  (file(GENERATE) / configure_file output)
#include <QtPlugin>
// Krita plugins (one per allowlisted MODULE target)
Q_IMPORT_PLUGIN(KritaLcmsEngineFactory)
Q_IMPORT_PLUGIN(DefaultPaintOpsPluginFactory)
Q_IMPORT_PLUGIN(KritaDefaultToolsFactory)
...
// Qt plugins (or qt5_import_plugins(krita INCLUDE ...))
Q_IMPORT_PLUGIN(QIOSIntegrationPlugin)
Q_IMPORT_PLUGIN(QSQLiteDriverPlugin)
Q_IMPORT_PLUGIN(QSvgIconPlugin)
Q_IMPORT_PLUGIN(QJpegPlugin)

void kritaInitStaticResources()          // must be outside any namespace
{
    Q_INIT_RESOURCE(defaulttools_basic); // one per plugin/lib .qrc, see pitfall (c)
    Q_INIT_RESOURCE(selectiontools);
    Q_INIT_RESOURCE(tool_transform);
    Q_INIT_RESOURCE(sql);                // libs/resources/CMakeLists.txt:62
    Q_INIT_RESOURCE(kxmlgui);            // libs/widgetutils/CMakeLists.txt:123
    ...
}
```

- `Q_IMPORT_PLUGIN` (`qplugin.h:134-142`) defines a static object whose constructor calls `qRegisterStaticPluginFunction()`. Its storage is a `Q_GLOBAL_STATIC` inside QtCore, which is safe to call before `main`.
- The object lives in a translation unit of the executable, so it is always linked. Its reference to `qt_static_plugin_<Class>()` (`qplugin.h:162-181`) pulls the plugin's object file out of its archive.
- Link the file into the `krita` executable together with every allowlisted plugin target: `target_link_libraries(krita PRIVATE ${KRITA_STATIC_PLUGIN_TARGETS})`.

**(c) `main()` and `KisApplication`.**
- In `krita/main.cc`, before `KisApplication app(...)` at `:657`, add `#ifdef KRITA_STATIC_PLUGINS extern void kritaInitStaticResources(); kritaInitStaticResources(); #endif`.
- Nothing else in `KisApplication` has to change. `loadPlugins()` (`KisApplication.cpp:466-480`) still drives the registries in the same order, and the plugin constructors still run lazily, after `QApplication` and KLocalizedString are set up. Keep it that way; see pitfall (b) in 4.5.

**(d) `KoJsonTrader` iterates the static registry instead of scanning.** This is the only loader change. `KoPluginLoader::load` / `loadSinglePlugin` keep their logic, including the version dedupe and blacklist.

> **Status:** implemented in `107eff4`. It is an addition to the directory scan, not a replacement (the scan is skipped only under `KRITA_STATIC_PLUGINS`), so `KoPluginLoaderTest` covers it on Linux. It stores the instance function and cached metadata rather than a `QStaticPlugin`, which keeps it identical on Qt 5 and Qt 6.

```cpp
// KoJsonTrader.h: Plugin gets a second backing
struct Plugin {
    ...
private:
    QSharedPointer<QPluginLoader> m_loader;   // dynamic
    QStaticPlugin m_static {};                // static (KRITA_STATIC_PLUGINS)
    QJsonObject m_metaData;                   // cached, QStaticPlugin::metaData() re-parses each call
    QMutex *m_mutex = 0;
};

// KoJsonTrader.cpp
KoJsonTrader::KoJsonTrader() {
#ifdef KRITA_STATIC_PLUGINS
    initializeStaticPluginCache();   // skip the whole dir search at :35-118
#else
    ... existing ...
#endif
}

void KoJsonTrader::initializeStaticPluginCache() {
    QMutexLocker l(&m_mutex);
    for (const QStaticPlugin &sp : QPluginLoader::staticPlugins()) {
        const QJsonObject md = sp.metaData();
        if (md.value("IID").toString() != QLatin1String(KPluginFactory_iid)) continue; // skip Qt's own plugins
        const QJsonObject json = md.value("MetaData").toObject();
        const QJsonArray serviceTypes = json.value("X-KDE-ServiceTypes").toArray();
        if (serviceTypes.isEmpty()) continue;
        PluginCacheEntry e;
        e.filePath = QStringLiteral("static:") + md.value("className").toString();
        e.serviceTypes = serviceTypes;
        e.mimeTypes = /* same three keys as :170-172 */;
        e.staticPlugin = sp; e.metaData = md;
        m_pluginLoaderCache << e;
    }
}
// Plugin::instance()  -> m_loader ? m_loader->instance() : m_static.instance();
// Plugin::metaData()  -> m_loader ? m_loader->metaData() : m_metaData;
// Plugin::fileName()  -> m_loader ? m_loader->fileName() : <className>;  (used at KisImportExportManager.cpp:263)
// Plugin::errorString -> m_loader ? m_loader->errorString() : QString();
```

- `QStaticPlugin::instance()` returns a singleton factory (`Q_PLUGIN_INSTANCE`, `qplugin.h:152-160`), which matches what `QPluginLoader::instance()` returns.
- `factory->create<>()` still creates a fresh object on each call, so the per-window `ViewPlugin` loads (`KisMainWindow.cpp:404`) behave the same.

**(e) Minimal first set (13 plugins + 2 helper libs).** Target names are verified in each `CMakeLists.txt`.

| Purpose | Directory | Target(s) |
|---|---|---|
| Colour engine (**mandatory**; `KisMainWindow.cpp:3000` quits without it) | `plugins/color/lcms2engine` | `kritalcmsengine` |
| Pixel brush + clone paintops | `plugins/paintops/defaultpaintops` (+ helper `plugins/paintops/libpaintop` → `kritalibpaintop`) | `kritadefaultpaintops` |
| Colour-smudge engine (many default presets use it; optional) | `plugins/paintops/colorsmudge` | `kritacolorsmudgepaintop` |
| Brush, line, rect, ellipse, fill, gradient, move, colour sampler, pan, measure, multibrush | `plugins/tools/basictools` | `kritadefaulttools` |
| Selection tools | `plugins/tools/selectiontools` | `kritaselectiontools` |
| Transform tool | `plugins/tools/tool_transform2` | `kritatooltransform` |
| `InteractionTool` (KoToolManager's fallback tool, `libs/flake/KoToolManager.cpp:291, 796, 843`; provided by `plugins/tools/defaulttool/defaulttool/DefaultToolFactory.cpp:17`) | `plugins/tools/defaulttool` | `krita_flaketools` |
| `.kra` load/save (also autosave) | `plugins/impex/kra` (+ helper `plugins/impex/libkra` → `kritalibkra`) | `kritakraimport`, `kritakraexport` |
| PNG load/save | `plugins/impex/png` | `kritapngimport`, `kritapngexport` |
| Layers docker | `plugins/dockers/layerdocker` | `kritalayerdocker` |
| Brush presets docker | `plugins/dockers/presetdocker` | `kritapresetdocker` |
| Advanced colour selector | `plugins/dockers/advancedcolorselector` | `kritacolorselectorng` |
| Undo history | `plugins/dockers/historydocker` | `kritahistorydocker` |

- The toolbox is not a plugin. It lives in `kritaui` (`KisMainWindow.cpp:409`, `KoToolBoxFactory`).
- Optional second wave: `plugins/tools/tool_crop` (`kritatoolcrop`), `plugins/dockers/overview`, `plugins/dockers/brushhud`, `plugins/impex/jpeg`, `plugins/color/colorspaceextensions` and `plugins/metadata/{exif,xmp}`.

### 4.5 Pitfalls

**(a) Duplicate symbols across plugins. This is the biggest issue.**

> **Status:** the factory names, the three `Plugin` classes and `defaulttools.qrc` are fixed in `9882099`. `KisColorSelector` remains (section 8, step 4).
- Today each plugin is its own `.so`, so the same names in different plugins never meet. In one static image they collide.
- Factory class names. 29 `K_PLUGIN_FACTORY_WITH_JSON` uses share only 7 class names:

  | Name | Count |
  |---|---|
  | `ExportFactory` | 8 |
  | `ImportFactory` | 7 |
  | `PluginFactory` | 4 |
  | `DefaultToolsFactory` | 4 |
  | `PresetDockerPluginFactory` | 2 |
  | `PaletteDockPluginFactory` | 2 |
  | `KisIptcIOPluginFactory` | 2 (xmp copies iptc's name) |

  Locations:
  - `plugins/impex/kra/kra_import.cpp:16`, `kra_export.cpp:32`
  - psd, jxl, exr, heif, ora, rgbe, qml and jp2 under `plugins/impex/*`
  - `plugins/color/lcms2engine/LcmsEnginePlugin.cpp:74`
  - `plugins/tools/defaulttool/Plugin.cpp:14`, `plugins/tools/svgtexttool/Plugin.cpp:23`, `plugins/dockers/svgcollectiondocker/Plugin.cpp:14`
  - `plugins/tools/basictools/default_tools.cc:33`, `tool_knife/ToolKnife.cpp:17`, `tool_lazybrush/tool_lazybrush.cpp:19`, `tool_smart_patch/tool_smartpatch.cpp:19`
  - `plugins/dockers/{brushhud,presetdocker}`, `plugins/dockers/{gamutmask,artisticcolorselector}`
  - `plugins/metadata/{iptc,xmp}`
- With `QT_STATICPLUGIN`, each name produces a global `qt_static_plugin_<Class>()`, and moc generates `<Class>::staticMetaObject`, its vtable and its constructor, so these collide.
- `Q_IMPORT_PLUGIN(ExportFactory)` also cannot say which plugin it means. With lazy archive resolution the outcome is either a "duplicate symbol" link error or, worse, the **wrong or missing plugin chosen silently**.
- Even the minimal set hits this: kra import/export use `ImportFactory`/`ExportFactory`, lcms and defaulttool both use `PluginFactory`, and basictools uses `DefaultToolsFactory`.
- Fix: give all factories unique names, for example `<target>Factory`.
- Plugin-internal classes clash too:
  - `class Plugin` is defined 3 times: `plugins/tools/defaulttool/Plugin.h:12`, `plugins/tools/svgtexttool/Plugin.h:14`, `plugins/dockers/svgcollectiondocker/Plugin.h:12`.
  - `KisColorSelector` (a QObject) is defined twice: `plugins/dockers/advancedcolorselector/kis_color_selector.h:22` and `plugins/dockers/artisticcolorselector/kis_color_selector.h:26`.
  - Same-named inline or template code is an ODR violation that the linker merges silently.
- Recommended discipline: link the allowlisted plugins with `$<LINK_LIBRARY:WHOLE_ARCHIVE,...>` (CMake ≥ 3.24, which uses `-force_load` on Apple). Every clash then becomes a hard link error instead of a silent drop, and you rename until the link is clean.
- Without `QT_STATICPLUGIN`, every plugin exports the same `extern "C" qt_plugin_instance` / `qt_plugin_query_metadata` (`qplugin.h:184-205`). Define it globally, not just on the MODULE targets. `LcmsEnginePlugin.cpp` is compiled into **both** `kritalcmsengine_static` and `kritalcmsengine` from the same `${lcmsengine_SRCS}` (`plugins/color/lcms2engine/CMakeLists.txt:69, 82-83`). In static mode, build that code once: make the plugin target the archive itself, or drop the MODULE.

**(b) Static initialiser order and timing.**
- Today, file-scope initialisers in plugins run at `dlopen` time, after `QApplication`, the KLocalizedString domain and the registries exist. Linked statically, they run **before `main()`**, and only if the linker keeps their object file.
- 32 files use `KIS_DECLARE_STATIC_INITIALIZER` (`libs/global/KisStaticInitializer.h:14-38`). 7 of them are in plugins:
  - `plugins/paintops/mypaint/MyPaintSensorPack.cpp:27` calls `i18n()` and `KisDynamicSensorFactoryRegistry::instance()->add(...)` before main. Translations are then lost and the registry gets touched early.
  - `qmlRegisterType` calls in `plugins/dockers/textproperties/TextPropertiesPlugin.cpp:43` and `plugins/tools/svgtexttool/Plugin.cpp:25`.
  - Metatype registrations in logdocker, channeldocker, recorder and svgtexttool.
- In a static archive, an object file that nothing references is dropped, and its registration silently disappears. Either use WHOLE_ARCHIVE as in (a), or move these bodies into the plugin constructors, which `KoPluginLoader` runs lazily.
- `KisApplication::verifyMetatypeRegistration()` (`libs/ui/KisApplication.cpp:997-1046`, called at `:856`) is a ready-made check for this, but only in builds with safe asserts. It also `qFatal`s on types that plugins register:
  - `SnapshotDirInfoList` from the recorder docker (`plugins/dockers/recorder/recorder_snapshots_scanner.cpp:18`).
  - `TransformTransactionProperties` / `ToolTransformArgs` from `plugins/tools/tool_transform2/tool_transform.cc:46-47`.
  - So it has to be adjusted when the recorder docker is left out.
- Never instantiate plugin factories from a static constructor. Plugin constructors call `Ko*Registry::instance()`, which calls `init()`, which calls `KoPluginLoader::load()`. Keep plugin construction inside `loadPlugins()`. `Q_IMPORT_PLUGIN` only records a function pointer, so it is safe.

**(c) Qt resources in static libraries.**
- `rcc` output registers itself through a file-scope static initialiser. In a static archive nothing references that object file, so it is dropped and `:/...` paths return nothing. That breaks icons, tool cursors and `kxmlgui` `.rc` files.
- Each `.qrc` in a static lib needs `Q_INIT_RESOURCE(<basename>)` from the executable (`kritaInitStaticResources()` above), or WHOLE_ARCHIVE linking.
- `.qrc` files in libraries and plugins:
  - libs: `libs/resources/CMakeLists.txt:62` (sql), `libs/widgetutils/CMakeLists.txt:123` (kxmlgui)
  - `plugins/tools/{basictools:39, defaulttool:30, selectiontools:15, tool_transform2:35, tool_crop:7, tool_polygon:6, tool_polyline:6, svgtexttool:52, karbonplugins/tools:11}`
  - `plugins/dockers/{smallcolorselector:14, textproperties:15}`
  - `plugins/flake/pathshapes:28`
  - `plugins/extensions/spensettings:10`
- The `krita` executable's own `.qrc` files (`krita/CMakeLists.txt:165-194`) are compiled into the executable and are unaffected.
- **Name clash:** `plugins/tools/basictools/defaulttools.qrc` and `plugins/tools/defaulttool/defaulttools.qrc` both generate `qInitResources_defaulttools`. Both are in the minimal set. Rename one, or pass `OPTIONS -name <unique>` to `qt_add_resources`.

**(d) Smaller items:**
- **Duplicate-id dedupe.** `KoPluginLoader::load()` still dedupes by `Id` and version (`KoPluginLoader.cpp:98-109`), so registering a plugin twice is tolerated. A static build no longer needs that.
- **Empty `fileName()`.** Static plugins have no file name, which affects log messages and `KisImportExportManager.cpp:263`. Return the class name.
- **Qt6 status.** The Qt6 static-plugin macros look analogous, using `QT_MOC_EXPORT_PLUGIN` under `QT_STATICPLUGIN`, but that is unverified here because no Qt6 headers are installed.
- **Qt6 QML module.** It is declared `SHARED` (`qmlmodules/components/CMakeLists.txt:8`) and must become `STATIC` plus `Q_IMPORT_QML_PLUGIN(org_krita_componentsPlugin)`. The exact plugin name is unverified.

## 5. OpenGL ES canvas

### 5.1 How the renderer is chosen (runtime)

Krita does **not** pick GL vs GLES with a compile-time switch. It probes at startup with throw-away Qt contexts, picks a `QSurfaceFormat`, and makes that the process default. Compile-time macros only change *which GL tokens and headers* get used.

| Step | Where | What happens |
|---|---|---|
| 1 | `krita/main.cc:249` | `Qt::AA_ShareOpenGLContexts` is set unconditionally. (Note: the file is `main.cc`; there is no `main.cpp`.) |
| 2 | `krita/main.cc:431-436` | Reads the `OpenGLRenderer` key from `kritadisplayrc`. Default is `"angle"` on Windows and `"auto"` everywhere else. `KisOpenGL::convertConfigToOpenGLRenderer` turns it into an enum. |
| 3 | `krita/main.cc:441-444` | `KisOpenGL::selectSurfaceConfig(...)`, then `KisOpenGL::setDefaultSurfaceConfig(config)` |
| 4 | `libs/ui/opengl/kis_opengl.cpp:910` `selectSurfaceConfig` | Builds `renderersToTest`. `RendererDesktopGL` is added only `#ifndef Q_OS_ANDROID` (`:920-922`); `RendererOpenGLES` is always added (`:923`); `RendererSoftware` (WARP) only on Windows (`:925`). |
| 5 | `kis_opengl.cpp:955-959` | Probes `RendererAuto` first. `#ifndef Q_OS_MACOS` (`:961-1000`), if that fails it tries this fallback chain: DesktopGL with compat profile → DesktopGL with the compat profile inhibited → OpenGLES. |
| 6 | `kis_opengl.cpp:1022` `getRendererFromProbeResult` (`:119-136`) | If the probed context reports `isOpenGLES()`, the default renderer becomes `RendererOpenGLES` (or `RendererSoftware` when the renderer string contains "software"/"basic render driver"). |
| 7 | `kis_opengl.cpp:1060-1176` | Probes every candidate, sorts by user preference, Qt preference and colour space (`FormatPositionLess`), and takes the first one that `isSupportedVersion()`. |
| 8 | `kis_opengl.cpp:1191-1210` `setDefaultSurfaceConfig` | `QSurfaceFormat::setDefaultFormat()`. For a GLES config it sets `Qt::AA_UseOpenGLES` (`:1199`); for desktop GL it sets `Qt::AA_UseDesktopOpenGL` (`:1208`). `QT_ANGLE_PLATFORM` is set only on Windows. |
| 9 | `krita/main.cc:671` `KisOpenGL::initialize()` (`kis_opengl.cpp:138`) | Probes the default format once more without touching global state, and caches `openGLCheckResult`. Every `KisOpenGL::has*/supports*` query reads from this cache. |

**Surface format** (`generateSurfaceConfig`, `kis_opengl.cpp:603-669`):
- `determineOpenGLImplementation()` (`:560-601`) maps `QSurfaceFormat::OpenGLES` to `LibGLES` on every non-Windows platform. `DefaultRenderableType` maps to `LibGLES` only `#if defined(QT_OPENGL_ES_2)` (`:588`).
- LibGL: 4.1 Core `#if Q_OS_MACOS` (`:621-624`), otherwise 3.3 Compatibility (`:630-635`).
- **LibGLES: `setVersion(3,0)`, `NoProfile`** (`:645-647`). Depth 24, stencil 8, double buffer, swap interval 0 (`:652-661`).
- `KisOpenGLModeProber::probeFormat` (`libs/ui/opengl/KisOpenGLModeProber.cpp:170-289`) creates a **temporary `QGuiApplication`** (`:224`), a `QWindow` and a `QOpenGLContext` (`:249-269`). It toggles `AA_UseDesktopOpenGL`/`AA_UseOpenGLES` around the probe (`:197-200`).
- Minimum version: `isSupportedVersion()` is `(isOpenGLES && major >= 3) || version >= 3.3` (`KisOpenGLModeProber.h:77-84`). **GLES 2 is rejected.**

**How Android "forces" GLES.** It does so by omission: `RendererDesktopGL` is never put in the test list (`kis_opengl.cpp:920`). Qt for Android is also built `-opengl es2`, so Auto probes yield an ES context. No `AA_UseOpenGLES` is set before the probe on Android.

### 5.2 Macros and CMake

| Macro | Defined by | Used at |
|---|---|---|
| `QT_OPENGL_ES_2` | Qt (`qtgui-config.h`) when built `-opengl es2` (Android, iOS) | `kis_opengl.cpp:588`; `kis_opengl_image_textures.cpp:9,13,569,647,656,689,730,772`; `kis_texture_tile.cpp:37`; `plugins/dockers/lut/ocio_display_filter_vfx2021.cpp:34,39,379` |
| `QT_OPENGL_ES` | Qt | `kis_texture_tile.cpp:13` (skips the `<QOpenGLBuffer>` include) |
| `QT_OPENGL_ES_3` | **Forced by Krita on Android:** `libs/ui/CMakeLists.txt:1-7` (`if (ANDROID) add_definitions(-DQT_OPENGL_ES_3)`, QTBUG-64703). It makes `qopengl.h` include the ES3 headers. | Implicitly needed by `kis_texture_tile.cpp:31-34,44-45` (`GL_TEXTURE_MIN_LOD`, `GL_TEXTURE_SWIZZLE_R`), `KisOpenGLSync.cpp` (`GLsync`, `GL_SYNC_GPU_COMMANDS_COMPLETE`), and `GL_RGBA16F`/`GL_HALF_FLOAT`/`GL_RGBA32F` in `kis_opengl_image_textures.cpp`; `ocio_display_filter_vfx2021.cpp:39` |
| `QT_OPENGL_DYNAMIC`, `QT_OPENGL_ES_2_ANGLE` | Qt (Windows) | `kis_opengl_image_textures.cpp:39` (EGL include) |
| `EGL_ANGLE_platform_angle` | EGL headers (Windows/ANGLE) | `kis_opengl_image_textures.cpp` 16-bit int branches → fall back to RGBA16F |
| `QT_OPENGL_3`, `QT_OPENGL_3_2` | Qt (desktop only) | OCIO `ocio_display_filter_vfx2021.cpp:339-370` |
| `HAVE_HDR` | `CMakeLists.txt:720-750` (compile test on `QSurfaceFormat` colour spaces / `QOpenGLWidget::setTextureColorSpace`) | `kis_opengl.cpp:934,1042` |
| *(none)* `KIS_OPENGL_ES`, `HAVE_GLES` | **These do not exist** in the tree. | |

CMake has no GLES detection of its own. With Qt5 it only checks that `Qt5Gui_OPENGL_IMPLEMENTATION` is set (`CMakeLists.txt:1399-1405`); on iOS this reports `GLESv2`. With Qt6 it requires the `OpenGL` and `OpenGLWidgets` components (`CMakeLists.txt:585-586`).

### 5.3 Shaders / GLSL ES

- Sources are in `krita/data/shaders/*.vert|*.frag` (Qt resource `shaders.qrc`). There are `*_legacy` variants for GL 2.1-era paths.
- The version header is prepended at runtime in `KisOpenGLShaderLoader::loadShader` (`libs/ui/opengl/kis_opengl_shader_loader.cpp:44-123`):
  - GLES: `#version 300 es` (`:54,80`). If `supportsLoD()`, it adds `#extension GL_EXT_shader_texture_lod : enable`. It also adds `precision mediump float; precision mediump sampler3D;` and `#define texture2D texture` / `texture3D texture` (`:80-97`).
  - macOS desktop: `#version 150 core`; other desktop: `#version 130`/`120` (`:56-63,98-104`).
- **So GLSL ES 3.00 is required, and iOS ES 3.0 is sufficient.** `mediump float` maps to real fp16 on Apple GPUs (Mali on Android does the same). That can show up as texture-coordinate precision artefacts on very large canvases or at deep zoom. Things to watch: changing to `highp` is a one-line change at `:85-87`.

### 5.4 What changes when the context is GLES

| Feature | Rule on GLES | Where |
|---|---|---|
| 8-bit texture format | Under `QT_OPENGL_ES_2` it always uses `GL_RGBA8`/`GL_RGBA` and swaps R/B with `GL_TEXTURE_SWIZZLE_*` (needs ES3). Otherwise BGRA8_EXT when `GL_EXT_texture_format_BGRA8888` is present. | `kis_opengl_image_textures.cpp:643-675`, `kis_texture_tile.cpp:37-46` |
| Half float (F16 images) | Under `QT_OPENGL_ES_2`: `GL_RGBA16F`/`GL_HALF_FLOAT` if major ≥ 3, otherwise the OES/EXT half-float extensions, otherwise RGBA32F | `kis_opengl_image_textures.cpp:562-640` |
| Float32 images | Under `QT_OPENGL_ES_2`: `GL_RGBA32F` if major ≥ 3. **GLES3 core cannot linear-filter RGBA32F** unless `OES_texture_float_linear` is present. This is unverified on iOS and could show as black or incomplete textures; check on a device. | `kis_opengl_image_textures.cpp:686-728` |
| 16-bit int images | Desktop: `GL_RGBA16`. ES: `GL_RGBA16_EXT` only with `GL_EXT_texture_norm16`, which iOS does not expose (to verify), so these images fall back to an 8-bit display texture. | `:729-800` |
| LoD (mipmapped zoom-out) | `supportsLoD = major >= 3 \|\| GL_EXT_shader_texture_lod`, so it is on for ES3 | `KisOpenGLModeProber.cpp:437` |
| Fences | `supportsFenceSync = major >= 3`. Function pointers are resolved only `#if Q_OS_WIN` / `#elif Q_OS_LINUX \|\| Q_OS_MACOS` (Android counts as LINUX). | `KisOpenGLModeProber.h:108`, `KisOpenGLSync.cpp:39-66` |
| PBO / buffer mapping | `supportsBufferMapping = !ES \|\| major >= 3 \|\| OES_mapbuffer…`, so it is on for ES3 | `KisOpenGLModeProber.cpp:428-432` |
| Buffer invalidation | `!m_isOpenGLES && …`, so **always off on GLES** | `KisOpenGLModeProber.cpp:434-436`, `kis_opengl.cpp:313-316` |
| Texture buffers | Force-disabled only for ANGLE (Windows) | `kis_opengl.cpp:151-174` |
| VAO | Needs version ≥ 3.0 | `KisOpenGLModeProber.h:90-102` |
| OCIO LUT docker | GLES path uses `QOpenGLExtraFunctions` when major ≥ 3. 1D LUT textures are not supported on GLES. | `ocio_display_filter_vfx2021.cpp:316-338,609` |
| Mirror-axis MSAA | Runtime-guarded by an extension check, but the `GL_MULTISAMPLE_EXT` token must compile | `libs/ui/canvas/kis_mirror_axis.cpp:36-40,160-170` |
| Context-switch lock (Qt5) | Forced on `Q_OS_MACOS \|\| Q_OS_ANDROID`; textures are uploaded in the painting context | `libs/ui/opengl/KisOpenGLContextSwitchLock.cpp:18` |

### 5.5 iOS: what is different and which guards to extend

iOS facts:
- Qt for iOS is always built `-opengl es2`, so `QT_OPENGL_ES_2` and `QT_OPENGL_ES` are defined.
- `QIOSContext` wraps an `EAGLContext` with a sharegroup. There is no desktop GL, no ANGLE and no EGL. It ignores `renderableType` and tries ES3 when `majorVersion() >= 3`.
- `Q_OS_IOS` defines `Q_OS_DARWIN`, `Q_OS_UNIX` and `Q_OS_MAC` (the Darwin-wide alias). It does **not** define `Q_OS_MACOS` or `Q_OS_LINUX`.
- CMake `APPLE` is true on iOS, and `IOS` is set when `CMAKE_SYSTEM_NAME=iOS`.

| # | File:line | Current | Change for iOS | Why |
|---|---|---|---|---|
| 1 | `libs/ui/CMakeLists.txt:1-7` | `if (ANDROID) add_definitions(-DQT_OPENGL_ES_3)` | `if (ANDROID OR IOS)`. First run `grep QT_OPENGL_ES_3 <qt>/include/QtGui/qtgui-config.h`; if Qt already defines it, skip this to avoid a macro-redefinition warning. | Without it, `qopengl.h` pulls `<OpenGLES/ES2/gl.h>`, and the ES3 tokens/types listed in 5.2 fail to compile. |
| 2 | `libs/ui/opengl/kis_opengl.cpp:920` | `#ifndef Q_OS_ANDROID` adds RendererDesktopGL | `#if !defined(Q_OS_ANDROID) && !defined(Q_OS_IOS)` | A "DesktopGL" probe on iOS would still return an ES context (`QIOSContext` ignores the type), so a fake DesktopGL entry would show up in the renderer list and in Preferences. |
| 3 | `kis_opengl.cpp:961` | `#ifndef Q_OS_MACOS` desktop-GL fallback chain | `#if !defined(Q_OS_MACOS) && !defined(Q_OS_IOS)`. Alternatively, on iOS short-circuit all of `selectSurfaceConfig` to `return generateSurfaceConfig(RendererOpenGLES, {Default,8}, enableDebug, true);` | Pointless desktop probes. Each probe also builds and destroys a **temporary `QGuiApplication`** (`KisOpenGLModeProber.cpp:224`); that is untested on iOS, where `UIApplicationMain` owns the process. The short-circuit removes that risk. |
| 4 | `libs/ui/opengl/KisOpenGLSync.cpp:55` | `#elif defined Q_OS_LINUX \|\| defined Q_OS_MACOS` | add `\|\| defined Q_OS_IOS` | Otherwise there are no fence function pointers ("Could not find sync functions") and fence-based upload throttling is off. `QIOSContext::getProcAddress` uses `dlsym`, so `glFenceSync` resolves. |
| 5 | `libs/ui/opengl/KisOpenGLContextSwitchLock.cpp:18` | `Q_OS_MACOS \|\| Q_OS_ANDROID` | add `\|\| Q_OS_IOS` (Qt5 only) | EAGL shared contexts have separate command queues, the same problem the macOS comment describes. |
| 6 | `libs/ui/canvas/kis_mirror_axis.cpp:36-40` | `#ifdef Q_OS_MACOS #define GL_MULTISAMPLE_EXT GL_MULTISAMPLE` | add `#ifndef GL_MULTISAMPLE_EXT` / `#define GL_MULTISAMPLE_EXT 0x809D` | Apple's ES headers likely lack `EXT_multisample_compatibility` (verify), which would be a compile error at `:169,234`. |
| 7 | `kis_opengl_image_textures.cpp:45-66`, `kis_texture_tile.cpp:17-23` | local `#ifndef` fallbacks for BGRA/RGBA16_EXT | add `#ifndef` fallbacks for `GL_RGBA16F_EXT` (0x881A), `GL_HALF_FLOAT_OES` (0x8D61), `GL_RGBA32F_EXT` (0x8814), `GL_RGB32F_EXT` (0x8815), `GL_R32F_EXT`/`GL_RED_EXT`/`GL_TEXTURE_WRAP_R_OES` (OCIO `:34-43`) if Apple's `ES3/glext.h` lacks them | Android's NDK `gl2ext.h` is a superset of Apple's headers. Lines `:606-616` and OCIO `:34-43` reference these tokens. |
| 8 | `krita/main.cc:447` | `#if Q_OS_WIN \|\| Q_OS_MACOS` sets `QT_WIDGETS_RHI_BACKEND=opengl` | add `Q_OS_IOS` (Qt6 builds) | The Qt6 iOS default RHI is Metal. `QOpenGLWidget` composition needs the OpenGL (ES) RHI. |
| 9 | `kis_opengl_shader_loader.cpp:85-87` | `precision mediump float` | optionally `highp` on iOS | fp16 precision (see 5.3) |

No change is needed for:
- `KisOpenGLCanvasRenderer.h:13-36`, `KisOpenGLSync.h:10-14`, `libs/ui/canvas/kis_display_filter.h:18-21`. They use `QOpenGLFunctions_3_2_Core` only under `Q_OS_MACOS`, so iOS correctly gets `QOpenGLFunctions`.
- `kis_opengl_canvas2.cpp:110-114`. iOS gets `WA_AcceptTouchEvents=true`, which is what you want.
- `KisScreenInformationAdapter.cpp`, which is Windows-only.

**Would it compile as-is with `QT_OPENGL_ES_2`?**
- **Mostly yes.** The Android build already compiles exactly these `QT_OPENGL_ES_2` branches, and every desktop-only token sits behind `#ifndef QT_OPENGL_ES_2` or `Q_OS_MACOS`.
- The blockers are header-level, not logic-level:
  - (a) `QT_OPENGL_ES_3` must be defined (item 1), or ES3 tokens such as `GL_TEXTURE_SWIZZLE_R`, `GL_TEXTURE_MIN_LOD`, `GLsync` and `GL_HALF_FLOAT` are missing.
  - (b) Some `_EXT`/`_OES` tokens may be absent from Apple's `OpenGLES/ES3/glext.h` (items 6-7).
- `PFNGLINVALIDATEBUFFERDATAPROC` is self-typedef'd with a `GL_APIENTRYP` fallback (`kis_opengl.cpp:53-63`), so it is fine.
- Runtime selection already works through the "ES context ⇒ RendererOpenGLES" logic. Items 2, 3 and 4 are about correctness and robustness, not compilation.

### 5.6 Tablet input (Apple Pencil)

**Pipeline.** Krita has no custom tablet event class (no `KisTabletEvent` in the current tree). It consumes plain `QTabletEvent`.

| Stage | File:line |
|---|---|
| Event filter on canvas: `TabletPress/Move/Release` | `libs/ui/input/kis_input_manager.cpp:599-660`; proximity `kis_input_manager_p.cpp:274-281` |
| Mouse/touch suppression while the pen is active | `libs/ui/input/KisInputEventsEater.cpp:236-300` (proximity, hover, press and synthetic-mouse blocking) |
| Wrapping into `KoPointerEvent` | `libs/flake/KoPointerEvent.cpp:67-70` (ctor), `pressure()` `:307-325`, `rotation()` `:328-346`, `tangentialPressure()` `:349-360`, `xTilt()` `:363` |
| Into paint info (pressure curve, tilt, rotation) | `libs/ui/tool/kis_painting_information_builder.cpp:131-134,160` |
| Debug | `libs/ui/input/kis_tablet_debugger.cpp` (Ctrl+Shift+T logs raw events; use it first on device) |
| No event compression | `krita/main.cc:842` `AA_CompressHighFrequencyEvents=false` |

**Android-specific bits that iOS should share:**

| File:line | Android behaviour | Recommendation for iOS |
|---|---|---|
| `libs/ui/input/kis_shortcut_matcher.cpp:201-206` | `actionsSuppressed()` ignores `cursorEntered`: when the pen is not over the canvas there is no Enter/Leave | extend to `Q_OS_IOS`. Touch platforms do not deliver reliable `QEvent::Enter`, and canvas actions could stay suppressed. |
| `libs/ui/input/kis_input_manager.cpp:568-579` | Enter/Leave handling compiled out | extend to `Q_OS_IOS` |
| `libs/ui/input/kis_input_manager_p.cpp:63-66` | Xiaomi multi-finger-cancel workaround | not needed |
| `libs/ui/kis_config.cc:1614` | steeper default pressure curve on Xiaomi | not needed |
| `kis_config.cc:2471` (kinetic scrolling gesture = left button), `:2999` (long-press enabled by default) | touch-UI defaults | extend to `Q_OS_IOS` |

**What Qt on iOS gives you, and the gaps:**
- Qt's `quiview.mm` turns `UITouchTypeStylus` touches into `QTabletEvent`. It sets pressure = `force / maximumPossibleForce` and derives `xTilt`/`yTilt` from `altitudeAngle`/`azimuthAngle`. That flows through `KoPointerEvent` unchanged, so pressure and tilt should work with no Krita change.
- Qt does not fill these, so they read 0:
  - `rotation()`: Pencil Pro roll angle, iOS 17.5+
  - `tangentialPressure()`
- There is no `QTabletEvent::Eraser` pointer type, so automatic eraser switching never fires.
- Pencil double-tap/squeeze (`UIPencilInteraction`) is not delivered. Mapping it to e.g. "toggle eraser" needs a small Objective-C++ hook.
- Proximity/hover:
  - Qt5 iOS sends no `TabletEnterProximity`/`LeaveProximity`, so `tabletIsInProximity` in `KisInputEventsEater` stays false and only `tabletIsPressed` blocks synthesized mouse events. That is fine.
  - Pencil hover (M2+ iPads) depends on the Qt version; check it with the tablet debugger.
- Qt does not use `coalescedTouchesForTouch:` or predicted touches, so you get frame-rate samples (120 Hz on ProMotion), not 240 Hz. Improving that means patching Qt, not Krita.
- `KisInputEventsEater.cpp:187,260,277` are `Q_OS_MACOS`-only touchpad and hover workarounds. They do not apply to iOS. The line-271 guard is `#ifndef Q_OS_MAC`, and `Q_OS_MAC` *is* defined on iOS (Darwin alias), so synthetic mouse events are not blocked by the source check there. Verify that on device; switch it to `Q_OS_MACOS` if pen strokes get duplicated by mouse events.

---

## 6. Resources and user files

### 6.1 Where things live

| What | Function / site | Default path source | iOS result (Qt's iOS `QStandardPaths` mapping; `<APP>` = sandbox container) |
|---|---|---|---|
| User resource folder ("ResourceDirectory") | `KoResourcePaths::getAppDataLocation()` `libs/resources/KoResourcePaths.cpp:220-286` | config key `ResourceDirectory` (`KisResourceLocator::resourceLocationKey`, `libs/resources/KisResourceLocator.cpp:47`), else `AppDataLocation` (`:229`) | `<APP>/Library/Application Support/krita`, **not visible in Files** |
| Typed save locations (`saveLocation("data", …)`, e.g. fonts `libs/flake/text/KoFontRegistry.cpp:146`) | `KoResourcePaths::saveLocationInternal` `KoResourcePaths.cpp:682-724` | reads the config key **directly** (`:690-693`), else `writableLocation(type)` + `/krita` (`:700-706`, skipped on Android) | same as above |
| Resource cache DB `resourcecache.sqlite` | `KisApplication::registerResources` `libs/ui/KisApplication.cpp:446-455`, `KisResourceCacheDb::initialize` `libs/resources/KisResourceCacheDb.cpp:480` | `getAppDataLocation()`, except on Android, where it is `AppDataLocation` (`:448-451`) | resource folder |
| Bundled read-only resources | `KoResourcePaths::getApplicationRoot()` → `getInstallationPrefix()` `KoResourcePaths.cpp:105-152`, plus `"/share/krita"` (`KisApplication.cpp:457`) | macOS: bundle detection (`:106-142`); Haiku: `appDir/` (`:143-144`); Android: `AppDataLocation[1]` (`:145-149`); else `applicationDirPath()+"/../"` (`:151`) | `Krita.app/../`, **wrong**, see 6.7 |
| kritarc, kritadisplayrc | `GenericConfigLocation` (`krita/main.cc:362`) | | `<APP>/Library/Preferences` |
| Autosave | `KisAutoSaveRecoveryDialog::autoSaveLocation` `libs/ui/KisAutoSaveRecoveryDialog.cpp:274-290` | Android: `DocumentsLocation + "/krita-backup"` (`:279-284`); others: `QDir::homePath()` | `<APP>` (hidden) |
| Dialog default dirs | ~40 `setDefaultDir(writableLocation(Pictures/Home/Download/Documents))` calls | | Pictures → `<APP>/Documents/Pictures`, Download → `<APP>/Documents/Downloads` (visible); Home → `<APP>` (not visible) |

`QStandardPaths` usage overall:
- 62 non-test source files, 136 `writableLocation` calls.
- Location counts: AppDataLocation 65, GenericConfigLocation 30, PicturesLocation 22, HomeLocation 19, GenericDataLocation 13, CacheLocation 5, TempLocation 5, DocumentsLocation 3, DownloadLocation 3.
- `QStandardPaths::locate` with `AppDataLocation` is also the first lookup for bundled resources (`KoResourcePaths.cpp:445,449,538,544,597,630,667`).

**Custom-location machinery that already exists.** When `getAppDataLocation() != writableLocation(AppDataLocation)`:
- `cleanup()`/`cleanupDirs()` drop paths under the standard AppData dir (`KoResourcePaths.cpp:38-78`).
- `findExtraResourceDirs()` adds the custom dir (`:755-772`).

So redirecting the folder is a supported configuration, not a hack.

### 6.2 KisResourceLocator: first run and storages

- `KisResourceLocator::initialize(installationResourcesLocation)` (`libs/resources/KisResourceLocator.cpp:94`):
  - `d->resourceLocation = KoResourcePaths::getAppDataLocation()` (`:98`).
  - mkpath and writability check (`:102-114`).
  - Version file `KRITA_RESOURCE_VERSION` (`:117-133`).
  - `firstTimeInstallation` (`:136`), then `synchronizeDb()` (`:143`).
- `firstTimeInstallation` (`:1042-1093`):
  - Creates one subfolder per resource type.
  - **Copies** loose resources from `<appRoot>/share/krita/<type>/` (`:1057-1069`).
  - **Copies** every `*.bundle/*.abr/*.asl` found under `<appRoot>/share/krita` into the resource-folder root (`:1072-1082`).
- `findStorages()` (`:1095-1135`) adds:
  - the folder storage
  - the `memory` storage
  - the `fontregistry` storage
  - every `*.bundle/*.abr/*.asl` under the resource folder, found recursively with `QDirIterator` (`:1117-1126`)

  So a bundle dropped into the folder through the Files app is picked up on the next launch.
- DB paths are stored **relative** to the resource folder for bundles (`makeStorageLocationRelative`/`Absolute`, `:1207-1304`), so a moving container path does not break them.

### 6.3 Android file handling (content://)

| Class / site | Purpose |
|---|---|
| `libs/ui/KisAndroidFileProxy.{h,cpp}`: `getFileFromContentUri()` (`KisAndroidFileProxy.cpp:15-34`) | Copies a `content://` file into `CacheLocation` for APIs that need a real path. Its only caller is MLT, `libs/ui/KisPlaybackEngineMLT.cpp:413`. |
| `libs/global/KisAndroidUtils.{h,cpp}`: `performInitialSetup()` (`KisAndroidUtils.cpp:24-35`, called at `krita/main.cc:220`) | Runs the JNI `copyAssets()` step. `packaging/android/apk/src/org/krita/android/ConfigsManager.java:67-111,159` copies the APK assets into `getFilesDir()` (`:272`), which is what `getInstallationPrefix()` returns on Android. |
| `KisAndroidUtils::copyFile` / `copyFileToTemporary` (`KisAndroidUtils.h:41-46`) | `QFile::copy` replacement for sandboxed URIs; used by `KisAndroidMediaEncoderRunnable.cpp:1019`, `KisAsyncAnimationFramesSavingRenderer.cpp:125`, `KisVideoSaver.cpp:106` |
| `libs/ui/KisDocument.cpp:1909-1915` | Autosave for a `content://` document goes to `autoSaveLocation()` |
| `KoFileDialog` Android branches | native picker (`libs/widgetutils/KoFileDialog.cpp:156-158`), save-as type chooser (`:266-297`), no suffix fix-ups (`:311,358,594`) |
| `libs/ui/dialogs/kis_dlg_preferences.cc:605+,3141-3147` | Android resource-folder combo box instead of the free path field |

iOS needs none of the content-URI code: the sandbox is a normal POSIX filesystem. The only analogue is **security-scoped URLs** for files opened in place from other providers. Krita's macOS equivalent, `libs/macosutils/KisMacosSecurityBookmarkManager.mm` (hooked in `KoFileDialog.cpp:146-151`), is `Q_OS_MACOS`-only and AppKit-based.

### 6.4 File dialogs

**Central wrapper: `KoFileDialog`.**
- Declared at `libs/widgetutils/KoFileDialog.h:21`.
- Implemented in `libs/widgetutils/KoFileDialog.cpp`: `createFileDialog()` `:138-258`, `filename()` `:261-370`, `filenames()` `:372-384`.
- It instantiates `KisPreviewFileDialog` (`libs/widgetutils/KisPreviewFileDialog.cpp:43`, a `QFileDialog` subclass), so it is the only real `QFileDialog` construction in Krita proper.
- Native vs non-native: `dontUseNative` defaults to `true` and is set false on Android/macOS/Windows/KDE (`:155-170`). iOS therefore gets Qt's **widget-based dialog** by default. That dialog can browse only the sandbox (fine for a Documents-centric workflow). You can override it with the `[File Dialogs] DontUseNativeFileDialog` key.

Secondary wrappers, which all end in KoFileDialog:
- `KisFileNameRequester` (`libs/widgets/kis_file_name_requester.cpp:16,83`; used in 11 files/.ui)
- `libkis` `FileDialog` (`libs/libkis/FileDialog.cpp:23,87`) for Python plugins (`plugins/python/{scripter,workflow_buttons,tenscripts}`)

Use-site counts (non-test):

| Kind | Count | Sites |
|---|---|---|
| `KoFileDialog` instantiations | **62** in 52 files | listed below |
| Direct `QFileDialog` | **4** | `KisPreviewFileDialog.cpp:43` (the wrapper itself); `plugins/impex/raw/3rdparty/libkdcraw/src/rwidgetutils.cpp:407` (RAW ICC picker); `plugins/extensions/pykrita/plugin/krita/sceditor/mainwindow.py:147,163` (Python) |

The most important KoFileDialog sites:
- Open: `KisMainWindow.cpp:1225` (`showOpenFileDialog`), `KisOpenPane.cpp:183`
- Save As: `KisMainWindow.cpp:1421`
- Bundle import: `plugins/extensions/resourcemanager/dlg_bundle_manager.cpp:219`
- Resource import: `ResourceImporter.cpp:118`
- Resource folder preference: `kis_dlg_preferences.cc:681` (via `KisFileNameRequester`)

<details><summary>All 62 KoFileDialog sites</summary>

`libs/ui/KisPaletteEditor.cpp:140`, `libs/ui/KisMainWindow.cpp:1225,1421,2769`, `libs/ui/KisOpenPane.cpp:183`, `libs/ui/KisImportExportManager.cpp:289,310`, `libs/ui/kis_node_manager.cpp:1294,1363`, `libs/ui/dialogs/kis_dlg_layer_style.cpp:377,443`, `libs/ui/dialogs/KisDlgSavePreset.cpp:103`, `libs/ui/dialogs/kis_dlg_import_image_sequence.cpp:138`, `libs/ui/dialogs/kis_dlg_preferences.cc:681,1189,1556`, `libs/ui/KisViewManager.cpp:988`, `libs/ui/animation/KisDlgAnimationRenderer.cpp:1020,1029`, `libs/ui/animation/KisDlgImportVideoAnimation.cpp:350,554,575`, `libs/ui/kis_image_manager.cc:106`, `libs/ui/KisTemplateCreateDia.cpp:376`, `libs/ui/kis_custom_pattern.cc:100`, `libs/ui/widgets/kis_advanced_color_space_selector.cc:798`, `libs/ui/widgets/kis_color_space_selector.cc:196`, `libs/resourcewidgets/KisResourceItemChooser.cpp:335`, `libs/libkis/FileDialog.cpp:23,87`, `libs/widgetutils/xmlgui/kshortcutschemeseditor.cpp:155,171,189,210`, `libs/widgets/kis_file_name_requester.cpp:83`, `libs/widgets/KoEditColorSetDialog.cpp:186`, `plugins/extensions/resourcemanager/ResourceImporter.cpp:118`, `plugins/extensions/resourcemanager/page_metadata_info.cpp:106`, `plugins/extensions/resourcemanager/dlg_bundle_manager.cpp:219,286`, `plugins/extensions/resourcemanager/page_bundle_saver.cpp:93`, `plugins/extensions/imagesplit/imagesplit.cpp:169,244`, `plugins/extensions/buginfo/dlg_buginfo.cpp:76`, `plugins/paintops/libpaintop/kis_predefined_brush_chooser.cpp:367`, `plugins/generators/seexpr/kis_wdg_seexpr_presets_save.cpp:102`, `plugins/dockers/logdocker/LogDockerDock.cpp:218`, `plugins/dockers/lut/lutdocker_dock.cpp:477,733`, `plugins/dockers/recorder/recorder_export.cpp:446,731`, `plugins/dockers/recorder/recorderdocker_dock.cpp:729`, `plugins/dockers/compositiondocker/compositiondocker_dock.cpp:250,368`, `plugins/dockers/palettedocker/palettedocker_dock.cpp:228`, `plugins/assistants/Assistants/kis_assistant_tool.cc:1437,1671`, `plugins/impex/libkra/kis_kra_loader.cpp:1156`, `plugins/impex/libkra/kis_kra_load_visitor.cpp:152`, `plugins/tools/defaulttool/referenceimagestool/ToolReferenceImages.cpp:104,180,231`
</details>

### 6.5 Bundle import paths

| Entry point | File:line | Destination |
|---|---|---|
| Manage Resource Libraries → Import | `plugins/extensions/resourcemanager/dlg_bundle_manager.cpp:217-273` (KoFileDialog with mime `application/x-krita-bundle`, `.abr`, `.asl`; default dir `DownloadLocation`) | `QFile::copy` to `getAppDataLocation()/<name>` (`:247-264`), then `KisResourceLocator::addStorage` (`:267-271`) |
| Generic resource import / brush chooser | `KisStorageModel::importStorageInternal` `libs/resources/KisStorageModel.cpp:438-490`; callers `plugins/extensions/resourcemanager/ResourceImporter.cpp:170`, `plugins/paintops/libpaintop/kis_predefined_brush_chooser.cpp:373` | `getAppDataLocation()/<name>` (`:445-447`), copy or `QSaveFile` |
| Drag onto welcome page / command line / file-open event | `KisWelcomePageWidget.cpp:427-428`, `KisApplication.cpp:799-800` → `KisMainWindow::installBundle` `libs/ui/KisMainWindow.cpp:1291-1299` | copy to `getAppDataLocation()`; it does **not** call `addStorage`, so the bundle is picked up at the next start by `findStorages()` |
| Shipped bundles | `krita/data/bundles/CMakeLists.txt:1-17` → `share/krita/bundles` (Android skips `Krita_3_Default_Resources.bundle`, `:8-13`) | copied into the resource folder on first run (`KisResourceLocator.cpp:1072-1082`) |

There is no `KisResourceBundle` or `KisDlgImportBundle` class in the current tree. Bundles are read by `KisBundleStorage` (`libs/resources/KisBundleStorage.cpp`) through `KisResourceStorage`.

### 6.6 Proposed minimal iOS change: resource folder in Documents

Info.plist (iOS-specific; `krita/Info.plist.template` is macOS-only and is wired in at `krita/CMakeLists.txt:221-232` under `if (APPLE)`, which is also true on iOS, so give iOS its own plist):
`UIFileSharingEnabled=YES`, `LSSupportsOpeningDocumentsInPlace=YES`, plus `CFBundleDocumentTypes`/`UTExportedTypeDeclarations` for `.kra` and `.bundle`.

**The one function to change: `KoResourcePaths::getAppDataLocation()`, `libs/resources/KoResourcePaths.cpp:220`.**

```cpp
QString KoResourcePaths::getAppDataLocation()
{
    if (!s_overrideAppDataLocation.isEmpty()) {
        return s_overrideAppDataLocation;
    }
#ifdef Q_OS_IOS
    // The container path (<...>/Application/<UUID>/) may change on reinstall/update,
    // so never trust a persisted absolute path; always recompute it.
    return QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)
           + QStringLiteral("/Resources");   // or no suffix to use Documents root
#endif
    ...
```

Why this one function:
- 16 call sites go through it. They include `KisResourceLocator::initialize` (`KisResourceLocator.cpp:98`), the DB location (`KisApplication.cpp:447`), all three bundle import paths (6.5), `KisStorageModel.cpp:445`, `KoDocumentInfo.cpp:255` (author info), `kis_input_profile_manager.cpp:442` and `kis_dlg_layer_style.cpp:334,408`.
- The existing custom-location logic (6.1) then adds it to the search dirs automatically.
- Using a `Resources/` subfolder keeps Krita's ~30 type folders out of the Documents root, where users will keep `.kra` files.

Small companion edits so everything agrees:
1. `KoResourcePaths::saveLocationInternal` `KoResourcePaths.cpp:690-693`. It reads `ResourceDirectory` straight from config, so under `#ifdef Q_OS_IOS` use `path = getAppDataLocation();` there. Otherwise `saveLocation("data", "/fonts/")` and similar keep writing to Library/Application Support. Alternative with zero code in `KoResourcePaths`: in `main.cc`, write `ResourceDirectory=<Documents>/Resources` into kritarc on **every** launch (this also handles the UUID drift).
2. `libs/ui/KisApplication.cpp:446`: change `#ifndef Q_OS_ANDROID` to `#if !defined(Q_OS_ANDROID) && !defined(Q_OS_IOS)`. That keeps `resourcecache.sqlite` in `<APP>/Library/Application Support`, out of the user-visible, user-deletable Files folder.
3. `libs/ui/dialogs/kis_dlg_preferences.cc:580-592,887,3141-3147`: hide `m_urlResourceFolder` on iOS, because the setting is ignored.
4. Optional: `libs/ui/KisAutoSaveRecoveryDialog.cpp:279` (extend the Android branch to iOS, giving `Documents/krita-backup`) and `KisApplication.cpp:386` (handle `QEvent::FileOpen` under `Q_OS_IOS`/`Q_OS_DARWIN` as well; verify that your Qt version maps `application:openURL:` to `QFileOpenEvent`), so "Open in Krita" from Files works.

Side effect to know about: the first run copies the shipped `.bundle` files (≈ tens of MB) into `Documents/Resources`. They are visible there and can be deleted. If a user deletes them, `KRITA_RESOURCE_VERSION` prevents a re-copy until the next version bump. Consider dropping `Krita_3_Default_Resources.bundle` on iOS as Android does (`krita/data/bundles/CMakeLists.txt:8`).

### 6.7 Bundled read-only resources and the .app layout

- Lookup root: `getApplicationRoot()` = `getInstallationPrefix()` (`KoResourcePaths.cpp:105-152`). The resource search falls back to `<root>/share/<alias>` and `<root>/share/krita/<alias>` (`:455-472`, `:557-560`, `:632`, `:650`, `:671`). `QStandardPaths::locate(AppDataLocation, …)` is tried first.
- Other users of the root:
  - `KisResourceLocator::initialize(<root>/share/krita)` (`KisApplication.cpp:457`)
  - fontconfig `<root>/etc/fonts` (`libs/flake/text/KoFontRegistry.cpp:131`) and, on Android, `<root>/share/etc/fonts` (`krita/main.cc:299`)
  - locale `root + "share/locale"` (`krita/main.cc:708`, Qt5 or Win/mac)
  - welcome-page banners (`KisWelcomePageWidget.cpp:838,955`)
- On iOS, `getInstallationPrefix()` falls into the generic `#else`, `applicationDirPath() + "/../"` (`:151`). An iOS `.app` is **flat**, with the executable at `Krita.app/krita`, so this resolves to the container's `Bundle/Application/<UUID>/`, outside the bundle, and nothing is found.
- **Fix:** add `#elif defined(Q_OS_IOS)` and `return qApp->applicationDirPath() + "/";`, mirroring the Haiku branch at `:143-144`. Then ship `Krita.app/share/krita/...`, `Krita.app/share/locale`, `Krita.app/etc/fonts` (or set `FONTCONFIG_PATH` the way Android does at `main.cc:298-301`).
- The `.app` is readable in place, so unlike Android there is no asset-copy step, apart from Krita's own first-run copy into the user folder.
- Plugins: `KoJsonTrader` starts from `applicationDirPath().cdUp()` (`libs/koplugin/KoJsonTrader.cpp:42-53`) and looks for `lib*/kritaplugins` or `*PlugIns*` (macOS). On iOS, skip the `cdUp()` (as with `#ifdef Q_OS_ANDROID`, but in the opposite direction), or link plugins statically.
- Other Android guards in `libs/` worth reviewing for iOS: 274 `Q_OS_ANDROID` sites across `libs`/`plugins`/`krita`. Many are JNI-only, so a blanket `|| Q_OS_IOS` is wrong. A `KRITA_MOBILE_UI`-style helper macro for the UI-behaviour subset (fusion style `KisApplication.cpp:253`, `AA_DontUseNativeMenuBar` `main.cc:688-690`, `setAnimated(false)` `KisMainWindow.cpp:387`, fixed-size main window `KisMainWindow.cpp:639`, `kis_config.cc:2471,2999`, the input guards in 5.6) would keep the diff small.

## 7. Qt version and patches

### 7.1 Version and source
| | Qt5 (default; Android) | Qt6 (optional) |
|---|---|---|
| Krita switch | `BUILD_WITH_QT6` OFF; `MIN_QT_VERSION 5.15.0` (`K:CMakeLists.txt:14-22`) | `-DBUILD_WITH_QT6=ON -DALLOW_UNSTABLE=QT6` (`K:CMakeLists.txt:374-381`; CI: `K:build-tools/ci-scripts/linux.yml:62-63`, `macos.yml:97-98`) |
| Recipe | `D:ext_qt/CMakeLists.txt`: one recipe with Windows, Android, Linux and macOS branches | `D6:ext_qt/CMakeLists.txt` |
| Source | **Patched fork** `https://invent.kde.org/szaman/qt5.git` @ `31a0c967…` (`D:ext_qt/CMakeLists.txt:6,177-182`). Krita patches live in the fork's submodule commits, not as patch files. The fork branch name `kazakov/krita/5.15.16-lts-lgpl` on the deps repo's `kazakov/krita/5.15.16-lts-lgpl` branch (`ext_qt/CMakeLists.txt:9,143`, Dec 2024) indicates **5.15.16 LTS or newer**. The exact pinned commit is not verifiable (invent is unreachable). | **Patched fork** `https://github.com/dimula73/qt5.git` @ `103e922` = branch `for-krita/6.11.3` ("Port Krita patches to 6.11.3") (`D6:ext_qt/CMakeLists.txt:6,107,159`). Submodules come from `../qtbase.git` and others, on branch `for-krita/6.11.3`. |
| Android submodules | qtbase qtdeclarative qtimageformats qttools qtsvg qttranslations **qtandroidextras qtquickcontrols2 qtgraphicaleffects** (`D:ext_qt/CMakeLists.txt:179`) | qtbase qtdeclarative qtimageformats qttools qtsvg qttranslations qt5compat qtshadertools; "TODO: still need to be recovered: qtgraphicaleffects qtandroidextras" (`D6:ext_qt/CMakeLists.txt:161-162`) |
| Android configure | `-xplatform android-clang -android-ndk-platform android-24 -qt-sqlite -openssl-linked -system-zlib -icu -no-style-android -nomake tools`, many `-skip`s (`D:ext_qt/CMakeLists.txt:186-204`) | Same, plus host tools built first via `-qt-host-path` (`D6:ext_qt/CMakeLists.txt:169-240`), `FEATURE_mimetype_database=OFF`, `FEATURE_style_android=OFF` |

**KDE Qt patch collection:** not used.
- Qt6 forks from upstream `v6.11.3`. About 92 commits on `for-krita/6.11.3` sit above upstream: Krita patches by D. Kazakov, A. Wong, H. Rempt and S. Zaman, plus a few backports.
- Qt5: the only reachable copy is the stale GitHub mirror `github.com/sh-zam/qtbase` branch `krita/5.15` (`a56ef32`, 2022-11). Its merges are `Merge 'origin/tqtc/lts-5.15.N' into tqtc/lts-5.15-opensource`, so it is based on the Qt Company's LTS open-source tags, not KDE's `kde/5.15`.
- Neither recipe references kde/5.15.

### 7.2 Patch files applied by the recipe (Qt5, master)
| File | Applied on | iOS relevance |
|---|---|---|
| `0001-android-Fix-build-with-NDK-27.patch` | Android (`D:ext_qt/CMakeLists.txt:206`) | NDK-only; no iOS twin |
| `0002-android-Fix-ranlib-path-for-NDK-27.patch` | Android (`:207`) | NDK-only |
| `0001-androiddeloyqt-fix-needed-libs-argument-for-llvm-rea.patch` | Android (`:208`) | androiddeployqt-only |
| `0001-Force-enable-16K-alignment-on-Android.patch` | Android, if NDK ≥ 27 (`:167-172,209`) | N/A |
| `0001-macos-Fix-building-on-MacOS-26.patch` | macOS (`:291`) | **Likely needs an iOS twin or check** when building with the Xcode 26 iOS SDK |
| `qtdeclarative-clang21-registerid-enum-fix.patch` | Windows only (`:153`) | May be needed with recent Apple clang (verify) |

The Qt6 branch carries the same Android files, but **commented out** (`D6:ext_qt/CMakeLists.txt:150-152,194-196`), plus `0001-Pass-string-to-ICU-wrapper-as-a-QByteArray-not-a-QSt.patch` and `0001-windeployqt-…`.

### 7.3 Android-specific patches inside the Qt5 fork (evidence: stale `sh-zam/qtbase@krita/5.15`; the current fork may differ)

| Area | Commits | iOS twin needed? |
|---|---|---|
| Stylus/input | `95a331f Android: Properly handle Tablet events`, `9a981e3 pen tilt/rotation`, `7043219 keyboard modifiers for mouse and tablet events`, `926fad4 stylus offset`, `39eced3 prevent out-of-order events`, `276b431 ACTION_CANCEL`, `39bb097 button state through JNI`, `f97a1d7 Move events handling to QtLayout`, `a56ef32 QtInputEventDispatcher`, `c7a3f30 Emulate Long Press as Right Click` | **Yes**: Apple Pencil pressure/tilt/azimuth, hover (iPadOS 16+), coalesced/predicted touches. The probe `IGNORE_HISTORIC_TABLET_EVENTS` maps to coalesced touches. Check what stock Qt iOS gives through `QTabletEvent`. |
| Storage | `bbed4b2 Rework Storage Access Framework`, `646f563`/`55b5ae2` content URIs, `89a222b`, `80cb0ed` URI permissions, `84358a4`, `9404ae2`, `9a1e770`, `978dbf6 External Storage standard paths`, `f9f7f06 TMPDIR` | **Yes**: security-scoped URLs and bookmarks for `UIDocumentPicker` and Files app access |
| Windowing for QWidgets | `8bb23de window manager for raster QWidgets`, `1bc83b9`, `11511ed`, `c1648a0`, `49428d8`, `85128e0` modality | **Probably**: multi-top-level QWidget dialogs on iOS |
| Misc | `b142177 changing cursor` (iPadOS pointer: optional), `5fdca24 Don't invoke Qt's exit path`, `00837b0 Menubar`, `8ef3d30 detection of OpenGL ES 3`, `9eb3712 clipboard buffer`, `35ee577 NDK 21.4 build` | Some |
| Krita-probed Qt5 APIs | `KRITA_QATTRIBUTE_ANDROID_*`, `Qt::ANDROID_INPUT_PLATFORM_DATA_SOFT_INPUT_ADJUST_NOTHING`, `QPlatformScreen::setDensityAdjustment`, `KRITA_QSCROLLER_PATCH` (`K:CMakeLists.txt:797-856`) | iOS twins: keyboard avoidance, UI scale, Pencil buttons via `UIPencilInteraction` (not pen-button emulation) |

The Qt6 fork (`for-krita/6.11.3` qtbase) has **no Krita Android patches**. Its Krita patches are input and shortcuts (Enter/Leave, KeyPress), frame-rate compression/RHI/HDR, Wayland, Windows/ANGLE, macOS (`b2cc490 bundle-local GenericDataLocation`, `7db708f pass-through mode`) and `81a5ac7 Allow widgets to block kinetic scrolling`. So the Android Qt patches would have to be ported in either case.

### 7.4 QtQuick / QML
- **Declared optional**: `Qt5Quick` and `QuickWidgets` are `TYPE OPTIONAL` ("touch gui"), and `QuickControls2` is optional (`K:CMakeLists.txt:887-915`). There is no `option()` to turn it off.
- **Required in practice**:
  - `add_subdirectory(qmlmodules)` is unconditional (`K:CMakeLists.txt:1691`).
  - `kritaqmlwidgets` links `Qt::Qml`, `Quick`, `QuickWidgets` and `QuickControls2` (`K:qmlmodules/widgets/CMakeLists.txt:8-18`).
  - The `kritaqmlcomponents` QML module (`K:qmlmodules/components/CMakeLists.txt:1-60`) is also unconditional.
  - The **Text Properties docker** (`K:plugins/dockers/textproperties/CMakeLists.txt:17-25`) and the **SVG text tool** (`K:plugins/tools/svgtexttool/CMakeLists.txt:56-67`) link Quick unconditionally.
- **Touch docker** is QWidget-only: `K:plugins/dockers/touchdocker/CMakeLists.txt` links just `kritaui`, with no QML.
- **Android enables it**: qtdeclarative, qtquickcontrols2 and qtgraphicaleffects are built (`D:ext_qt/CMakeLists.txt:179`). Krita adds QuickWidgets to `ANDROID_EXTRA_LIBS` (`K:CMakeLists.txt:903-906`) and forces `QT_QUICK_BACKEND=software` (`K:libs/ui/KisApplication.cpp:230-235`). There is also the androiddeployqt QML workaround (`K:android.yml:27-31`).
- **iOS**: build qtdeclarative and quickcontrols2. With static Qt, QML plugins must be imported (qmlimportscanner / `qt_import_qml_plugins`). ECM QML modules (`ecm_add_qml_module`, `SHARED` on Qt6) must also be linkable statically. Treat this as a porting risk.

### 7.5 iOS takeaways
1. **Qt6 is the better base.** It has an upstream-maintained iOS platform, and a host-tools pattern already written for Android cross-builds (`D6:ext_qt/CMakeLists.txt:204-240`). The trade-off: the Android Qt patches are not ported to Qt6, and Krita's Qt6 build still needs `ALLOW_UNSTABLE=QT6`. The Qt5 fork route depends on an unreachable invent repo and a Qt 5.15 iOS backend against current Xcode SDKs (unverified).
2. **Static vs shared decides the architecture.** Qt's documented iOS configuration is static. Krita is many SHARED libs plus about 170 `MODULE` plugin targets (count of `kis_add_library(... MODULE` under `plugins/` and `libs/`) found at runtime by `QPluginLoader` (`K:libs/koplugin/KoJsonTrader.cpp:143-157`). With static Qt, either:
   - build Krita fully static and register plugins statically (code work), or
   - attempt a shared Qt for a sideload-only build (unsupported upstream; verify for the chosen Qt version). A static Qt linked into many dylibs would duplicate Qt and break singletons.
3. **Add a new `elseif(IOS)` Qt recipe branch**: `-xplatform macx-ios-clang` (Qt5) or `-platform`/toolchain plus `-qt-host-path` (Qt6), `-no-openssl` (SecureTransport), `-no-dbus`, `FEATURE_mimetype_database=OFF` as on other Qt6 platforms. It must be placed **before** the `else(APPLE)` macOS branch (`D:ext_qt/CMakeLists.txt:263`).

## 8. Ordered list of code changes

Each step is meant to be one commit. **Done** means committed on this branch and verified on Linux. **Linux-safe** means it can be written and checked here (compiles, tests pass, nothing changes off iOS), but it hasn't been done yet. **Mac** means it needs the iOS toolchain to verify. **Deps repo** means the change goes in krita-deps-management, not here.

| # | Change | Where | Status |
|---|---|---|---|
| 1 | Use `Q_OS_MACOS` instead of `Q_OS_MAC` where the code is macOS-only. Fixes the unbalanced brace on iOS, the doubled touch and Pencil mouse events, and the ColorSync scan. | `libs/ui/input/kis_input_manager.cpp:684`, `libs/ui/input/KisInputEventsEater.cpp:271`, `plugins/color/lcms2engine/LcmsEnginePlugin.cpp:98` | **Done** (`45bb0b2`) |
| 2 | Give every plugin factory (26 renamed), `Plugin` class (3) and `.qrc` (1) a unique name, so plugins can be linked into one binary | `plugins/**` | **Done** (`9882099`) |
| 3 | `KoJsonTrader` also loads `Q_IMPORT_PLUGIN`'d plugins (IID `org.kde.KPluginFactory`); `KRITA_STATIC_PLUGINS` skips the directory scan. New static case in `KoPluginLoaderTest`. | `libs/koplugin/` | **Done** (`107eff4`); `KoPluginLoaderTest` 9/9 pass |
| 4 | Rename the second `KisColorSelector` (artistic colour selector), which clashes with the advanced colour selector's class of the same name | `plugins/dockers/artisticcolorselector/` | **Done** (`3b7ec59`) |
| 5 | Move plugin-scope static initializers that use `i18n()` or registries out of pre-`main()` static initialization. Only MyPaint's sensor factories qualified; the other six register metatypes or QML types, which is safe before `main()`. | `plugins/paintops/mypaint/MyPaintSensorPack.cpp` | **Done** (`7c312d0`) |
| 6 | CMake `KRITA_MOBILE` (`ANDROID OR IOS`, or the `KRITA_SIMULATE_MOBILE` test option) as a global compile definition, and `MACOS` (`APPLE AND NOT IOS`) for what only macOS has | top-level `CMakeLists.txt` | **Done** (see "Mobile code paths" below) |
| 7 | Switch the 144 **reuse** guards from `Q_OS_ANDROID` / `if(ANDROID)` to `KRITA_MOBILE`, splitting the mixed guards | section 1 table | **Done**: 150 sites in 41 files; `Q_OS_ANDROID` went from 275 to 132 occurrences, all Android-only or ios-twin. Compiled on Linux with `KRITA_SIMULATE_MOBILE=ON` |
| 8 | Replace plain `APPLE` with `MACOS` in the macOS-only CMake blocks: macosutils/AppKit, `osx.mm`, `krita/integration`, bundle/plist/icon, `-mmacosx-version-min`, `packaging/macos` | section 2.2 row 34, section 1 "Darwin hazards" | **Done** (13 blocks; `krita_version` and `kritarunner` are already excluded by `KRITA_MOBILE` / no Python). Only checked on Linux, where `APPLE` is false |
| 9 | iOS toolchain files, an `iOS` platform in `latest/krita-deps.yml` and the recipes' `.kde-ci.yml`, `elseif(IOS)` branches before the `APPLE` ones in the 8 recipes that have them | krita-deps-management | **Done** for the painting set: `5041ad5` on the deps fork's `ios` branch. 41 recipes build static for the simulator and the device; Krita configures against both prefixes. The per-recipe `.kde-ci.yml` files are unchanged (krita-ci-utilities has no iOS flavour; `tools/ios-build-deps.sh` drives the build). Record: `IOS_DEPS_BUILD.md` |
| 10 | `ext_qt` iOS branch: Qt 6 static, arm64 device and simulator, macOS host tools first | krita-deps-management `ext_qt/CMakeLists.txt` (`D6:`) | **Done**: `92fcb8a` on branch `ios` of `github.com/Erindale/krita-deps-management`, copied to `packaging/ios/deps/ext_qt-ios-branch.cmake`. Built by hand for device and simulator, and the recipe itself run end to end for the simulator; tablet, hellogles3 and QtQuick Controls examples run on the simulator; a device-SDK example links and signs. No Qt patches; the recipe's host step needs `-no-warnings-are-errors`. Record: `IOS_QT_BUILD.md` (`ed62bff924`) |
| 11 | `KRITA_STATIC_BUILD` option (on by default for iOS): `kis_add_library` builds `SHARED`/`MODULE` as `STATIC`, `BUILD_SHARED_LIBS` off, plugins outside `KRITA_STATIC_PLUGINS_ALLOWLIST` left out of the default build | `cmake/modules/KritaStaticBuild.cmake`, top-level `CMakeLists.txt` | **Done** on Linux (`971f21d`, `a2ac82c`, `31d0825`); see "Static Linux build" below |
| 12 | Plugin registry: a generated `krita_static_plugins.cpp` of `Q_IMPORT_PLUGIN` calls (class names read from `K_PLUGIN_FACTORY_WITH_JSON`), and whole-archive linking of every library and plugin, which keeps Qt resources and static initializers without `Q_INIT_RESOURCE`. Qt's own iOS plugins (platform, sqlite, svg, jpeg) still need importing on iOS. | `krita/CMakeLists.txt` | **Done**. Krita side on Linux (`971f21d`); on iOS Qt's CMake links its own plugins (platform, SQLite, image formats, SVG, QtQuick/Controls QML) with no extra code, verified on the simulator (`IOS_KRITA_BUILD.md`) |
| 13 | GLES and input guards extended to iOS | `libs/ui/CMakeLists.txt:1`, `kis_opengl.cpp`, `KisOpenGLSync.cpp`, `KisOpenGLContextSwitchLock.cpp`, `krita/main.cc`, `kis_shortcut_matcher.cpp`, `kis_input_manager.cpp` | **Done** on the Krita side: `QT_OPENGL_ES_3` for `ANDROID OR IOS`, the desktop-GL probe/fallback and the input guards via `KRITA_MOBILE`, fences and the Qt 6 RHI backend via `Q_OS_IOS`. **Verified** on the simulator: with Qt 6 also `QT_OPENGL_ES_2` (Qt 6 no longer defines it) and three GLES constant fallbacks; canvas draws and strokes paint (`IOS_KRITA_BUILD.md`) |
| 14 | `totalRAM()` iOS branch and a lower default hard limit | `libs/image/kis_image_config.cpp` | Drafted: `sysctl hw.memsize` shared with macOS, default hard limit 30% on iOS. Mac |
| 15 | Paths inside the `.app`: installation prefix, plugin lookup, translations, MLT | `libs/resources/KoResourcePaths.cpp`, `libs/koplugin/KoJsonTrader.cpp`, `krita/main.cc` | Prefix **verified** on the simulator: `share/` and `lib/qml` copied into `krita.app`, resources and translations load; plugin lookup is moot in a static build; MLT not built |
| 16 | Resource folder in `Documents/Resources`, ignoring a saved absolute path; resource DB kept out of Documents | `KoResourcePaths.cpp`, `libs/ui/KisApplication.cpp` | Drafted: `iosResourceLocation()` used by `getAppDataLocation()` and `saveLocationInternal()`; the DB location is already AppDataLocation under `KRITA_MOBILE`. **Verified** on the simulator: the default bundle loads from `Documents/Resources` |
| 17 | iOS `Info.plist` and bundle target | `krita/CMakeLists.txt`, `packaging/ios/Info.plist.in` | Drafted: `elseif (IOS)` bundle block with Xcode signing attributes, plist with file sharing, in-place documents, `.kra`/`.krz`/`.bundle` types, iPad only. **Verified** on the simulator (bundle installs, Files app shows the Krita folder, `.kra` saved and opened through the iOS picker). No app icon yet; device signing is Phase 5 |
| 18 | App lifecycle: autosave on background, files opened from the system; fullscreen, device model, crash log | `krita/main.cc`, `libs/global/` | Autosave **done** for all mobile platforms (`applicationStateChanged` → `autoSaveDocumentsOnPause()`, shared with the Android JNI hook); system file opens already arrive as `QFileOpenEvent`. Fullscreen, device model and crash log keep their Android-only JNI code; iOS uses the generic paths. On iOS Krita now starts once UIKit reports the app active, and shows no splash (`krita/ios/KisIosApplicationState.mm`, `IOS_KRITA_BUILD.md`) |
| 19 | Native file access: `UIDocumentPickerViewController` behind `KoFileDialog`; security-scoped bookmarks for recent files (template: `libs/macosutils/KisMacosSecurityBookmarkManager.mm`); "outside app container" predicate replacing `startsWith("content://")` | `libs/widgetutils/KoFileDialog.cpp:217/:266/:311`, `KisRecentFilesManager_p.h:42/:108`, `KisDocument.cpp:1910` | Mac (later: Phase 6 only needs the Documents folder, step 16) |
| 20 | In-process libav encoder on all mobile platforms, `KisAndroidMediaEncoderRunnable` Android-only | `libs/ui/CMakeLists.txt` | **Done** as part of step 7: the encoder, its preferences dialog and the wrapper build under `KRITA_MOBILE` (LibAV required there); compiled on Linux. Only the MediaCodec runnable stays Android-only |

### Mobile code paths on Linux

`KRITA_SIMULATE_MOBILE=ON` defines `KRITA_MOBILE` on a desktop platform, so the code Android and iOS share can be compiled and run here. It is a test configuration only (desktop GL Qt, no file picker integration, `windowlayouts` left out of the install like Android):

```bash
cmake -G Ninja <krita-src> -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DKRITA_SIMULATE_MOBILE=ON
ninja krita kritarecorderdocker kritacompositiondocker kritaresourcemanager krita_tool_svgtext
```

It needs the ffmpeg development libraries (`pkg-config libavcodec libavfilter libavformat libavutil libswscale`), because the in-process encoder is required on mobile. Result on Ubuntu 24.04:

- `krita`, every library and the four plugins with mobile code compile and link; the shared build is unchanged.
- One real defect: the libav encoder used `av_err2str()`, a C99 compound literal that clang accepts in C++ and GCC does not. Fixed in `cdab968`. Everything else in the 150 switched sites compiled as it does on Android.
- Exporting a raster-only `.kra` to PNG with the simulated-mobile binary gives a file identical to the desktop build's, three runs out of three, so the mobile save path (temp file, then copy into place) works.
- Exporting the comics template, which has a vector layer, crashes on exit every time in the simulated build (`KisShapeLayerCanvas::repaint()` still running on a worker thread while the application is torn down), and writes a PNG without the vector content. The desktop build has the same crash about one run in three, so this is a pre-existing race that the mobile save path makes more likely; it is not investigated. Check animation and vector export on the device.
- Loading a multi-window `windowlayouts` resource shows a modal dialog under `KRITA_MOBILE`; a headless run hangs there. Mobile installs do not ship those files.

Not covered: `QT_OPENGL_ES_3` (tied to `ANDROID OR IOS`, not to `KRITA_MOBILE`), the Android-only JNI code, and any `Q_OS_IOS` branch.

### Static Linux build

The static build runs on Linux with Qt 5.15 and KF5 from Ubuntu 24.04:

```bash
cmake -G Ninja <krita-src> -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DKRITA_STATIC_BUILD=ON
ninja krita
```

It links 47 libraries and 17 Krita plugins into one 99 MB `krita` executable (Qt and KF5 stay shared on Linux). The default allowlist is the 13-plugin painting set from section 4.4 (e) plus the two vector shape plugins, `krita_shape_image` and `krita_shape_paths`: text rendering looks those shapes up without a null check, and crashes on first start without them.

To run it without installing, put the binary in a `bin/` directory next to a `share/` taken from a normal install (`KoResourcePaths` falls back to `applicationDirPath()/../`). Verified with this binary:

- Command-line export of a `.kra` to PNG is byte-identical to the shared build's output.
- Under Xvfb, the GUI opens a `.kra` with canvas, toolbox and all four allowlisted dockers, and a mouse stroke paints with the pixel brush.
- All 17 plugins arrive through `QPluginLoader::staticPlugins()`; the QML module's plugin is registered too and correctly skipped by `KoJsonTrader`.

What the whole-archive link found:

- `KisPaintOpPluginUtils::effectiveSpacing()` and `effectiveTiming()` were non-inline functions defined in a header, one copy per paintop. Fixed in `a2ac82c`.
- With `KRITA_STATIC_PLUGINS_ALLOWLIST=ALL` (219 libraries, 169 plugins, a 125 MB binary) the link found the other kind of duplicate: sources compiled into two plugins. Eight import/export pairs (ora, exr, jpeg, csv, heightmap, heif, gif, brush) compiled their converter twice, the levels filter compiled two files from the colors filters, and the TIFF logger header defined functions without `inline`. Fixed in `7f47e29` by one `STATIC` helper library per pair. After that the all-plugins binary links, exports PNG (byte-identical), ORA, PSD, JPEG and TIFF, and under Xvfb opens a `.kra` with the full toolbox and paints a stroke; `KoJsonTrader` reports all 168 Krita plugins (the 169th is the QML plugin, correctly skipped). So no duplicate-symbol problem remains in the Linux plugin set; plugins not built on Linux (platform plugins for xcb/wayland are built; G'MIC and Python are not) are unchecked.

Problems that are not specific to the static build (the shared build behaves the same):

- Command-line export crashes about 1 run in 3 on exit: an image update job still runs after `main()` returns and calls the already destroyed `KisUpdateTimeMonitor` singleton.
- The GUI crashes at start on the `offscreen` Qt platform, because `KisClipboard` calls `hasImage()` on the clipboard's null `mimeData()`. Use Xvfb for headless GUI tests.

Not covered on Linux: Qt 6, static Qt (here Qt itself is shared, so no Qt plugins needed importing), the Qt 6 QML module path in `qmlmodules/components/CMakeLists.txt`, and Apple's linker (`-force_load` is used there instead of `--whole-archive`). ECM 5.x writes a stray `_init.cpp` into `qmlmodules/components/` in static builds (it uses an unset variable for the output path); it is in `.gitignore`.
