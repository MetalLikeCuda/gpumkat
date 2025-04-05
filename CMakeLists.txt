cmake_minimum_required(VERSION 3.10)

project(gpumkat)

# Specify the C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Add the include directories for json-c
include_directories(/opt/homebrew/Cellar/json-c/0.17/include)

set(SOURCES
    main.m
    modules/plugin_manager/plugin_manager.m
    modules/debug/debug.m
    modules/debug/timeline_debug.m
    modules/update/update.m
    modules/memory_tracker/memory_tracker.m
    modules/pipeline_statistics/pipeline_statistics.m
    modules/visualization/visualization.m
)

# Create the executable target
add_executable(gpumkat ${SOURCES})

# Link libraries and frameworks
target_link_libraries(gpumkat
    /opt/homebrew/Cellar/json-c/0.17/lib/libjson-c.dylib
    -lcurl
    -framework Foundation
    -framework Metal
    -framework MetalPerformanceShaders
    -framework QuartzCore
    -framework AppKit
)

find_package(CURL REQUIRED)
target_link_libraries(gpumkat PRIVATE CURL::libcurl)

include_directories(/opt/homebrew/Cellar/json-c/0.17/include)
target_link_directories(gpumkat PRIVATE /opt/homebrew/Cellar/json-c/0.17/lib)
target_link_libraries(gpumkat PRIVATE json-c)