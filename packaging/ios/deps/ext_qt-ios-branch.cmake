# iOS branch for ext_qt/CMakeLists.txt in krita-deps-management, branch
# transition.now/qt6. Insert it as `elseif (IOS)` BEFORE the final
# `else( APPLE )` macOS branch, since CMake sets APPLE for iOS too.
#
# It follows the Android Qt 6 branch: host tools (moc, rcc, qsb, ...) are
# built for the Mac first, then Qt is cross-compiled against them. Static
# is Qt's only supported iOS configuration. The bundled third-party
# libraries (-qt-zlib etc.) are a first step: once the dependency prefix
# exists, switch to -system-* so the final link holds one copy of each.
#
# Unverified: nothing has been built with this yet. ${QT_GIT_TAG},
# ${EXTPREFIX}, ${SUBMAKE_JOBS}, ${HOST_ONLY_*} and ${EXTERNALS_DOWNLOAD_DIR}
# are the recipe's existing variables.

elseif (IOS)

    if (NOT DEFINED ENV{KDECI_IOS_SDK})
        set(KDECI_IOS_SDK iphoneos)
    else()
        set(KDECI_IOS_SDK $ENV{KDECI_IOS_SDK})
    endif()

    set(IOS_QT_CONFIGURE_OPS
        -platform macx-ios-clang
        -sdk ${KDECI_IOS_SDK}
        -qt-host-path <TMP_DIR>/hosttools/qtbase
        -release -static
        -opensource -confirm-license
        -prefix ${EXTPREFIX}
        -nomake examples -nomake tests
        -skip qt3d -skip qtactiveqt -skip qtcanvas3d -skip qtconnectivity -skip qtdoc
        -skip qtlocation -skip qtsensors -skip qtserialport -skip qtwayland
        -skip qtwebchannel -skip qtwebsockets -skip qtwebview -skip qtwebengine
        -skip qtcharts -skip qtdatavis3d -skip qtgamepad -skip qtnetworkauth
        -skip qtremoteobjects -skip qtscxml -skip qtserialbus -skip qtspeech
        -skip qtvirtualkeyboard -skip qtmultimedia
        -no-dbus -no-qml-debug -no-libproxy -no-system-proxies -no-mtdev
        -qt-zlib -qt-libpng -qt-libjpeg -qt-freetype -qt-harfbuzz -qt-pcre -qt-sqlite
        -no-openssl   # SecureTransport is the default on Apple platforms
        -no-feature-assistant -no-feature-designer -feature-linguist
        --
        -DCMAKE_OSX_ARCHITECTURES=arm64
        -DCMAKE_OSX_DEPLOYMENT_TARGET=$ENV{IPHONEOS_DEPLOYMENT_TARGET}
        # Krita ships its own freedesktop.org.xml mime database
        -DFEATURE_mimetype_database=OFF
    )

    ExternalProject_Add(
        ext_qt
        DOWNLOAD_DIR ${EXTERNALS_DOWNLOAD_DIR}

        GIT_REPOSITORY https://github.com/dimula73/qt5.git
        GIT_TAG ${QT_GIT_TAG}
        GIT_SUBMODULES qtbase qtdeclarative qtimageformats qttools qtsvg qttranslations qt5compat qtshadertools
        GIT_SUBMODULES_RECURSE false
        GIT_PROGRESS true
        GIT_REMOTE_UPDATE_STRATEGY REBASE

        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env --unset=QMAKEFEATURES
            <SOURCE_DIR>/configure ${IOS_QT_CONFIGURE_OPS}

        BUILD_COMMAND ${CMAKE_COMMAND} --build . --parallel ${SUBMAKE_JOBS}
        INSTALL_COMMAND ${CMAKE_COMMAND} --build . --target install

        UPDATE_COMMAND ""
    )

    # Host tools, copied from the Android branch: a macOS developer build
    # of qtbase + qtdeclarative + qtshadertools + qttools without widgets
    ExternalProject_Add_Step(ext_qt hosttools-dirs
        COMMENT "Making directories for host-tools"
        COMMAND ${CMAKE_COMMAND} -E make_directory <TMP_DIR>/hosttools
    )

    ExternalProject_Add_Step(ext_qt hosttools-configure
        COMMENT "Configuring host-tools (moc, qsb...)"
        COMMAND ${CMAKE_COMMAND} -E env
            --unset=QMAKEFEATURES
            --unset=CMAKE_PREFIX_PATH
            --unset=CMAKE_TOOLCHAIN_FILE
            PKG_CONFIG_PATH=${HOST_ONLY_PKG_CONFIG_PATH}
            PATH=${HOST_ONLY_PATH}
            <SOURCE_DIR>/configure -release -developer-build
                -nomake tests -nomake examples
                -no-widgets -no-dbus
                -skip qt5compat -skip qtimageformats -skip qtsvg -skip qttranslations
                -no-feature-sql
                -no-feature-network
                -no-feature-testlib
                -- -Wno-dev -DCMAKE_OSX_ARCHITECTURES=arm64
        DEPENDEES hosttools-dirs patch
        WORKING_DIRECTORY <TMP_DIR>/hosttools
    )

    ExternalProject_Add_Step(ext_qt hosttools
        COMMENT "Building host-tools (moc, qsb...)"
        COMMAND ${CMAKE_COMMAND} -E env
            --unset=QMAKEFEATURES
            --unset=CMAKE_PREFIX_PATH
            --unset=CMAKE_TOOLCHAIN_FILE
            PKG_CONFIG_PATH=${HOST_ONLY_PKG_CONFIG_PATH}
            PATH=${HOST_ONLY_PATH}
            ${CMAKE_COMMAND} --build . --target host_tools --parallel ${SUBMAKE_JOBS}
        DEPENDEES hosttools-configure
        WORKING_DIRECTORY <TMP_DIR>/hosttools
        DEPENDERS configure
    )

    ExternalProject_Add_StepTargets(ext_qt hosttools)
    ExternalProject_Add_StepTargets(ext_qt configure)
