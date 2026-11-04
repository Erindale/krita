set(kritalevelfilter_SOURCES
    KisLevelsFilterPlugin.cpp
    KisLevelsFilter.cpp
    KisLevelsConfigWidget.cpp
    KisLevelsFilterConfiguration.cpp
    )
ki18n_wrap_ui(kritalevelfilter_SOURCES
    KisLevelsConfigWidget.ui
    )
kis_add_library(kritalevelfilter MODULE ${kritalevelfilter_SOURCES})
target_link_libraries(kritalevelfilter kritaui kritamultichannelcommon)
install(TARGETS kritalevelfilter  DESTINATION ${KRITA_PLUGIN_INSTALL_DIR})
