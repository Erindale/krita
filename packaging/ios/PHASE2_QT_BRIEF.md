# Phase 2 brief: Qt 6 for iOS (run on the Mac)

A copy of the brief from the planning document, so the Mac session has it in the checkout. Paste the block below into Claude Code running on the MacBook Air, in a terminal inside `tmux` and started with `caffeinate`, so the multi-hour builds survive a closed lid. It covers Phase 2 only: Qt 6 for iOS, proven on the simulator. Dependencies and Krita itself get their own briefs.

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
