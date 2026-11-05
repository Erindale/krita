# Krita on iPad: Plan of Attack

Exported 2026-11-04 from the planning document at https://claude.ai/artifact/JNWxekjBgXC6VQicNvp5iY (the live copy; this file is for sessions without access to it). Companion files: `IOS_PORT_GAPLIST.md` (the audit and step list) and `packaging/ios/README.md` (the iOS drafts).

Nov 3, 2026 · Erindale

## Goal

Build stock Krita for iPadOS, sideloaded onto a personal iPad, with custom brush bundles loaded from the Files app. This is a personal experiment: nothing goes back upstream and nothing goes to the App Store, so the GPL vs App Store problem never applies.

**In scope**

- Krita master (or the current stable branch) built for arm64 iPadOS with the same mobile code paths the Android build uses
- OpenGL ES canvas, Apple Pencil pressure and tilt, touch gestures
- A resource folder visible in the Files app so `.bundle` files can be dropped in
- A simulator build for smoke tests on the cloud Mac, then a signed device build

**Out of scope**

- Python scripting (Android disables it; do the same)
- A touch-first UI redesign; the existing mobile UI mode is enough
- Metal rendering; OpenGL ES is deprecated on iOS but still ships and works
- Any distribution beyond your own devices

## The constraint that shapes everything

iOS apps can only be compiled, signed and deployed from macOS with Xcode. A Linux cloud box, including a Claude Code cloud session, cannot produce the final build. So the work splits in two:

- **Linux-safe work** (most of the engineering hours): reading the Krita tree, auditing the Android code paths, writing the CMake and C++ changes, adapting dependency recipes, and verifying nothing breaks by building the normal Linux target. A Claude Code cloud session does all of this well.
- **Mac-only work**: building Qt for iOS, cross-compiling the dependencies, building Krita itself for iOS, running the simulator, signing, and installing on the iPad. This runs on your MacBook Air, with the trees on an external SSD.

Two further facts set the plan:

- **Installing on the iPad** is a signing step, not a build step. With the build on the laptop, Xcode signs and installs straight to the connected iPad, or exports a development `.ipa` for your device UDID. A free Apple ID gives 7-day signatures; the paid developer program gives a year, and TestFlight.
- **Krita's own CI** already builds Android on Linux. The tree has moved dependency management to the separate `krita-deps-management` repository, so the iOS recipes belong there, mirroring its Android ones.

## Where the work runs

The Claude Code cloud session did the audit and the Linux-safe code (done). Everything that needs Xcode runs on your MacBook Air, with the sources and build trees on an external SSD: about 60–75 GB at peak, plus Xcode's 20–25 GB on the internal disk. A rented Mac stays a fallback if the laptop's build times become the bottleneck.

| Environment | Good for | Limits |
| --- | --- | --- |
| Claude Code cloud session (Linux) | Audit, CMake and C++ changes, dependency recipe edits, Linux build to catch regressions | Cannot build, sign or run anything for iOS |
| Your MacBook Air with an external SSD | No rental cost, Xcode already there, the iPad plugs straight in; the SSD (APFS, 250 GB or more) holds Qt, the dependencies and Krita | Ties up the laptop for the multi-hour Qt build; keep it on power and awake, and exclude the SSD from Spotlight and Time Machine |
| AWS EC2 Mac (Apple silicon) | Persistent SSH box for the iOS toolchain; Claude Code can connect over SSH | Dedicated host, billed with a 24-hour minimum |
| Scaleway Apple silicon Mac mini | Same role as EC2 Mac, hourly billing | 24-hour minimum, EU regions |
| MacStadium | Monthly rental, strongest for a multi-week effort | Monthly commitment |
| GitHub Actions macOS runner | Free CI once the recipes work; caches built dependencies between runs | 6-hour job limit, ephemeral, no interactive debugging |

Recommended split: Claude Code cloud for the audit and code (done), the MacBook Air with the SSD for Qt, the dependencies, Krita, signing and the install. Rent a Mac only if the laptop proves too slow; once the dependency recipes are stable, a GitHub Actions runner can take the long builds.

> Diagram in the planning document: three boxes left to right, *Claude Code cloud* (audit, CMake and C++ edits, Linux build check; done) → git → *Your MacBook Air + SSD* (Qt, deps, Krita on the SSD; simulator, then signing; install from Xcode; 60 to 75 GB on the SSD) → USB → *Your iPad* (sideloaded Krita, bundles via Files).

Code reaches the laptop as a git branch; the laptop builds everything for iOS on the SSD and installs to the iPad over USB.

## Plan of attack

Six phases. The first is Linux-only and costs nothing but agent time; nothing after it starts until the audit says what the tree actually looks like today. The audit is done, and the steps below reflect what it found.

1. **Audit the tree (Linux, Claude Code cloud). Done.** The gap list has exact paths for everything below; see Phase 1 results. It covered:
   - Grep every `Q_OS_ANDROID` site under `libs/`, `krita/` and `plugins/`. Classify each: reusable on iOS as-is, needs an iOS twin, or Android-only (JNI, Storage Access Framework).
   - Read `packaging/android/` to learn which CMake options and disabled features the Android build uses. Those become the iOS defaults.
   - List every dependency recipe (the `3rdparty/ext_*` directories, or the `krita-deps-management` repository if the tree has moved there) and note which carry Android patches. Those are the iOS candidates.
   - Map plugin loading in `libs/koplugin` (`KoPluginLoader`, `KoJsonTrader`): how plugins are found on disk and what a static registry would replace.
   - Map the GLES path in `libs/ui/opengl` (`KisOpenGL`) and how Android selects it.
   - Map resource and file access: `KoResourcePaths`, `KisResourceLocator`, the Android file manager class, and every `QFileDialog` use.
   - Record which Qt the tree builds against (patched 5.15 or 6.x) and whether Krita's QtQuick touch docker is needed.
2. **Qt for iOS (Mac).** Build Krita's Qt 6 fork (`github.com/dimula73/qt5`, branch `for-krita/6.11.3`) static for arm64 device and simulator, with macOS host tools first. Modules: qtbase, qtdeclarative (Krita requires QtQuick Controls 2), qtsvg, qtimageformats, qtshadertools, qt5compat, and qttools for translations. Neither Qt fork has iOS patches; port Krita's Android pen and storage patches only where iOS turns out to need them. Prove it on the simulator with Qt's tablet, OpenGL ES 3 and QtQuick Controls examples.
3. **Dependencies for iOS (Mac).** Work in `krita-deps-management` on its Qt 6 branch, `transition.now/qt6`. Add iOS toolchain files and an iOS platform to `latest/krita-deps.yml`, and put `elseif(IOS)` branches ahead of the recipes' `APPLE` branches. Cross-compile the required recipes (gap list section 3) in dependency order, skipping optional importers (libraw, poppler, G'MIC, HEIF, JPEG XL) until a canvas is on screen. Everything static. Then rebuild Qt against the prefix's libpng, libjpeg, freetype, harfbuzz and zlib, so the final link has one copy of each.
4. **Krita itself for iOS (Mac, with code from the Linux session).**
   - A `KRITA_STATIC_BUILD` option that builds every library and plugin static, plus a generated file of `Q_IMPORT_PLUGIN` and `Q_INIT_RESOURCE` calls in place of the on-disk scan. The loader side is already done; start with the 13-plugin minimal set in the gap list's section 4.4.
   - An `Info.plist` that enables file sharing and in-place document opening, declares `.kra` and `.bundle` document types, and sets supported orientations.
   - Point Krita's resource folder at the app's Documents directory so the Files app shows it: `KoResourcePaths::getAppDataLocation()` returns `Documents/Resources` on iOS, and the resource database stays outside Documents.
   - Disable Python scripting, force the GLES canvas, add the iOS RAM detection that `totalRAM()` lacks, and lower the default memory limits.
   - Mark the roughly 25 macOS-only `if (APPLE)` CMake blocks as macOS-only, and extend the mobile and GLES guards to iOS (gap list section 8).
   - Milestones in order: links, launches on the simulator, draws a canvas, paints a stroke, opens a `.kra`, saves one.
5. **Sign and install (laptop).** Set the development team in CMake, archive and export a development `.ipa` for your iPad's UDID, or run straight from Xcode on the connected iPad; the command-line route is `xcrun devicectl`. Check Pencil pressure and tilt on real hardware; the simulator cannot.
6. **Brush bundles (iPad).** Drop a `.bundle` into the Krita folder in the Files app, relaunch, confirm it appears in the resource manager, and confirm the resource database survives a relaunch.

## Checklist

**Before starting**

- [x] Apple ID signed in to Xcode (free is enough to start; paid program for year-long installs)
- [ ] iPad UDID noted and registered to the Apple ID
- [ ] External SSD (APFS, 250 GB or more) attached and excluded from Spotlight and Time Machine; current Xcode with the iOS SDK and a simulator runtime installed on the laptop
- [x] Claude Code cloud session opened on a fork or clone of Krita

**Phase 1: audit**

- [x] Gap list written with exact file paths for every `Q_OS_ANDROID` site
- [x] Android CMake options and disabled features recorded
- [x] Dependency list with Android-patched recipes marked
- [x] Plugin loader static-registry design sketched
- [x] Qt version and QtQuick requirement confirmed

**Phase 2: Qt**

- [x] Static Qt for iOS device built
- [x] Static Qt for iOS simulator built
- [x] Qt tablet example runs on the simulator

**Phase 3: dependencies**

- [x] iOS toolchain file committed
- [x] Required dependencies cross-compiled and installed to one prefix
- [x] Optional importers deferred and listed

**Phase 4: Krita**

- [x] iOS CMake configuration builds all plugins static
- [x] Static plugin registry replaces the disk scan
- [ ] `Info.plist` with file sharing and document types
- [ ] Resource folder lives in Documents
- [ ] Links without unresolved symbols
- [ ] Launches on the simulator
- [ ] Canvas draws and a stroke paints
- [ ] Opens and saves a `.kra`

**Phase 5: device**

- [ ] Development `.ipa` exported for the iPad's UDID
- [ ] Installed on the iPad
- [ ] Pencil pressure and tilt work
- [ ] Survives a 500 MB document without being killed

**Phase 6: bundles**

- [ ] Krita folder visible in the Files app
- [ ] A dropped `.bundle` appears in the resource manager after relaunch
- [ ] Brushes from the bundle paint correctly

## Risks and where the time goes

The static plugin registry and the Qt build are where this project lives or dies. Everything else is work, not uncertainty.

| Risk | Why it matters | Fallback |
| --- | --- | --- |
| Static plugin loading | Krita's loader scans directories for shared libraries; iOS forbids that. Nobody has done this for Krita. | Start with a hand-written registry of the dozen plugins a painter needs; add the rest later |
| Qt 5.15 against a current iOS SDK | If the tree is still on patched Qt 5.15, it predates recent Xcode releases and may need patches to configure | Pin an older Xcode on the Mac, or move to Qt 6 if Krita master already supports it |
| QWidgets on iOS | Qt's iOS platform plugin supports QWidgets but menus, dialogs and the keyboard behave oddly | Lean on the existing mobile UI mode; accept rough edges |
| Memory kills | iPadOS terminates apps using more than a few GB | Lower the tile and undo memory limits as Android does; test on an M-series iPad |
| OpenGL ES removal | Deprecated since iOS 12; Apple could drop it in a future release | ANGLE over Metal exists if it ever happens; not needed now |
| Build time | Qt plus forty dependencies is several hours on one Mac | Use ccache on the SSD; move stable steps to GitHub Actions |
| 7-day signatures | A free Apple ID expires the install weekly | Join the paid developer program, or re-sign weekly from the laptop |
| Simulator gaps | No Pencil pressure, no real GPU memory pressure | Treat simulator milestones as build checks only; validate on hardware |

## Phase 1 results

Phase 1 is done. The gap list is [IOS\_PORT\_GAPLIST.md](https://github.com/Erindale/krita/blob/claude/vibrant-wright-6bl1z8/IOS_PORT_GAPLIST.md) on branch `claude/vibrant-wright-6bl1z8`; its section 8 is the ordered list of remaining commits. Five findings change the plan above:

| Finding | What it changes |
| --- | --- |
| Krita's Android build uses a patched Qt 5.15 fork on invent.kde.org; master also builds with Qt 6 from `github.com/dimula73/qt5`, branch `for-krita/6.11.3` | Phase 2 builds that Qt 6 fork, not 5.15. Neither fork has iOS patches, and the Android pen and storage patches must be ported either way |
| QtQuick is required: `qmlmodules/`, the text tool and the Text Properties docker link QtQuick Controls 2 | Every Qt build includes qtdeclarative, and its QML plugins are imported statically. The touch docker is QWidget-only |
| Dependency recipes moved to `krita-deps-management`; `3rdparty/` is empty | Phase 3 works in that repo. Its GitHub mirror's default branch is a stale 2024 one, so clone `master` explicitly. 28 of 96 recipes are needed for a painting-only build |
| `totalRAM()` has no iOS branch and falls back to 1 GiB | New Phase 4 item: an iOS branch and a lower default memory limit |
| About 25 CMake `if (APPLE)` blocks are macOS-only but also fire on iOS | New Phase 4 item: mark them macOS-only |

invent.kde.org is unreachable from Claude Code cloud sessions, so every outside repository came from its GitHub mirror.

| Commit | What it does |
| --- | --- |
| `45bb0b2` | Fixes three macOS-only guards that iOS also triggers, one of which broke the iOS compile |
| `9882099` | Gives every plugin factory, `Plugin` class and `.qrc` a unique name, so plugins can share one binary |
| `107eff4` | Lets the plugin loader find plugins compiled into the app, with a new test |
| `6ee2add` | Adds the gap list |

Verified on Linux: the full build links, `KoPluginLoaderTest` passes 9 of 9, and a command-line export from `.kra` to PNG, ORA and PSD works. Nothing has been compiled for iOS or Android.

**Done on Linux after the audit** (same branch, 12 more commits). The two risks the plan called decisive are now cleared on Linux, and the Mac work starts from code rather than notes.

| Work | Result |
| --- | --- |
| Static build (`KRITA_STATIC_BUILD`) | Krita, its libraries and all 168 plugins link into one 125 MB executable. It exports PNG (byte-identical to the normal build), ORA, PSD, JPEG and TIFF, and under a virtual display opens a `.kra` with the full toolbox and paints a stroke. The link flushed out every duplicate name and twice-compiled source; all fixed. Phase 4's first two checklist items are ticked on that basis |
| Shared mobile code (`KRITA_MOBILE`) | The 144 Android code sites iOS can reuse, including the in-process video encoder, now sit behind one guard. A test option compiles them on Linux; that found one GCC-only error (fixed). Autosave when the app goes to the background is shared too |
| iOS drafts, unbuilt | `Info.plist`, the Xcode bundle block, resource folder in Documents, RAM detection, GLES guards, the macOS-only CMake blocks fenced off, and in `packaging/ios/deps/` the toolchain files, Qt recipe branch and deps list for `krita-deps-management` |

Still only a Mac can do: build Qt and the dependencies, import Qt's own plugins into the app, sign, and test on the simulator and iPad. One open issue to check there: exporting a document with a vector layer crashes on exit in the simulated-mobile build every time (the desktop build has the same race about one run in three).

## Brief for the cloud session: Phase 1 (done)

Paste this into a Claude Code cloud session pointed at a fork of Krita. It covers Phase 1, which is done; the results are above and the Phase 2 brief follows.

```markdown
Goal: prepare a personal iPadOS port of Krita, reusing the Android build's mobile code paths. This session is Linux-only: audit and plan, write code where it is safe to do so, and verify with the normal Linux build. Do not attempt any iOS compilation here.

Deliverable: a file IOS_PORT_GAPLIST.md at the repo root containing:

1. Every Q_OS_ANDROID site under libs/, krita/ and plugins/, with file:line, one line on what it does, and a classification: reuse on iOS as-is / needs an iOS twin / Android-only.
2. The CMake options and disabled features the Android build uses, read from packaging/android/ and any CI config, as the proposed iOS defaults.
3. The dependency list: every third-party recipe (3rdparty/ext_* or the krita-deps-management repo, whichever the tree uses today), marking which have Android patches, which are required for a painting-only build, and which are optional importers to defer.
4. How plugins are discovered and loaded (libs/koplugin), with a concrete design for a static plugin registry on iOS: which CMake macro builds plugins, what changes to build them STATIC, and how main() would register them.
5. How the OpenGL ES canvas is selected on Android (libs/ui/opengl) and what, if anything, differs for iOS.
6. Where resources and user files are located (KoResourcePaths, KisResourceLocator, QStandardPaths, the Android file manager class, every QFileDialog use) and the smallest change that puts the resource folder in the iOS app's Documents directory.
7. The Qt version the tree targets, whether the KDE patch collection has iOS support, and whether the QtQuick touch docker is required.
8. An ordered list of code changes, each small enough to be one commit, with the ones that can be made and Linux-tested now marked.

Then make the changes marked as safe now on a branch named ios-port, one commit each, and confirm the Linux build still configures and compiles. Report what you changed, what you could not verify, and what needs the Mac.
```

## Brief for the Mac: Phase 2

Paste this into Claude Code running on the MacBook Air, in a terminal inside `tmux` and started with caffeinate, so the multi-hour builds survive a closed lid. It covers Phase 2 only: Qt 6 for iOS, proven on the simulator. Dependencies and Krita itself get their own briefs.

Before pasting:

- Current Xcode with the iOS SDK and an iOS simulator runtime installed, and `xcode-select` pointing at it
- Homebrew `cmake`, `ninja`, `ccache` and `python3`
- The external SSD mounted, APFS, with 100 GB free; Xcode on the internal disk
- A GitHub fork of `KDE/krita-deps-management` under your account, so the session can push the recipe change

```markdown
Goal: build static Qt 6 for iOS (arm64 device and arm64 simulator) from the Qt fork Krita uses, prove it on the simulator, and capture the build as a reproducible krita-deps-management recipe. This is Phase 2 of a personal iPadOS port of Krita. Do not build any other dependency or Krita itself.

Context:
- Phase 1 audit: IOS_PORT_GAPLIST.md on branch claude/vibrant-wright-6bl1z8 of https://github.com/Erindale/krita. Read its summary, section 7 (Qt) and section 8 steps 9-10 first.
- Qt source: https://github.com/dimula73/qt5.git at commit 103e9220e99215ab26fefac041e7f77793403b2b (branch for-krita/6.11.3). Submodules: qtbase qtdeclarative qtimageformats qttools qtsvg qttranslations qt5compat qtshadertools. QtQuick Controls 2 is part of qtdeclarative and Krita requires it.
- Recipe to extend: ext_qt/CMakeLists.txt on branch transition.now/qt6 of the user's fork of https://github.com/KDE/krita-deps-management. invent.kde.org may be unreachable; use the GitHub mirrors. The mirror's default branch is stale, so check out the named branch explicitly.
- Start from the drafts in packaging/ios/deps/ of the Krita branch: ios-toolchain.cmake, ios-toolchain-krita.cmake, ext_qt-ios-branch.cmake and deps-ios.yml, written on Linux and never built; packaging/ios/README.md says where each goes. They mirror the recipe's macOS branch (skip list, -no-dbus, -no-qml-debug, -qt-sqlite, FEATURE_mimetype_database=OFF) and its Android host-tools pattern (-qt-host-path).

Steps:
1. Layout under /Volumes/<your SSD>/krita-ios: src/, qt-host/, qt-iphoneos/, qt-iphonesimulator/, logs/. Run every build in the background with a log in logs/, use ccache (cache on the SSD), and delete each build tree once its install is done to stay within the SSD.
2. Build host Qt for macOS (arm64) into qt-host: qtbase, qtdeclarative, qtshadertools, qttools (for lrelease), release, no examples or tests.
3. Configure and build Qt for iOS device into qt-iphoneos: -platform macx-ios-clang -sdk iphoneos -qt-host-path /Volumes/<your SSD>/krita-ios/qt-host -release, the same submodules as the recipe, bundled third-party libraries (-qt-zlib -qt-libpng -qt-libjpeg -qt-freetype -qt-harfbuzz -qt-pcre), no OpenSSL. Static is the iOS default; confirm it.
4. The same for the simulator into qt-iphonesimulator: -sdk iphonesimulator, with CMAKE_OSX_ARCHITECTURES=arm64.
5. Prove it on the simulator, building each example with /Volumes/<your SSD>/krita-ios/qt-iphonesimulator/bin/qt-cmake -GXcode and running it with xcrun simctl, taking a screenshot of each:
   - qtbase examples/widgets/widgets/tablet (QWidgets and tablet events)
   - qtbase examples/opengl/hellogles3 (OpenGL ES 3, which Krita's canvas needs)
   - a QtQuick Controls 2 example from qtdeclarative (static QML plugin import)
   Also build one example for the device SDK to prove it links and signs with automatic signing; do not install it.
6. If the fork's Krita patches break the iOS build, record which commit and error, check whether upstream Qt v6.11.3 builds cleanly with the same flags, and fix or revert only what iOS needs.
7. Add an elseif(IOS) branch to ext_qt/CMakeLists.txt, placed before the APPLE (macOS) branch, that reproduces steps 2-4 (host tools as an ExternalProject step, as the Android branch does). Commit it on a branch named ios in the user's krita-deps-management fork and push.

Deliverable: IOS_QT_BUILD.md committed on branch claude/vibrant-wright-6bl1z8 of the Krita repo, containing the Xcode and SDK versions, the exact configure lines, build times and prefix sizes, any patches needed and why, the three simulator screenshots, and anything that failed. Also update IOS_PORT_GAPLIST.md section 8 step 10 to Done with the commit hashes.

Known follow-up, not for this session: Qt's bundled libpng, libjpeg, freetype, harfbuzz and zlib will clash with Krita's own copies once everything is linked statically, so Phase 3 rebuilds Qt against the dependency prefix with -system-* options. Note in IOS_QT_BUILD.md which bundled libraries Qt used.

Report what you built, what you verified on the simulator, what you could not verify, and what Phase 3 needs from this.
```
