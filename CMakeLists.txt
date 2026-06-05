cmake_minimum_required(VERSION 3.10)
project(gpumkat)

set(CMAKE_C_FLAGS_RELEASE "-O2 -Wall -Wextra")
set(CMAKE_BUILD_TYPE Release)

set(LIBRARY_SOURCES
    modules/plugin_manager/plugin_manager.m
    modules/debug/debug.m
    modules/debug/timeline_debug.m
    modules/update/update.m
    modules/memory_tracker/memory_tracker.m
    modules/pipeline_statistics/pipeline_statistics.m
    modules/visualization/visualization.m
    modules/testing/testing.m
    modules/lsp_server/metal_lsp_server.m
    modules/lsp_server/lsp_integration.m
)

set(EXECUTABLE_SOURCES
    main.m
)

find_package(CURL REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(JSONC REQUIRED IMPORTED_TARGET json-c)

add_library(gpumkat_lib SHARED ${LIBRARY_SOURCES})
set_target_properties(gpumkat_lib PROPERTIES
    OUTPUT_NAME "gpumkat"
    INSTALL_NAME_DIR "@rpath"
)

target_link_libraries(gpumkat_lib PRIVATE
    PkgConfig::JSONC
    CURL::libcurl
    "-framework Foundation"
    "-framework Metal"
    "-framework MetalPerformanceShaders"
    "-framework QuartzCore"
    "-framework AppKit"
    "-ObjC"
)

add_executable(gpumkat ${EXECUTABLE_SOURCES})
target_link_libraries(gpumkat PRIVATE
    gpumkat_lib
    PkgConfig::JSONC
    CURL::libcurl
    "-framework Foundation"
    "-framework CoreGraphics"
    "-framework CoreImage"
    "-framework Metal"
    "-framework MetalPerformanceShaders"
    "-framework QuartzCore"
    "-framework AppKit"
    "-ObjC"
)

set_target_properties(gpumkat PROPERTIES
    BUILD_RPATH "${CMAKE_BINARY_DIR}"
    INSTALL_RPATH "${CMAKE_INSTALL_PREFIX}/lib"
)
