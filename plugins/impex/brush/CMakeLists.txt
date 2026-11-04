add_subdirectory(tests)

# shared by the import and export plugins; one copy, so they can be
# linked into one binary
kis_add_library(kritabrushcommon STATIC KisAnimatedBrushAnnotation.cpp)
target_link_libraries(kritabrushcommon PUBLIC kritalibbrush kritaui)

set(kritabrushexport_PART_SRCS
    kis_brush_export.cpp
    KisWdgOptionsBrush.cpp
    )

ki18n_wrap_ui(kritabrushexport_PART_SRCS  wdg_export_gih.ui)

kis_add_library(kritabrushexport MODULE ${kritabrushexport_PART_SRCS})

target_link_libraries(kritabrushexport kritalibbrush kritalibpaintop kritaui kritaimpex kritabrushcommon)

install(TARGETS kritabrushexport  DESTINATION ${KRITA_PLUGIN_INSTALL_DIR})

set(kritabrushimport_PART_SRCS
    kis_brush_import.cpp
    )

ki18n_wrap_ui(kritabrushimport_PART_SRCS )

kis_add_library(kritabrushimport MODULE ${kritabrushimport_PART_SRCS})

target_link_libraries(kritabrushimport kritalibbrush kritaui kritabrushcommon)

install(TARGETS kritabrushimport  DESTINATION ${KRITA_PLUGIN_INSTALL_DIR})

install(FILES krita_brush.desktop  DESTINATION ${KDE_INSTALL_APPDIR})
