add_subdirectory(tests)

# shared by the import and export plugins; one copy, so they can be
# linked into one binary
kis_add_library(kritagifcommon STATIC qgiflibhandler.cpp)
target_link_libraries(kritagifcommon PUBLIC kritaui ${GIF_LIBRARY})

set(kritagifexport_SOURCES
    kis_gif_export.cpp
    )

ki18n_wrap_ui(kritagifexport_SOURCES )

kis_add_library(kritagifexport MODULE ${kritagifexport_SOURCES})

target_link_libraries(kritagifexport kritaui kritaimpex kritagifcommon ${GIF_LIBRARY})

install(TARGETS kritagifexport  DESTINATION ${KRITA_PLUGIN_INSTALL_DIR})

set(kritagifimport_SOURCES
    kis_gif_import.cpp
    )

ki18n_wrap_ui(kritagifimport_SOURCES )

kis_add_library(kritagifimport MODULE ${kritagifimport_SOURCES})

target_link_libraries(kritagifimport kritaui kritagifcommon ${GIF_LIBRARY})

install(TARGETS kritagifimport  DESTINATION ${KRITA_PLUGIN_INSTALL_DIR})

install(FILES krita_gif.desktop DESTINATION ${KDE_INSTALL_APPDIR})
