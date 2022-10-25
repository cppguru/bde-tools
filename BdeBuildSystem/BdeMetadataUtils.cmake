include_guard()

#.rst:
# .. command:: bbs_read_metadata(PACKAGE <package> [SOURCE_DIR <dir>])
# .. command:: bbs_read_metadata(GROUP   <group>   [SOURCE_DIR <dir>])
#
# PACKAGE mode reads the bde metadata files from the package dir and sets the following list variables in the parent scope
#  package_COMPONENTS
#  package_DEPENDS
#  package_PCDEPS
#  package_INCLUDE_DIRS
#  package_INCLUDE_FILES
#  package_SOURCE_DIRS
#  package_SOURCE_FILES
#  package_MAIN_SOURCE
#  package_TEST_DEPENDS
#  package_TEST_PCDEPS
#  package_TEST_SOURCES
#  package_G_TEST_SOURCES
#  package_METADATA_DIR
#
# GROUP mode will set the above variables for each package in the group.
# Additionally it will set the following list variables for the group:
#  group_PACKAGES
#  group_COMPONENTS
#  group_DEPENDS
#  group_PCDEPS
#  group_INCLUDE_DIRS
#  group_INCLUDE_FILES
#  group_SOURCE_DIRS
#  group_SOURCE_FILES
#  group_TEST_DEPENDS
#  group_TEST_PCDEPS
#  group_TEST_SOURCES
#  group_G_TEST_SOURCES
#  group_METADATA_DIRS
#
# SOURCE_DIR is optional and defaults to CMAKE_CURRENT_SOURCE_DIR
#
function(bbs_read_metadata)
    cmake_parse_arguments(PARSE_ARGV 0
                          ""
                          ""
                          "PACKAGE;GROUP;SOURCE_DIR"
                          "CUSTOM_PACKAGES")
    bbs_assert_no_unparsed_args("")

    if (_PACKAGE AND _GROUP)
        message(FATAL_ERROR "Cannot specify both PACKAGE and GROUP")
    endif()

    if (NOT _SOURCE_DIR)
        set(_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR})
    else()
        get_filename_component(_SOURCE_DIR ${_SOURCE_DIR} ABSOLUTE)
    endif()

    if (_PACKAGE)
        bbs_read_package_metadata(${_PACKAGE} ${_SOURCE_DIR})
    elseif (_GROUP)
        bbs_read_group_metadata(${_GROUP}
                                ${_SOURCE_DIR}
                                CUSTOM_PACKAGES "${_CUSTOM_PACKAGES}")
    endif()

endfunction()

# reads the package metadata in the given directory
macro(bbs_read_package_metadata pkg dir)
    set(_meta_dir ${dir}/package)
    set(${pkg}_METADATA_DIRS ${_meta_dir})

    unset(mems)

    _bbs_read_bde_metadata(${_meta_dir}/${pkg}.mem mems)
    _bbs_set_bde_component_lists(${dir} ${pkg} mems)

    if (EXISTS ${_meta_dir}/${pkg}.dep)
        _bbs_read_bde_metadata(${_meta_dir}/${pkg}.dep ${pkg}_DEPENDS)
        set(${pkg}_DEPENDS ${${pkg}_DEPENDS} PARENT_SCOPE)

        bbs_uor_to_pc_list("${${pkg}_DEPENDS}" ${pkg}_PCDEPS)
        set(${pkg}_PCDEPS ${${pkg}_PCDEPS} PARENT_SCOPE)
    endif()


    if (EXISTS ${_meta_dir}/${pkg}.t.dep)
        _bbs_read_bde_metadata(${_meta_dir}/${pkg}.t.dep ${pkg}_TEST_DEPENDS)
        set(${pkg}_TEST_DEPENDS ${${pkg}_TEST_DEPENDS} PARENT_SCOPE)

        bbs_uor_to_pc_list("${${pkg}_TEST_DEPENDS}" ${pkg}_TEST_PCDEPS)
        set(${pkg}_TEST_PCDEPS ${${pkg}_TEST_PCDEPS} PARENT_SCOPE)
    endif()

    set(${pkg}_METADATA_DIRS ${${pkg}_METADATA_DIRS} PARENT_SCOPE)
endmacro()

#.rst:
# .. command:: bbs_read_group_metadata(dir group)
#
# Reads the package group metadata in the given directory and set the group's
# and packages' variable in the parent scope.
macro(bbs_read_group_metadata group dir)
    cmake_parse_arguments(""
                          ""
                          ""
                          "CUSTOM_PACKAGES"
                          ${ARGN})
    bbs_assert_no_unparsed_args("")

    set(_meta_dir ${dir}/group)
    list(APPEND ${group}_METADATA_DIRS ${_meta_dir})

    unset(pkgs)

    _bbs_read_bde_metadata(${_meta_dir}/${group}.mem pkgs)

    set(${group}_DEPENDS "")
    set(${group}_PCDEPS  "")
    if (EXISTS ${_meta_dir}/${group}.dep)
        _bbs_read_bde_metadata(${_meta_dir}/${group}.dep ${group}_DEPENDS)
        set(${group}_DEPENDS ${${group}_DEPENDS})
        bbs_uor_to_pc_list("${${group}_DEPENDS}" ${group}_PCDEPS)
        set(${group}_PCDEPS ${${group}_PCDEPS})
    endif()

    set(${group}_TEST_DEPENDS "")
    set(${group}_TEST_PCDEPS  "")
    if (EXISTS ${_meta_dir}/${group}.t.dep)
        _bbs_read_bde_metadata(${_meta_dir}/${group}.t.dep ${group}_TEST_DEPENDS)
        set(${group}_TEST_DEPENDS ${${group}_TEST_DEPENDS})
        bbs_uor_to_pc_list("${${group}_TEST_DEPENDS}" ${group}_TEST_PCDEPS)
        set(${group}_TEST_PCDEPS ${${group}_TEST_PCDEPS})
    endif()

    foreach(pkg ${pkgs})
        list(APPEND ${group}_PACKAGES ${pkg})
        if (${pkg} IN_LIST _CUSTOM_PACKAGES)
            message(TRACE "Skipping metadata for custom ${pkg}")
        else()
            bbs_read_package_metadata(${pkg} ${_SOURCE_DIR}/${pkg})
            foreach(var COMPONENTS INCLUDE_DIRS INCLUDE_FILES
                        SOURCE_DIRS SOURCE_FILES
                        TEST_SOURCES G_TEST_SOURCES METADATA_DIRS)
               list(APPEND ${group}_${var}     ${${pkg}_${var}})
            endforeach()

            foreach(dep ${${pkg}_DEPENDS})
                if (NOT dep IN_LIST pkgs)
                    message(WARNING "Package \"${pkg}\" has \"${dep}\" dependency outside of package group (${pkgs}). Check ${pkg}/package/${pkg}.dep file.")
                endif()
            endforeach()
        endif()
    endforeach()

    foreach(var PACKAGES DEPENDS PCDEPS TEST_DEPENDS TEST_PCDEPS COMPONENTS
                INCLUDE_DIRS INCLUDE_FILES SOURCE_DIRS SOURCE_FILES
                TEST_SOURCES G_TEST_SOURCES METADATA_DIRS)
        set(${group}_${var} ${${group}_${var}} PARENT_SCOPE)
    endforeach()
endmacro()

# reads each line of the file into the 'items' list
macro(_bbs_read_bde_metadata filename items)
    # reconfigure if this file changes
    bbs_track_file(${filename})

    # Read all lines from 'filename'
    file(STRINGS "${filename}" lines)

    foreach(line IN LISTS lines)
        # Remove comments, leading & trailing spaces, squash spaces
        if (line)
            string(REGEX REPLACE " *#.*$" "" line "${line}")
            string(STRIP "${line}" line)
        endif()

        if (line)
            # Handle lines with multiple entries.
            string(REGEX REPLACE " +" ";" line_list "${line}")
            list(APPEND ${items} ${line_list})
        endif()
    endforeach()
endmacro()

macro(_bbs_set_bde_component_lists dir package mems)
    list(APPEND ${package}_INCLUDE_DIRS ${dir})
    list(APPEND ${package}_SOURCE_DIRS  ${dir})

    foreach(mem IN LISTS ${mems})
        list(APPEND ${package}_COMPONENTS ${mem})

        # This variable is used to generate a warning for the mem entries that 
        # do not have any existing headers/source files.
        set(component_found FALSE)

        # Special case entry in .mem file points to the actual file and not the
        # component
        if (EXISTS ${dir}/${mem})
            get_filename_component(file_suffix ${mem} EXT)
            if ("${file_suffix}" STREQUAL ".h")
                list(APPEND ${package}_INCLUDE_FILES ${dir}/${mem})
                continue() # Not strictly needed, but speeds thing up
            elseif("${file_suffix}" STREQUAL ".cpp")
                list(APPEND ${package}_SOURCE_FILES ${dir}/${mem})
                continue() # Not strictly needed, but speeds thing up
            elseif("${file_suffix}" STREQUAL ".c")
                list(APPEND ${package}_SOURCE_FILES ${dir}/${mem})
                continue() # Not strictly needed, but speeds thing up
            else()
                message(WARNING "Unrecognized entry in .mem file: ${mem}")
            endif()
        endif()

        if (EXISTS ${dir}/${mem}.h)
            set(component_found TRUE)
            list(APPEND ${package}_INCLUDE_FILES ${dir}/${mem}.h)
        endif()

        if (EXISTS ${dir}/${mem}.cpp)
            set(component_found TRUE)
            list(APPEND ${package}_SOURCE_FILES ${dir}/${mem}.cpp)

            if (EXISTS ${dir}/${mem}.t.cpp)
                list(APPEND ${package}_TEST_SOURCES ${dir}/${mem}.t.cpp)
            elseif(EXISTS ${dir}/${mem}.g.cpp)
                list(APPEND ${package}_G_TEST_SOURCES ${dir}/${mem}.g.cpp)
            endif()

            # finding numbered tests
            file(GLOB numbered_tests "${dir}/${mem}.*.t.cpp")
            foreach(ntest IN LISTS numbered_tests)
                list(APPEND ${package}_TEST_SOURCES ${ntest})
            endforeach()
        endif()

        if (EXISTS ${dir}/${mem}.c)
            set(component_found TRUE)
            list(APPEND ${package}_SOURCE_FILES ${dir}/${mem}.c)

            if (EXISTS ${dir}/${mem}.t.c)
                list(APPEND ${package}_TEST_SOURCES ${dir}/${mem}.t.c)
            endif()
            # There are no numbered test drivers for C. Add if needed.
        endif()

        if (NOT component_found)
            message(WARNING "No source files for component ${mem} found")
        endif()
    endforeach()

    # Check for a main file that is not listed as a component
    if (NOT ${package}_MAIN_SOURCE AND EXISTS ${dir}/${package}.m.cpp)
        list(APPEND ${package}_MAIN_SOURCE ${dir}/${package}.m.cpp)
    endif()

    # propagate the lists to the caller
    foreach(var COMPONENTS INCLUDE_DIRS INCLUDE_FILES
                SOURCE_DIRS SOURCE_FILES MAIN_SOURCE
                TEST_SOURCES G_TEST_SOURCES)
        set(${package}_${var} ${${package}_${var}} PARENT_SCOPE)
    endforeach()
endmacro()