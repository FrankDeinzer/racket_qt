cmake_minimum_required(VERSION 3.21)
project(racketqtshim CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets)
qt_standard_project_setup()

add_library(racketqtshim SHARED
    src/shim.cpp
)

target_link_libraries(racketqtshim PRIVATE Qt6::Widgets)

set_target_properties(racketqtshim PROPERTIES
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)
