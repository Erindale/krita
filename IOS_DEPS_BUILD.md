# Krita's dependencies for iPadOS: Phase 3 build record

Phase 3 of the personal iPadOS port (see `IOS_PORT_PLAN.md`): Krita's dependencies cross-compiled into one static prefix per SDK, with Qt rebuilt against them. Phase 2 (Qt on its own) is in `IOS_QT_BUILD.md`.

**Result:**
- Every package Krita's CMake requires on a mobile Qt 6 build, plus the recommended ones, builds static for the iOS simulator and for the device: 41 recipes into one prefix each. None needed a source fix for iOS beyond guarding `QProcess`.
- Qt is rebuilt into the same prefix against the prefix's libraries. Krita configures against the simulator prefix with every required package found.
- Nothing of Krita is compiled yet; that is Phase 4.

Both SDKs are done. The device chain ran after the simulator one with the same recipes and needed no further changes. Its libraries carry the iOS device platform tag (`platform 2`), and Krita configures against the device prefix with no errors either.

## Where it lives

| | |
|---|---|
| Recipes | `https://github.com/Erindale/krita-deps-management`, branch `ios`, commit `5041ad5` (on top of Phase 2's `92fcb8a`) |
| Driver | `tools/ios-build-deps.sh <iphoneos\|iphonesimulator> [recipe ...]` in that repository: each recipe is configured like the CI does it (standalone project, `tools/ios-toolchain.cmake`, target `ext_install`), in dependency order, and the script stops if anything leaves a dylib in the prefix |
| Prefixes | `/Volumes/Krita/krita-ios/deps-iphonesimulator` and `deps-iphoneos` (1.2 GB each, 77 static libraries plus Qt's static frameworks) |
| Build trees | `/Volumes/Krita/krita-ios/build/deps-<sdk>/<recipe>` (13 GB per SDK). **Keep `build/deps-<sdk>/qt`**: the prefix's Qt records its host tools inside it (`ext_qt-prefix/tmp/hosttools/qtbase`), as the Android recipe does. The others can be deleted |
| Host tools | `/Volumes/Krita/krita-ios/host-tools`: a Python venv with meson 1.12.1 and pkgconf 3.0.7 (`pip install meson pkgconf`), and GNU gettext 0.21 built for the Mac with the repository's own `ext_gettext` recipe (`msgfmt`, `msgmerge` for ki18n). Nothing was installed on the internal disk |
| Jobs | 4 parallel jobs throughout, so the Mac stayed usable |

Command line, from the deps repository:

```bash
IOS_DEPS_ROOT=/Volumes/Krita/krita-ios \
IOS_HOST_TOOLS=/Volumes/Krita/krita-ios/host-tools/venv/bin:/Volumes/Krita/krita-ios/host-tools/prefix/bin \
tools/ios-build-deps.sh iphonesimulator      # or iphoneos
```

## What is in the prefix

| Group | Packages (version) |
|---|---|
| From the SDK | zlib 1.2.12, expat 2.7.4, iconv, bzip2. The `ext_zlib` and `ext_expat` recipes build nothing on iOS; they install `zlib.pc` and `expat.pc` pointing at the SDK's copies, for meson and pkg-config users |
| Images | libpng 1.6.58, libjpeg-turbo 3.1.4.1, libtiff 4.7.1, libwebp 1.6.0, giflib 5.2.1, OpenEXR 3.4.10 with Imath 3.2.2 and OpenJPH 0.26.3 |
| Colour, maths | lcms2 2.19, Eigen 5.0.1, xsimd 14.1.0, GSL 2.8, FFTW 3.3.9 |
| Text | FreeType 2.14.3, HarfBuzz 12.3.2, FriBidi 1.0.16, fontconfig 2.16.0, libunibreak 5.0 |
| Other | exiv2 0.28.8 (with brotli 1.2.1), Boost 1.90 (headers only, which is all Krita asks for), immer, zug, lager, json-c 0.18, libmypaint 1.6.1, libintl-lite, QuaZip 1.5 |
| Video | FFmpeg 8.0.1 (libavcodec 62.11) static, without programs and without external codec libraries; its own encoders (PNG/APNG, GIF, FLAC, AAC), libwebp, and VideoToolbox (Apple's hardware H.264/HEVC) |
| Qt | 6.11.3 (Krita's fork), static, against the prefix's zlib, libpng, libjpeg, FreeType, HarfBuzz, libtiff and libwebp (`Using system ... yes` for each). Only PCRE2 stays bundled; no ICU |
| KDE Frameworks 6.25 | ECM, KConfig, KCoreAddons, KWidgetsAddons, KCodecs, KCompletion, KGuiAddons, KI18n, KItemViews, KColorScheme |

**Deferred** (moved out of `@all` in `latest/krita-deps.yml`, into a block for the four existing platforms, so their sets do not change):
- optional importers: JPEG XL with highway, JPEG 2000, HEIF's libaom
- SeExpr and ICU
- the frameworks Krita does not link: karchive, kitemmodels, kimageformats, kwindowsystem
- MLT and ffmpeg's external codec libraries: flac, ogg, opus, SDL2, vpx, vorbis, theora, openh264, lame

Excluded as on Android: lzma, OCIO, libraw/kdcraw, Python and PyQt, Poppler.

## Times (simulator, 4 jobs)

| Step | Time |
|---|---|
| 28 libraries before Qt | about 8 min; the longest were ffmpeg 116 s, boost 101 s and freetype with harfbuzz 41 s |
| Qt host tools (developer build, `host_tools` target) | about 12 min |
| Qt for iOS | 15 min (900 s) |
| QuaZip and the frameworks | about 3.5 min |
| **Total** | **about 40 min** |

Device (4 jobs, everything from scratch including Qt's host tools): 35 min (2115 s), of which Qt took 26 min (1557 s) and ffmpeg 109 s. Both prefixes are 1.2 GB.

## Changes to `krita-deps-management`

All of them are inert off iOS: they sit behind `if (IOS)`, or in patches whose new code is behind `IOS` or `QT_CONFIG(process)`.

**Shared plumbing**

| File | Change | Why |
|---|---|---|
| `tools/ios-toolchain.cmake` | SDK and deployment target read from CMake variables first, then the environment | So every inner build gets them on its command line. The environment variable `IPHONEOS_DEPLOYMENT_TARGET` makes clang target iOS even for compiles meant for the Mac (it broke fribidi's generators), so the driver no longer exports it |
| | `CMAKE_SYSTEM_PROCESSOR arm64` | CMake leaves it empty on iOS; libjpeg-turbo stops at `string(TOLOWER)` |
| | `CMAKE_MACOSX_BUNDLE OFF` | CMake makes every executable an app bundle on iOS, which breaks the install rules for lcms2's (and others') tools. Krita's own target sets `MACOSX_BUNDLE TRUE` explicitly |
| | `CMAKE_FIND_ROOT_PATH` gets `CMAKE_PREFIX_PATH` too | Recipes that install into a temporary prefix (freetype's bootstrap) otherwise cannot see the dependency prefix |
| | `KRITA_IOS_TARGET_TRIPLE` (`arm64-apple-ios17.0[-simulator]`) | For meson and autotools |
| `tools/ios-toolchain-krita.cmake` | Added (the Phase 1 draft, unchanged) | Toolchain for Krita itself |
| `tools/ios-build-deps.sh` | Added | The driver above |
| `cmake/base-dep-options.cmake` | `if (IOS)` block | Passes the toolchain, SDK, deployment target, `BUILD_SHARED_LIBS=OFF` and `KF_IGNORE_PLATFORM_CHECK=ON` (the frameworks' metainfo does not list iOS) to every CMake sub-build. Gives autotools builds `--host=aarch64-apple-darwin`, static-only, the clang target and sysroot. The macOS flags, including `-ld_classic`, are not used |
| `cmake/KritaExternalProject.cmake` | macOS per-architecture macro only for `APPLE AND NOT IOS` | iOS is one architecture with a cross toolchain |
| `cmake/krita_initialize_meson.cmake`, `meson-host.ini.in` | iOS cross file and native file | Cross file: `-isysroot`/`-target`, `system = 'darwin'` with `subsystem = 'ios'` or `'ios-simulator'`, `cpu_family = 'aarch64'`, `default_library=static`. Native file: the Mac's compiler with an explicit `-target arm64-apple-macos`, for projects that build generators |
| `latest/krita-deps.yml` | `@all` split, `iOS` block (zlib, libintl-lite) | See above. krita-ci-utilities has no iOS flavour, so nothing reads it yet. The per-recipe `.kde-ci.yml` files are unchanged |

**Recipes**

| Recipe | Change on iOS | Why |
|---|---|---|
| ext_zlib, ext_expat | Install a `.pc` file for the SDK's library | Use the system copies, as Linux does |
| ext_png | `PNG_SHARED=OFF PNG_FRAMEWORK=OFF PNG_TOOLS=OFF` | libpng ignores `BUILD_SHARED_LIBS` |
| ext_jpeg | `ENABLE_SHARED=OFF ENABLE_STATIC=ON` | Same for libjpeg-turbo |
| ext_lcms2 | `LCMS2_BUILD_SHARED=OFF`, static, no tools/tests | lcms2 2.19 renamed its switches; the recipe's `BUILD_STATIC=FALSE` etc. no longer do anything on any platform (worth fixing upstream separately) |
| ext_giflib | `if (APPLE)` → `if (APPLE AND NOT IOS)` in the existing patch; new patch `0002-iOS-build-libgif-static.patch` | The patch adds `-mmacosx-version-min`, and the library was hard-coded `SHARED` |
| ext_gsl | static; `RUN_RESULT=0` pre-seeded | Its IEEE and stdio checks run test programs; Android assumes they pass, and they do on arm64 |
| ext_mypaint | new patch `0007-iOS-build-libmypaint-static.patch` | Hard-coded `SHARED` |
| ext_tiff | tools/tests/docs off; new patch `0002-Import-dependencies-of-a-static-libtiff.patch` | The tools fail to link a static libwebp (libsharpyuv is not pulled in). libtiff's installed config has a literal `# TODO: import dependencies` for static builds and references `CMath::CMath` without defining it, which broke Qt's configure. The patch imports ZLIB, JPEG and WebP and defines `CMath::CMath` |
| ext_openexr | builds the vendored OpenJPH (from the same tarball) as its own package first | A static OpenEXR with its internal OpenJPH exports a reference to an `openjph` target it never installs, so Krita's `find_package(OpenEXR)` failed. With OpenJPH installed, OpenEXR's config imports it |
| ext_ffmpeg | static, no programs, no external codec libraries | Krita's in-process encoder needs only the libraries. The codec recipes are not built for iOS yet. The other platforms keep exactly their old options, now grouped in two variables |
| ext_qt | `-system-zlib -system-libpng -system-libjpeg -system-freetype -system-harfbuzz -system-tiff -system-webp`, `-I/-L` and `CMAKE_PREFIX_PATH`/`CMAKE_FIND_ROOT_PATH` set to the prefix; deployment target from the toolchain | One copy of each library in the final static link (Phase 2 used the bundled ones) |
| ext_kconfig | patch `0001`: `QProcess` uses behind `QT_CONFIG(process)`. Patch `0002`: on iOS skip `kconf_update` and `kreadconfig`, link `kconfig_compiler` with `qt_no_entrypoint` | iOS Qt has no `QProcess`. Qt gives every iOS executable the UIKit entry point (`-e _qt_main_wrapper`), so command-line tools cannot link. `kconfig_compiler` stays because KF6ConfigConfig includes its export |
| ext_kwidgetsaddons | patch: `KMimeTypeEditor` without `QProcess` (reports the editor cannot start) | No `QProcess` |
| ext_kguiaddons | patch: AppKit and the macOS colour-scheme watcher only for `APPLE AND NOT IOS`; `KUrlHandler` skips khelpcenter without `QProcess` | The C++ already chooses the Qt backend on iOS (`Q_OS_MACOS`) |

## Krita configure check

Krita configures against both prefixes (shown for the simulator). This was configure only, with Ninja; Phase 4 uses the Xcode generator.

```bash
cmake -G Ninja <krita> \
  -DCMAKE_TOOLCHAIN_FILE=<deps>/tools/ios-toolchain-krita.cmake \
  -DKDECI_IOS_SDK=iphonesimulator -DIPHONEOS_DEPLOYMENT_TARGET=17.0 \
  -DCMAKE_PREFIX_PATH=<prefix> -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DBUILD_TESTING=OFF -DBUILD_WITH_QT6=ON -DALLOW_UNSTABLE=QT6
# with PATH including the host meson/pkg-config/gettext, and
# PKG_CONFIG_LIBDIR=<prefix>/lib/pkgconfig:<prefix>/share/pkgconfig
```

- **Found:** every package in the REQUIRED list, among them ECM, KF6 (Config, WidgetsAddons, Completion, CoreAddons, GuiAddons, I18n, ItemViews, ColorScheme), Qt6 with its private modules, PNG, Boost, Immer, Zug, Lager, TIFF, Eigen3, LibExiv2, LCMS2, xsimd, **LibAV**, ZLIB, QUAZIP, Freetype, HarfBuzz, Fontconfig, libunibreak, FriBidi and Gettext.
- **Optional, found:** OpenEXR, GSL, FFTW3, LibMyPaint, JPEG, GIF, WebP.
- **Not found, as intended:** HEIF, OpenJPEG, JPEGXL, KSeExpr, OpenColorIO, Poppler, KDcraw, SIP/PyQt6, and the Linux-only EGL and Wayland.

## For Phase 4

- **Prefix.** Point Krita at `deps-<sdk>` (Qt is inside it now; Phase 2's `qt-iphone*` prefixes are no longer needed). Keep `build/deps-<sdk>/qt` for Qt's host tools, or pass `-DQT_HOST_PATH=/Volumes/Krita/krita-ios/qt-host` (same Qt version, installed).
- **Static link order.** Some static libraries carry dependencies their CMake files may not spell out:
  - libtiff needs libwebp and libsharpyuv (the patched config now imports WebP).
  - FreeType and HarfBuzz depend on each other.
  - FFmpeg's `.pc` files list CoreMedia, CoreVideo, VideoToolbox, AudioToolbox, Security, CoreImage, Metal, libiconv and libbz2. `pkg_check_modules(... IMPORTED_TARGET)` reads them only with `--static` (`PKG_CONFIG_ARGN=--static` or `pkg_check_modules(... STATIC)`); expect to add that.
- **Command-line tools in Krita** (if any are built on iOS) need `qt_no_entrypoint`, as kconfig's do.
- **Runtime.**
  - fontconfig needs a `fonts.conf` that points at fonts inside the app, plus a writable cache directory.
  - ki18n uses libintl-lite, so catalogs are found the Android way.
  - Without ICU, QtCore uses its fallback collation and text boundaries.
- **Translations** need the host `msgfmt` (in `host-tools/prefix/bin`).
- **Upstream-worthy, unrelated to iOS:**
  - lcms2's recipe switches are stale on every platform.
  - libtiff's static config is incomplete everywhere.
