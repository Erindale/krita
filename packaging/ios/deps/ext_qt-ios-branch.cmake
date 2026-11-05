# iOS branch of ext_qt/CMakeLists.txt in krita-deps-management, as committed
# on the `ios` branch of https://github.com/Erindale/krita-deps-management
# (from transition.now/qt6). It sits after `elseif (NOT APPLE)` and
# before the final `else( APPLE )` macOS branch, since CMake sets APPLE for
# iOS too. Kept here for sessions without that repository.
#
# Built and verified on the Mac with Xcode 27.1: the recipe ran end to end for
# the simulator SDK and its prefix ran the QtQuick Controls gallery. See
# IOS_QT_BUILD.md at the repository root.

elseif (IOS)
    # Static Qt 6 for iPadOS (arm64 device or arm64 simulator), for a
    # personal sideloaded Krita build. Follows the Android branch: host
    # tools (moc, rcc, uic, qsb, qmlcachegen, lrelease...) are built for
    # the Mac first, then Qt is cross-compiled against them. Static is
    # Qt's only supported iOS configuration.
    #
    # The SDK comes from CMAKE_OSX_SYSROOT (set by tools/ios-toolchain.cmake
    # from KDECI_IOS_SDK), the minimum iOS version from the environment's
    # IPHONEOS_DEPLOYMENT_TARGET; Qt 6.11 needs 17.0 or later.
    #
    # Everything is linked statically into one app, so Qt uses the
    # prefix's libpng, libjpeg, freetype, harfbuzz, libtiff and libwebp
    # (and the SDK's zlib) instead of its bundled copies. Only pcre2 stays
    # bundled; Krita does not use it.
    include(${CMAKE_SOURCE_DIR}/FilterEnvironmentPathList.cmake)

    filter_environment_path_list(PATH "${EXTPREFIX}" HOST_ONLY_PATH)
    filter_environment_path_list(PKG_CONFIG_PATH "${EXTPREFIX}" HOST_ONLY_PKG_CONFIG_PATH)

    if (CMAKE_OSX_SYSROOT MATCHES "[Ss]imulator")
        set(IOS_QT_SDK iphonesimulator)
    elseif (DEFINED ENV{KDECI_IOS_SDK})
        set(IOS_QT_SDK $ENV{KDECI_IOS_SDK})
    else()
        set(IOS_QT_SDK iphoneos)
    endif()

    # from tools/ios-toolchain.cmake (IPHONEOS_DEPLOYMENT_TARGET), 17.0 by default
    if (CMAKE_OSX_DEPLOYMENT_TARGET)
        set(IOS_QT_DEPLOYMENT_TARGET ${CMAKE_OSX_DEPLOYMENT_TARGET})
    else()
        set(IOS_QT_DEPLOYMENT_TARGET 17.0)
    endif()

    message(STATUS "Building Qt for iOS SDK ${IOS_QT_SDK}, minimum iOS ${IOS_QT_DEPLOYMENT_TARGET}")

    set(IOS_QT_SUBMODULES qtbase qtdeclarative qtimageformats qttools qtsvg qttranslations qt5compat qtshadertools)
    list(JOIN IOS_QT_SUBMODULES "," IOS_QT_SUBMODULES_COMMA)

    set(IOS_QT_CONFIGURE_OPS
        -platform macx-ios-clang -sdk ${IOS_QT_SDK}
        -qt-host-path <TMP_DIR>/hosttools/qtbase
        -prefix ${EXTPREFIX}
        -release -static -opensource -confirm-license
        -submodules ${IOS_QT_SUBMODULES_COMMA}
        -nomake examples -nomake tests
        -no-dbus -no-qml-debug -no-libproxy -no-system-proxies
        -system-zlib -system-libpng -system-libjpeg -system-freetype -system-harfbuzz
        -qt-pcre -qt-sqlite
        -system-tiff -system-webp
        -I ${EXTPREFIX}/include
        -L ${EXTPREFIX}/lib
        # SecureTransport/Network.framework is used on Apple platforms
        -no-openssl
        -no-feature-assistant -no-feature-designer -feature-linguist
        --
        -Wno-dev
        -DCMAKE_OSX_ARCHITECTURES=arm64
        -DCMAKE_OSX_DEPLOYMENT_TARGET=${IOS_QT_DEPLOYMENT_TARGET}
        # find the dependencies in the prefix (the SDK is searched anyway)
        -DCMAKE_PREFIX_PATH=${EXTPREFIX}
        -DCMAKE_FIND_ROOT_PATH=${EXTPREFIX}
        # we ship our own version of freedesktop.org.xml database
        # which has Krita-specific formats and translations, so we
        # can disable the internal database shipped with Qt
        -DFEATURE_mimetype_database=OFF
    )

    ExternalProject_Add(
        ext_qt
        DOWNLOAD_DIR ${EXTERNALS_DOWNLOAD_DIR}

        GIT_REPOSITORY https://github.com/dimula73/qt5.git
        GIT_TAG ${QT_GIT_TAG}
        GIT_SUBMODULES ${IOS_QT_SUBMODULES}
        GIT_SUBMODULES_RECURSE false
        GIT_PROGRESS true
        GIT_REMOTE_UPDATE_STRATEGY REBASE

        # unset QMAKEFEATURES to allow incremental builds with run-ci-build.py
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env --unset=QMAKEFEATURES
            <SOURCE_DIR>/configure ${IOS_QT_CONFIGURE_OPS}

        BUILD_COMMAND ${CMAKE_COMMAND} --build . --parallel ${SUBMAKE_JOBS}
        INSTALL_COMMAND ${CMAKE_COMMAND} --build . --target install

        UPDATE_COMMAND ""
    )

    # Host tools for the Mac, as in the Android branch: a developer build
    # of qtbase, qtdeclarative, qtshadertools and qttools, of which only
    # the host_tools target is built. The iOS SDK variables are cleared so
    # that clang targets macOS.
    ExternalProject_Add_Step(ext_qt hosttools-dirs
        COMMENT "Making directories for host-tools"
        COMMAND ${CMAKE_COMMAND}
            -E make_directory <TMP_DIR>/hosttools
    )

    ExternalProject_Add_Step(ext_qt hosttools-configure
        COMMENT "Configuring host-tools (moc, qsb...)"
        COMMAND ${CMAKE_COMMAND}
            -E env
                --unset=QMAKEFEATURES
                # disable cross-compilation variables for host tools
                --unset=CMAKE_PREFIX_PATH
                --unset=CMAKE_TOOLCHAIN_FILE
                --unset=SDKROOT
                --unset=IPHONEOS_DEPLOYMENT_TARGET
                PKG_CONFIG_PATH=${HOST_ONLY_PKG_CONFIG_PATH}
                PATH=${HOST_ONLY_PATH}
            <SOURCE_DIR>/configure -release -developer-build
                # -developer-build implies -warnings-are-errors, and the
                # fork's qsurfaceformat.cpp (7ad4a8bc178) has an incomplete
                # switch that clang reports with -Wswitch
                -no-warnings-are-errors
                -submodules qtbase,qtdeclarative,qtshadertools,qttools
                -nomake tests -nomake examples
                -no-dbus
                -no-feature-assistant -no-feature-designer -feature-linguist
                -no-feature-sql
                -no-feature-testlib
                -- -Wno-dev -DCMAKE_OSX_ARCHITECTURES=arm64

        DEPENDEES hosttools-dirs patch
        WORKING_DIRECTORY <TMP_DIR>/hosttools
    )

    ExternalProject_Add_Step(ext_qt hosttools
        COMMENT "Building host-tools (moc, qsb...)"
        COMMAND ${CMAKE_COMMAND}
            -E env
                --unset=QMAKEFEATURES
                --unset=CMAKE_PREFIX_PATH
                --unset=CMAKE_TOOLCHAIN_FILE
                --unset=SDKROOT
                --unset=IPHONEOS_DEPLOYMENT_TARGET
                PKG_CONFIG_PATH=${HOST_ONLY_PKG_CONFIG_PATH}
                PATH=${HOST_ONLY_PATH}
            ${CMAKE_COMMAND} --build . --target host_tools --parallel ${SUBMAKE_JOBS}

        DEPENDEES hosttools-configure
        WORKING_DIRECTORY <TMP_DIR>/hosttools

        DEPENDERS configure
    )

    ExternalProject_Add_StepTargets(ext_qt hosttools)
    ExternalProject_Add_StepTargets(ext_qt configure)
