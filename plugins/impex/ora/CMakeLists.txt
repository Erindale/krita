add_subdirectory(tests)

# shared by the import and export plugins; one copy, so they can be
# linked into one binary
set(kritaoracommon_SOURCES
    ora_converter.cpp
    kis_open_raster_load_context.cpp
    kis_open_raster_save_context.cpp
    kis_open_raster_stack_load_visitor.cpp
    kis_open_raster_stack_save_visitor.cpp
    )

kis_add_library(kritaoracommon STATIC ${kritaoracommon_SOURCES})
target_link_libraries(kritaoracommon PUBLIC kritaui)

set(kritaoraimport_SOURCES
    ora_import.cc
    )

kis_add_library(kritaoraimport MODULE ${kritaoraimport_SOURCES})

target_link_libraries(kritaoraimport kritaui kritaoracommon)

install(TARGETS kritaoraimport  DESTINATION ${KRITA_PLUGIN_INSTALL_DIR})

set(kritaoraexport_SOURCES
    ora_export.cc
    )

kis_add_library(kritaoraexport MODULE ${kritaoraexport_SOURCES})

target_link_libraries(kritaoraexport kritaui kritaimpex kritaoracommon)

install(TARGETS kritaoraexport  DESTINATION ${KRITA_PLUGIN_INSTALL_DIR})

install(FILES krita_ora.desktop DESTINATION ${KDE_INSTALL_APPDIR})
