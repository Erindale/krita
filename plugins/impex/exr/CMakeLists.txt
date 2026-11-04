add_subdirectory(tests)

# shared by the import and export plugins; one copy, so they can be
# linked into one binary
set(kritaexrcommon_SOURCES
    exr_converter.cc
    kis_exr_layers_sorter.cpp
    exr_extra_tags.cpp
    )

kis_add_library(kritaexrcommon STATIC ${kritaexrcommon_SOURCES})
target_link_libraries(kritaexrcommon PUBLIC kritaui kritalibkra OpenEXR::IlmImf)

set(kritaexrimport_SOURCES
    exr_import.cc
    )

kis_add_library(kritaexrimport MODULE ${kritaexrimport_SOURCES})

target_link_libraries(kritaexrimport kritaui kritalibkra kritaexrcommon OpenEXR::IlmImf)

install(TARGETS kritaexrimport  DESTINATION ${KRITA_PLUGIN_INSTALL_DIR})

set(kritaexrexport_SOURCES
    exr_export.cc
    )

ki18n_wrap_ui(kritaexrexport_SOURCES exr_export_widget.ui )

kis_add_library(kritaexrexport MODULE ${kritaexrexport_SOURCES})

target_link_libraries(kritaexrexport kritaui kritalibkra kritaimpex kritaexrcommon OpenEXR::IlmImf)

install(TARGETS kritaexrexport  DESTINATION ${KRITA_PLUGIN_INSTALL_DIR})

install( FILES
    exrchannels.schema
    DESTINATION ${KDE_INSTALL_DATADIR}/krita/metadata/schemas)

install(FILES krita_exr.desktop DESTINATION ${KDE_INSTALL_APPDIR})
