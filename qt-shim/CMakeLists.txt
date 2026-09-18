cmake_minimum_required(VERSION 3.21)
project(racketqtshim CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets PrintSupport)
qt_standard_project_setup()

add_library(racketqtshim SHARED
    src/shim.cpp
)

target_link_libraries(racketqtshim PRIVATE Qt6::Widgets Qt6::PrintSupport)

if(APPLE)
    find_library(APPLICATIONSERVICES_FRAMEWORK ApplicationServices REQUIRED)
    target_link_libraries(racketqtshim PRIVATE ${APPLICATIONSERVICES_FRAMEWORK})
endif()

set_target_properties(racketqtshim PROPERTIES
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)
