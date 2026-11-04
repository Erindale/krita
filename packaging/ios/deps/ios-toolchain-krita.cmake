# Toolchain for building Krita itself for iPadOS, on top of
# ios-toolchain.cmake. Mirrors tools/android-toolchain-krita.cmake in
# krita-deps-management (see ../README.md).
#
# Environment:
#   KRITA_IOS_DEVELOPMENT_TEAM    Apple developer team id, for code signing
#
# Unverified: nothing has been configured with this file yet.

# try_run() results that cannot be computed when cross-compiling
# (cmake/modules/CheckLibTIFFPSDSupport.cmake)
set(TIFF_HAS_PSD_TAGS TRUE)
set(TIFF_CAN_WRITE_PSD_TAGS TRUE)

# Static Qt means static Krita: libraries and plugins are linked into
# the executable (cmake/modules/KritaStaticBuild.cmake). This is already
# the default for iOS; set here so it cannot be switched off by accident.
set(KRITA_STATIC_BUILD ON CACHE BOOL "" FORCE)

# No update channel, no Python, no G'MIC, no MLT on a sideloaded app
set(ENABLE_UPDATERS OFF CACHE BOOL "" FORCE)
set(CMAKE_DISABLE_FIND_PACKAGE_Mlt7 ON CACHE BOOL "" FORCE)
set(CMAKE_DISABLE_FIND_PACKAGE_PythonLibrary ON CACHE BOOL "" FORCE)

if (DEFINED ENV{KRITA_IOS_DEVELOPMENT_TEAM})
    set(KRITA_IOS_DEVELOPMENT_TEAM "$ENV{KRITA_IOS_DEVELOPMENT_TEAM}" CACHE STRING "Apple developer team id")
endif()

include("${CMAKE_CURRENT_LIST_DIR}/ios-toolchain.cmake" REQUIRED)
