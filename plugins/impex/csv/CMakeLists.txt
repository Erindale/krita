add_subdirectory(tests)

# import

# shared by the import and export plugins; one copy, so they can be
# linked into one binary
kis_add_library(kritacsvcommon STATIC csv_layer_record.cpp)
target_link_libraries(kritacsvcommon PUBLIC kritaui)

set(kritacsvimport_SOURCES
    kis_csv_import.cpp
    csv_loader.cpp
    csv_read_line.cpp
)

kis_add_library(kritacsvimport MODULE ${kritacsvimport_SOURCES})

target_link_libraries(kritacsvimport kritaui kritacsvcommon)

install(TARGETS kritacsvimport DESTINATION ${KRITA_PLUGIN_INSTALL_DIR})

# export

set(kritacsvexport_SOURCES
    kis_csv_export.cpp
    csv_saver.cpp
)

kis_add_library(kritacsvexport MODULE ${kritacsvexport_SOURCES})

target_link_libraries(kritacsvexport kritaui kritaimpex kritacsvcommon)

install(TARGETS kritacsvexport  DESTINATION ${KRITA_PLUGIN_INSTALL_DIR})

install(FILES krita_csv.desktop DESTINATION ${KDE_INSTALL_APPDIR})
