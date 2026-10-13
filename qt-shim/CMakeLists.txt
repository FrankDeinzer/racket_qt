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

# canvas% 'gl (docs/HACKING.md §78): optional.  Without Qt6::OpenGL the
# shim still builds; the shim_gl_* exports then report "no GL" and racket/gui
# degrades exactly like an old shim binary (get-gl-context -> #f).
find_package(Qt6 OPTIONAL_COMPONENTS OpenGL)
if(TARGET Qt6::OpenGL)
    target_link_libraries(racketqtshim PRIVATE Qt6::OpenGL)
    target_compile_definitions(racketqtshim PRIVATE RQT_HAVE_GL=1)
    message(STATUS "racketqtshim: canvas% 'gl support ON (Qt6::OpenGL)")
else()
    message(STATUS "racketqtshim: canvas% 'gl support OFF (Qt6::OpenGL not found)")
endif()

if(APPLE)
    find_library(APPLICATIONSERVICES_FRAMEWORK ApplicationServices REQUIRED)
    target_link_libraries(racketqtshim PRIVATE ${APPLICATIONSERVICES_FRAMEWORK})
endif()

if(UNIX AND NOT APPLE)
    find_package(X11 REQUIRED)
    target_link_libraries(racketqtshim PRIVATE X11::X11)
endif()

set_target_properties(racketqtshim PROPERTIES
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)
