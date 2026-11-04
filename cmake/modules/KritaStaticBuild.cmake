# SPDX-FileCopyrightText: 2026 Krita contributors
# SPDX-License-Identifier: BSD-3-Clause
#
# Support for linking Krita, its libraries and its plugins into one
# executable, for platforms that cannot load shared libraries at runtime
# (iOS). Enabled with -DKRITA_STATIC_BUILD=ON.
#
# - kis_add_library() turns SHARED and MODULE libraries into STATIC ones
#   and records them (kis_static_build_adjust_library_args and
#   kis_static_build_register_library below)
# - plugins not listed in KRITA_STATIC_PLUGINS_ALLOWLIST are left out of
#   the default build target
# - kis_static_build_link_into(<executable>) links every Krita library and
#   allowlisted plugin into the executable whole-archive (so Qt resources
#   and static initializers are kept, and duplicate symbols fail the link)
#   and generates the Q_IMPORT_PLUGIN calls that register the plugins with
#   QPluginLoader::staticPlugins(), which KoJsonTrader reads

set(KRITA_STATIC_PLUGINS_ALLOWLIST_DEFAULT
    # colour engine; Krita quits without it
    kritalcmsengine
    # paintops
    kritadefaultpaintops
    kritacolorsmudgepaintop
    # tools; krita_flaketools provides the fallback InteractionTool
    kritadefaulttools
    kritaselectiontools
    kritatooltransform
    krita_flaketools
    # file formats
    kritakraimport
    kritakraexport
    kritapngimport
    kritapngexport
    # dockers
    kritalayerdocker
    kritapresetdocker
    kritacolorselectorng
    kritahistorydocker
)

set(KRITA_STATIC_PLUGINS_ALLOWLIST "${KRITA_STATIC_PLUGINS_ALLOWLIST_DEFAULT}" CACHE STRING
    "Plugin targets linked into a static build (KRITA_STATIC_BUILD), or ALL for every plugin")

function(_kis_static_build_is_plugin_dir out_var)
    string(FIND "${CMAKE_CURRENT_SOURCE_DIR}/" "${CMAKE_SOURCE_DIR}/plugins/" _pos)
    if (_pos EQUAL 0)
        set(${out_var} TRUE PARENT_SCOPE)
    else()
        set(${out_var} FALSE PARENT_SCOPE)
    endif()
endfunction()

function(_kis_static_build_is_allowlisted target out_var)
    if (KRITA_STATIC_PLUGINS_ALLOWLIST STREQUAL "ALL" OR target IN_LIST KRITA_STATIC_PLUGINS_ALLOWLIST)
        set(${out_var} TRUE PARENT_SCOPE)
    else()
        set(${out_var} FALSE PARENT_SCOPE)
    endif()
endfunction()

# Rewrites the arguments of an add_library() call in place
function(kis_static_build_adjust_library_args args_var)
    set(_args ${${args_var}})
    list(GET _args 0 _target)

    foreach(_keyword INTERFACE OBJECT ALIAS IMPORTED)
        if (_keyword IN_LIST _args)
            return()
        endif()
    endforeach()

    list(TRANSFORM _args REPLACE "^(SHARED|MODULE)$" "STATIC")
    if (NOT "STATIC" IN_LIST _args)
        list(INSERT _args 1 STATIC)
    endif()

    # Only allowlisted plugins (and whatever they depend on) are built.
    # Plugin helper libraries outside the allowlist build only when an
    # allowlisted plugin links them.
    _kis_static_build_is_plugin_dir(_in_plugins)
    _kis_static_build_is_allowlisted(${_target} _allowed)
    if (_in_plugins AND NOT _allowed AND NOT "EXCLUDE_FROM_ALL" IN_LIST _args)
        list(INSERT _args 2 EXCLUDE_FROM_ALL)
    endif()

    set(${args_var} ${_args} PARENT_SCOPE)
endfunction()

# Records a library target created while KRITA_STATIC_BUILD is on.
# IS_PLUGIN marks it as a plugin, i.e. something to Q_IMPORT_PLUGIN.
function(kis_static_build_register_library target)
    cmake_parse_arguments(ARG "IS_PLUGIN" "" "" ${ARGN})

    get_target_property(_type ${target} TYPE)
    if (NOT _type STREQUAL "STATIC_LIBRARY" AND NOT _type STREQUAL "INTERFACE_LIBRARY")
        return()
    endif()

    # test helpers (e.g. the dummy plugins in libs/koplugin/tests) are
    # never part of the application
    if ("${CMAKE_CURRENT_SOURCE_DIR}/" MATCHES "/tests/")
        return()
    endif()

    _kis_static_build_is_plugin_dir(_in_plugins)
    set_target_properties(${target} PROPERTIES KRITA_STATIC_IN_PLUGINS_DIR ${_in_plugins})
    set_property(GLOBAL APPEND PROPERTY KRITA_STATIC_LIBRARY_TARGETS ${target})

    if (ARG_IS_PLUGIN)
        set_property(GLOBAL APPEND PROPERTY KRITA_STATIC_PLUGIN_TARGETS ${target})
    endif()
endfunction()

# Called from kis_add_library() with the add_library() arguments
function(kis_static_build_register_add_library_call original_args)
    set(_args ${original_args} ${ARGN})
    list(GET _args 0 _target)
    if (NOT TARGET ${_target})
        return()
    endif()
    if ("MODULE" IN_LIST _args)
        kis_static_build_register_library(${_target} IS_PLUGIN)
    else()
        kis_static_build_register_library(${_target})
    endif()
endfunction()

function(_kis_static_build_collect_deps target known_targets visited_var)
    set(_visited ${${visited_var}})
    if (target IN_LIST _visited)
        return()
    endif()
    list(APPEND _visited ${target})

    get_target_property(_type ${target} TYPE)
    set(_deps)
    if (NOT _type STREQUAL "INTERFACE_LIBRARY")
        get_target_property(_link ${target} LINK_LIBRARIES)
        if (_link)
            list(APPEND _deps ${_link})
        endif()
    endif()
    get_target_property(_ilink ${target} INTERFACE_LINK_LIBRARIES)
    if (_ilink)
        list(APPEND _deps ${_ilink})
    endif()

    foreach(_dep IN LISTS _deps)
        string(REGEX REPLACE "^\\$<LINK_ONLY:(.*)>$" "\\1" _dep "${_dep}")
        if (_dep IN_LIST known_targets)
            _kis_static_build_collect_deps(${_dep} "${known_targets}" _visited)
        endif()
    endforeach()

    set(${visited_var} ${_visited} PARENT_SCOPE)
endfunction()

# Q_IMPORT_PLUGIN needs the plugin's class name, which is the first
# argument of K_PLUGIN_FACTORY_WITH_JSON (or the CLASSNAME of an ECM QML module)
function(_kis_static_build_find_plugin_classes target out_var)
    set(_classes)

    get_target_property(_qml_classname ${target} _ecm_qml_classname)
    if (_qml_classname)
        list(APPEND _classes ${_qml_classname})
    endif()

    get_target_property(_type ${target} TYPE)
    if (_type STREQUAL "INTERFACE_LIBRARY")
        set(${out_var} ${_classes} PARENT_SCOPE)
        return()
    endif()

    get_target_property(_sources ${target} SOURCES)
    get_target_property(_source_dir ${target} SOURCE_DIR)
    foreach(_source IN LISTS _sources)
        if (_source MATCHES "^\\$<" OR NOT _source MATCHES "\\.(cpp|cc|cxx)$")
            continue()
        endif()
        if (NOT IS_ABSOLUTE "${_source}")
            set(_source "${_source_dir}/${_source}")
        endif()
        if (NOT EXISTS "${_source}")
            continue()
        endif()
        file(STRINGS "${_source}" _lines REGEX "K_PLUGIN_FACTORY_WITH_JSON[ \t]*\\(")
        foreach(_line IN LISTS _lines)
            if (_line MATCHES "K_PLUGIN_FACTORY_WITH_JSON[ \t]*\\([ \t]*([A-Za-z0-9_]+)")
                list(APPEND _classes ${CMAKE_MATCH_1})
            endif()
        endforeach()
    endforeach()

    set(${out_var} ${_classes} PARENT_SCOPE)
endfunction()

function(kis_static_build_link_into executable)
    get_property(_all_targets GLOBAL PROPERTY KRITA_STATIC_LIBRARY_TARGETS)
    get_property(_plugin_targets GLOBAL PROPERTY KRITA_STATIC_PLUGIN_TARGETS)

    # every library outside plugins/ is part of the application
    set(_link_targets)
    foreach(_target IN LISTS _all_targets)
        get_target_property(_in_plugins ${_target} KRITA_STATIC_IN_PLUGINS_DIR)
        if (NOT _in_plugins)
            list(APPEND _link_targets ${_target})
        endif()
    endforeach()

    # allowlisted plugins and the plugin-side libraries they need
    set(_selected_plugins)
    foreach(_target IN LISTS _plugin_targets)
        _kis_static_build_is_allowlisted(${_target} _allowed)
        if (_allowed)
            list(APPEND _selected_plugins ${_target})
        endif()
    endforeach()
    if (NOT KRITA_STATIC_PLUGINS_ALLOWLIST STREQUAL "ALL")
        foreach(_name IN LISTS KRITA_STATIC_PLUGINS_ALLOWLIST)
            if (NOT _name IN_LIST _plugin_targets)
                message(WARNING "KRITA_STATIC_PLUGINS_ALLOWLIST: ${_name} is not a plugin target in this build")
            endif()
        endforeach()
    endif()

    set(_closure)
    foreach(_target IN LISTS _selected_plugins)
        _kis_static_build_collect_deps(${_target} "${_all_targets}" _closure)
    endforeach()
    list(APPEND _link_targets ${_closure})
    list(REMOVE_DUPLICATES _link_targets)

    set(_plugin_classes)
    foreach(_target IN LISTS _link_targets)
        _kis_static_build_find_plugin_classes(${_target} _classes)
        list(APPEND _plugin_classes ${_classes})
    endforeach()
    list(REMOVE_DUPLICATES _plugin_classes)

    set(_imports "")
    foreach(_class IN LISTS _plugin_classes)
        string(APPEND _imports "Q_IMPORT_PLUGIN(${_class})\n")
    endforeach()
    set(_registry "${CMAKE_CURRENT_BINARY_DIR}/${executable}_static_plugins.cpp")
    file(CONFIGURE OUTPUT "${_registry}" CONTENT
"// Generated by KritaStaticBuild.cmake: registers the plugins linked into
// this executable with QPluginLoader::staticPlugins(), see KoJsonTrader
#include <QtPlugin>

${_imports}"
    )
    target_sources(${executable} PRIVATE "${_registry}")

    # Link the archives whole, so that objects nothing references by name
    # (Qt resources, static initializers, plugin factories) are kept, and
    # duplicate symbols between libraries fail the link instead of being
    # resolved silently.
    target_link_libraries(${executable} PRIVATE ${_link_targets})
    set(_whole_archive_options)
    foreach(_target IN LISTS _link_targets)
        get_target_property(_type ${_target} TYPE)
        if (_type STREQUAL "STATIC_LIBRARY")
            if (APPLE)
                list(APPEND _whole_archive_options "LINKER:-force_load,$<TARGET_FILE:${_target}>")
            else()
                list(APPEND _whole_archive_options "$<TARGET_FILE:${_target}>")
            endif()
        endif()
    endforeach()
    if (NOT APPLE)
        list(PREPEND _whole_archive_options "LINKER:--whole-archive")
        list(APPEND _whole_archive_options "LINKER:--no-whole-archive")
    endif()
    target_link_options(${executable} PRIVATE ${_whole_archive_options})

    list(LENGTH _link_targets _target_count)
    list(LENGTH _plugin_classes _plugin_count)
    message(STATUS "Static build: linking ${_target_count} libraries into ${executable}, registering ${_plugin_count} plugins: ${_plugin_classes}")
endfunction()
