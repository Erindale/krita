# Toolchain for cross-compiling Krita's dependencies and Krita itself for
# iPadOS. Mirrors tools/android-toolchain.cmake and tools/macos-toolchain.cmake.
#
# Settings, each read from a CMake variable first, then the environment:
#   KDECI_IOS_SDK                 iphoneos (default) or iphonesimulator
#   IPHONEOS_DEPLOYMENT_TARGET    minimum iPadOS version, default 17.0 (the
#                                 minimum Qt 6.11 supports)
# and from the environment only:
#   CMAKE_PREFIX_PATH             the dependency install prefix
#
# cmake/base-dep-options.cmake passes the first two on to every recipe's
# inner CMake build, so the environment is only needed for the outer one.

if (NOT KDECI_IOS_SDK)
    if (DEFINED ENV{KDECI_IOS_SDK})
        set(KDECI_IOS_SDK "$ENV{KDECI_IOS_SDK}")
    else()
        set(KDECI_IOS_SDK iphoneos)
    endif()
endif()
if (NOT KDECI_IOS_SDK MATCHES "^(iphoneos|iphonesimulator)$")
    message(FATAL_ERROR "KDECI_IOS_SDK must be iphoneos or iphonesimulator, got '${KDECI_IOS_SDK}'")
endif()

if (IPHONEOS_DEPLOYMENT_TARGET)
    set(KRITA_IOS_DEPLOYMENT_TARGET "${IPHONEOS_DEPLOYMENT_TARGET}")
elseif (DEFINED ENV{IPHONEOS_DEPLOYMENT_TARGET})
    set(KRITA_IOS_DEPLOYMENT_TARGET "$ENV{IPHONEOS_DEPLOYMENT_TARGET}")
else()
    set(KRITA_IOS_DEPLOYMENT_TARGET "17.0")
endif()

# clang target triple, for build systems that do not get it from CMake
# (meson cross files, autotools)
if (KDECI_IOS_SDK STREQUAL "iphonesimulator")
    set(KRITA_IOS_TARGET_TRIPLE "arm64-apple-ios${KRITA_IOS_DEPLOYMENT_TARGET}-simulator")
else()
    set(KRITA_IOS_TARGET_TRIPLE "arm64-apple-ios${KRITA_IOS_DEPLOYMENT_TARGET}")
endif()

set(CMAKE_SYSTEM_NAME iOS)
# CMake leaves this empty when cross-compiling for iOS, and several
# recipes (libjpeg-turbo, ...) read it
set(CMAKE_SYSTEM_PROCESSOR arm64)
set(CMAKE_OSX_SYSROOT "${KDECI_IOS_SDK}" CACHE STRING "iOS SDK")
# arm64 for both the device and the simulator (Apple silicon Macs)
set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "iOS architectures")
set(CMAKE_OSX_DEPLOYMENT_TARGET "${KRITA_IOS_DEPLOYMENT_TARGET}" CACHE STRING "Minimum iPadOS version")

# Everything is linked statically into the app
set(BUILD_SHARED_LIBS OFF)
# CMake makes every executable an app bundle on iOS, which breaks the
# install rules of the dependencies' helper tools. Krita's own app target
# sets MACOSX_BUNDLE explicitly.
set(CMAKE_MACOSX_BUNDLE OFF)
set(CMAKE_FIND_FRAMEWORK LAST)

# A toolchain file stops CMake from reading CMAKE_PREFIX_PATH from the
# environment (same workaround as macos-toolchain.cmake)
if (DEFINED ENV{CMAKE_PREFIX_PATH} AND NOT CMAKE_PREFIX_PATH)
    set(CMAKE_PREFIX_PATH $ENV{CMAKE_PREFIX_PATH})
endif()

# Only look for libraries and headers in the SDK (CMake adds it itself),
# the dependency prefix and the install prefix; host tools (pkg-config,
# python, meson...) come from the Mac. Recipes may install into a
# temporary prefix (freetype's bootstrap), so the dependency prefix from
# CMAKE_PREFIX_PATH has to be a root of its own.
list(APPEND CMAKE_FIND_ROOT_PATH ${CMAKE_INSTALL_PREFIX} ${CMAKE_PREFIX_PATH})
list(REMOVE_DUPLICATES CMAKE_FIND_ROOT_PATH)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# try_run() cannot run on the target; recipes that need results pre-seed
# them (see ios-toolchain-krita.cmake)
set(CMAKE_CROSSCOMPILING TRUE)
