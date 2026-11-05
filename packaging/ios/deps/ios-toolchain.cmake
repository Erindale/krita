# Toolchain for cross-compiling Krita's dependencies and Krita itself for
# iPadOS. Mirrors tools/android-toolchain.cmake and tools/macos-toolchain.cmake
# in krita-deps-management; this file belongs in that repository's tools/
# directory (see ../README.md).
#
# Environment:
#   KDECI_IOS_SDK                 iphoneos (default) or iphonesimulator
#   IPHONEOS_DEPLOYMENT_TARGET    minimum iPadOS version, default 17.0 (the minimum Qt 6.11 supports)
#   CMAKE_PREFIX_PATH             the dependency install prefix
#
# Unverified: nothing has been configured with this file yet.

if (DEFINED ENV{KDECI_IOS_SDK})
    set(KDECI_IOS_SDK "$ENV{KDECI_IOS_SDK}")
else()
    set(KDECI_IOS_SDK iphoneos)
endif()
if (NOT KDECI_IOS_SDK MATCHES "^(iphoneos|iphonesimulator)$")
    message(FATAL_ERROR "KDECI_IOS_SDK must be iphoneos or iphonesimulator, got '${KDECI_IOS_SDK}'")
endif()

if (DEFINED ENV{IPHONEOS_DEPLOYMENT_TARGET})
    set(KRITA_IOS_DEPLOYMENT_TARGET "$ENV{IPHONEOS_DEPLOYMENT_TARGET}")
else()
    set(KRITA_IOS_DEPLOYMENT_TARGET "17.0")
endif()

set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_SYSROOT "${KDECI_IOS_SDK}" CACHE STRING "iOS SDK")
# arm64 for both the device and the simulator (Apple silicon Macs)
set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "iOS architectures")
set(CMAKE_OSX_DEPLOYMENT_TARGET "${KRITA_IOS_DEPLOYMENT_TARGET}" CACHE STRING "Minimum iPadOS version")

# Everything is linked statically into the app
set(BUILD_SHARED_LIBS OFF)
set(CMAKE_FIND_FRAMEWORK LAST)

# Only look for libraries and headers in the SDK and our own prefix;
# host tools (pkg-config, python, nasm...) come from the Mac
set(CMAKE_FIND_ROOT_PATH "${CMAKE_INSTALL_PREFIX}" "${CMAKE_FIND_ROOT_PATH}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# A toolchain file stops CMake from reading CMAKE_PREFIX_PATH from the
# environment (same workaround as macos-toolchain.cmake)
if (DEFINED ENV{CMAKE_PREFIX_PATH})
    set(CMAKE_PREFIX_PATH $ENV{CMAKE_PREFIX_PATH})
endif()

# try_run() cannot run on the target; recipes that need results pre-seed
# them (see ios-toolchain-krita.cmake)
set(CMAKE_CROSSCOMPILING TRUE)
