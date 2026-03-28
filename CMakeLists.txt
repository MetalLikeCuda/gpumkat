cmake_minimum_required(VERSION 3.10)
project(gpumkat)

set(CMAKE_C_FLAGS_RELEASE "-O2 -Wall -Wextra")
set(CMAKE_BUILD_TYPE Release)

# Library sources (everything except main)
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

# Executable sources
set(EXECUTABLE_SOURCES
    main.m
)

# Create the shared library target
add_library(gpumkat_lib SHARED ${LIBRARY_SOURCES})

# Create the executable target
add_executable(gpumkat ${EXECUTABLE_SOURCES})

# Find required packages
find_package(CURL REQUIRED)

# Add include directories for both targets
target_include_directories(gpumkat_lib PRIVATE 
    /opt/homebrew/Cellar/json-c/0.18/include
)
target_include_directories(gpumkat PRIVATE 
    /opt/homebrew/Cellar/json-c/0.18/include
)

# Add library directories for both targets
target_link_directories(gpumkat_lib PRIVATE 
    /opt/homebrew/Cellar/json-c/0.18/lib
)
target_link_directories(gpumkat PRIVATE 
    /opt/homebrew/Cellar/json-c/0.18/lib
)

# Link libraries to the shared library
target_link_libraries(gpumkat_lib PRIVATE
    json-c
    CURL::libcurl
    "-framework Foundation"
    "-framework Metal"
    "-framework MetalPerformanceShaders"
    "-framework QuartzCore"
    "-framework AppKit"
)

# Link the executable to the shared library AND the frameworks it needs
target_link_libraries(gpumkat PRIVATE
    gpumkat_lib
    "-framework Foundation"
    "-framework CoreGraphics"
    "-framework CoreImage"
    "-framework Metal"
    "-framework MetalPerformanceShaders"
    "-framework QuartzCore"
    "-framework AppKit"
)

set_target_properties(gpumkat_lib PROPERTIES
    OUTPUT_NAME "gpumkat"
)
