# iPadOS packaging (personal, sideloaded build)

Drafts for the parts of the iPadOS port that can only be verified with Xcode. The Qt recipe, the dependency toolchains and the dependency set have been built on the Mac (Phases 2 and 3, see `IOS_QT_BUILD.md` and `IOS_DEPS_BUILD.md`); `Info.plist.in` and the Krita-side code are still unbuilt. The audit behind it is `IOS_PORT_GAPLIST.md` at the repository root; its section 8 lists the remaining steps.

## What is here

| File | Goes where | Purpose |
|---|---|---|
| `Info.plist.in` | used in place by `krita/CMakeLists.txt` when `IOS` is set | Bundle metadata: iPad only, Files app sharing on, `.kra`/`.krz`/`.bundle` document types |
| `deps/ios-toolchain.cmake` | `krita-deps-management/tools/` (committed on the fork's `ios` branch) | Cross-compile toolchain for the dependency recipes (device or simulator SDK, arm64, static, iOS 17.0 minimum) |
| `deps/ios-toolchain-krita.cmake` | `krita-deps-management/tools/` (committed on the fork's `ios` branch) | The same for Krita itself: pre-seeded `try_run` results, `KRITA_STATIC_BUILD`, no updaters/Python/MLT |
| `deps/ext_qt-ios-branch.cmake` | `krita-deps-management/ext_qt/CMakeLists.txt` before its `else( APPLE )` branch; committed on the fork's `ios` branch | Static Qt 6 for iOS with macOS host tools, against the dependency prefix's libraries. Verified (`IOS_QT_BUILD.md`, `IOS_DEPS_BUILD.md`) |
| `deps/deps-ios.yml` | summary of the iOS entries in `krita-deps-management/latest/krita-deps.yml` | The iOS platform block, as committed |
| `screenshots/` | referenced by `IOS_QT_BUILD.md` | Qt examples on the simulator (Phase 2) |
| `../../IOS_PORT_PLAN.md` | read first on the Mac | The whole plan, with the Phase 2 brief to paste into Claude Code |

## Build outline (Mac)

1. Build the dependencies, Qt included, into one prefix per SDK with `tools/ios-build-deps.sh <iphoneos|iphonesimulator>` in krita-deps-management (see `IOS_DEPS_BUILD.md` for the host tools it needs).
2. Configure Krita:

   ```bash
   cmake -G Xcode <krita-src> \
     -DCMAKE_TOOLCHAIN_FILE=<deps>/tools/ios-toolchain-krita.cmake \
     -DCMAKE_PREFIX_PATH=<prefix> -DCMAKE_INSTALL_PREFIX=<install> \
     -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_TESTING=OFF \
     -DKRITA_IOS_DEVELOPMENT_TEAM=<team id>
   ```

   `KRITA_STATIC_BUILD` is on by default for iOS. `KRITA_STATIC_PLUGINS_ALLOWLIST` defaults to the painting set; `ALL` links every plugin.
3. Qt's own plugins (`QIOSIntegrationPlugin`, SQLite, image formats, SVG, the QtQuick and Controls QML plugins) are linked by Qt's CMake without any extra code; verified on the simulator (`IOS_KRITA_BUILD.md`).
4. Krita's data must be inside the `.app`, flat: `KoResourcePaths::getInstallationPrefix()` returns the executable's directory on iOS, so `share/` and `lib/qml` from `cmake --install` are copied to `krita.app/` (in a static build `install(TARGETS)` skips the static libraries). MLT is not built.
5. Sign and run: ad hoc on the simulator (done, see `IOS_KRITA_BUILD.md`); for the iPad, a development signature and `xcrun devicectl device install app` (Phase 5).

## Known gaps

- The app icon: `krita/CMakeLists.txt` skips icons on iOS; an asset catalog with `AppIcon` needs adding here.
- App lifecycle: autosave when the app goes to the background, and opening files handed over by the system (the Android `saveState` / `openFileFromIntent` JNI hooks in `krita/main.cc` have no iOS twin yet).
- File access outside the app container: `KoFileDialog` uses Qt's widget dialog on iOS, which only sees the sandbox. A `UIDocumentPickerViewController` wrapper and security-scoped bookmarks are needed for Phase 5; Phase 6 (bundles dropped into the Documents folder) works without them.
- `KisKineticScroller`, long-press and the Xiaomi pressure curve keep their Android-only JNI branches; the shared defaults apply on iOS.
