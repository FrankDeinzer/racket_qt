# Qt-WASM + Racket CS 9.3 in ONE module (docs/HACKING.md §85, docs/2026-10-15_report-wasm-macos.md §3b).
#
# Qt's main() runs on the browser main thread (Qt-WASM cannot run under -sPROXY_TO_PTHREAD); Racket's own
# entry point (the fork's main_em.c, compiled with `main` renamed to `racket_em_main`, no fork change) runs
# in a pthread. All Racket inputs are taken from the racket-wasm-backend fork's build tree (.work/), which
# `racket build/main.rkt app apps/node-repl` (or any `app`) leaves behind -- run that first.
#
#   source ~/emsdk/emsdk_env.sh        # emcc 4.0.7: Qt 6.11.2 WASM checks the version exactly
#   ~/Qt/6.11.2/wasm_multithread/bin/qt-cmake -S qt-shim/wasm -B <build> -G Ninja \
#       -DCMAKE_MAKE_PROGRAM=<ninja> -DQT_HOST_PATH=$HOME/Qt/6.11.2/macos -DCMAKE_BUILD_TYPE=Release
#   cmake --build <build>
cmake_minimum_required(VERSION 3.21)
project(racketqt_wasm LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)

find_package(Qt6 REQUIRED COMPONENTS Widgets OpenGL PrintSupport)
qt_standard_project_setup()

set(RACKET_WASM_BACKEND "${CMAKE_CURRENT_LIST_DIR}/../../third_party/racket-wasm-backend"
    CACHE PATH "racket-wasm-backend fork checkout (with a finished build under .work/)")
get_filename_component(RACKET_WASM_BACKEND "${RACKET_WASM_BACKEND}" ABSOLUTE)
set(RS "${RACKET_WASM_BACKEND}/.work/racket/racket/src")
set(RC "${RS}/build/cs/c")
if(NOT EXISTS "${RC}/boot.o")
  message(FATAL_ERROR "No Racket WASM build under ${RC}. Run `racket build/main.rkt app apps/node-repl ...` "
                      "in ${RACKET_WASM_BACKEND} first (see docs/HACKING.md §85.4).")
endif()

# --- Racket entry point: the fork's main_em.c with `main` renamed (-Dmain=racket_em_main) -------------------
set(MAIN_EM_C "${RS}/cs/c/main_em.c")
set_source_files_properties(${MAIN_EM_C} PROPERTIES
  COMPILE_DEFINITIONS "main=racket_em_main;PORTABLE_BYTECODE"
  INCLUDE_DIRECTORIES "${RC}/ChezScheme/tpb32l/boot/tpb32l;${RC}/ChezScheme/tpb32l/c;${RS}/ChezScheme/c"
  COMPILE_OPTIONS "-sUSE_ZLIB=1")

# --- the shim and its WASM thread-proxy layer (generated from shim.cpp, tools/gen-proxies.py) ---------------
set(SHIM_CPP "${CMAKE_CURRENT_LIST_DIR}/../src/shim.cpp")
set(GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/gen")
find_program(PYTHON3 python3 REQUIRED NO_CMAKE_FIND_ROOT_PATH)
add_custom_command(
  OUTPUT "${GEN_DIR}/shim_wasm_proxy.cpp" "${GEN_DIR}/wasm_shim.inc" "${GEN_DIR}/rqt_wasm_extras.inc"
  COMMAND "${PYTHON3}" -I "${CMAKE_CURRENT_LIST_DIR}/tools/gen-proxies.py" "${SHIM_CPP}" "${RS}/cs/c/wasm_extras.inc" "${GEN_DIR}"
  DEPENDS "${SHIM_CPP}" "${CMAKE_CURRENT_LIST_DIR}/tools/gen-proxies.py" "${RS}/cs/c/wasm_extras.inc"
  COMMENT "Generating the WASM proxy layer for shim_* (gen-proxies.py)")
set_source_files_properties("${SHIM_CPP}" PROPERTIES COMPILE_DEFINITIONS "RQT_HAVE_GL=1")

# --- boot.c compiled here (not the fork's boot.o) so the shim symbols reach Chez' foreign-symbol table --------
# Same flags as the fork's own compile of boot.c, but RACKET_EXTRA_FOREIGN_INC names our rqt_wasm_extras.inc: it includes
# the fork's wasm_extras.inc and then the generated wasm_shim.inc (Sforeign_symbol for every shim_* entry).
set(BOOT_C "${RS}/cs/c/boot.c")
set_source_files_properties("${BOOT_C}" PROPERTIES
  COMPILE_DEFINITIONS "PBCHUNK_REGISTER;RACKET_EXTRA_FOREIGN_INC=\"rqt_wasm_extras.inc\""
  INCLUDE_DIRECTORIES "${GEN_DIR};${RS}/cs/c;${RC}/wasm-deps;${RC}/ChezScheme/tpb32l/boot/tpb32l;${RS}/rktio;${RC}/rktio"
  OBJECT_DEPENDS "${GEN_DIR}/rqt_wasm_extras.inc;${GEN_DIR}/wasm_shim.inc")

# --- Racket objects/archives, exactly as the fork's own link uses them (minus main_em.o / wasm_shell_io.o / boot.o)
file(GLOB RACKET_O "${RC}/*.o")
list(FILTER RACKET_O EXCLUDE REGEX "/(main_em|wasm_shell_io|boot)\\.o$")
set_source_files_properties(${RACKET_O} PROPERTIES EXTERNAL_OBJECT TRUE GENERATED TRUE)
set(RACKET_A
  "${RC}/ChezScheme/tpb32l/boot/tpb32l/libkernel.a"
  "${RC}/ChezScheme/tpb32l/lz4/lib/liblz4.a"
  "${RC}/rktio/librktio.a")

# --- native deps (cairo, pango, glib, ...): link flags in final link order, one token per line ------------
set(FLAGS_FILE "${RC}/wasm-deps/.wasm-deps-linkflags.txt")
if(NOT EXISTS "${FLAGS_FILE}")
  message(FATAL_ERROR "Missing ${FLAGS_FILE} (wasm-deps not built)")
endif()
file(STRINGS "${FLAGS_FILE}" DEP_TOKENS)
set(DEP_LIBDIRS "")
set(DEP_LIBS "")
set(expect_dir FALSE)
foreach(t ${DEP_TOKENS})
  if(expect_dir)
    list(APPEND DEP_LIBDIRS "${t}")
    set(expect_dir FALSE)
  elseif(t STREQUAL "-L")
    set(expect_dir TRUE)
  elseif(t MATCHES "^-L(.+)$")
    list(APPEND DEP_LIBDIRS "${CMAKE_MATCH_1}")
  elseif(t MATCHES "^-l")
    list(APPEND DEP_LIBS "${t}")
  endif()
endforeach()
list(REMOVE_DUPLICATES DEP_LIBDIRS)

qt_add_executable(racketqt_wasm main.cpp ${MAIN_EM_C} ${BOOT_C} ${SHIM_CPP}
  "${GEN_DIR}/shim_wasm_proxy.cpp" ${RACKET_O})
target_link_directories(racketqt_wasm PRIVATE ${DEP_LIBDIRS})
target_link_libraries(racketqt_wasm PRIVATE ${RACKET_A} ${DEP_LIBS} Qt6::Widgets Qt6::OpenGL Qt6::PrintSupport)

# Qt's own -s settings stay; ours extend EXPORTED_RUNTIME_METHODS/FUNCTIONS (the last -s wins, so both lists are merged here).
target_link_options(racketqt_wasm PRIVATE
  -sUSE_ZLIB=1 -sALLOW_TABLE_GROWTH=1 -sPTHREAD_POOL_SIZE=6
  "-sEXPORTED_RUNTIME_METHODS=UTF16ToString,stringToUTF16,JSEvents,specialHTMLTargets,FS,callMain,getValue,setValue,UTF8ToString,stringToUTF8,addFunction,removeFunction,HEAPU8,HEAP32,addRunDependency,removeRunDependency,FS_createPath,FS_createDataFile"
  "-sEXPORTED_FUNCTIONS=_main,__embind_initialize_bindings,_malloc,_free,_setThrew,_memcpy,_memset")

# --- files preloaded into the module's file system (same set as the fork's link, `core-preloads`) -----------
set(RACKET_PRELOADS
  "${RC}/petite-pbchunk.boot@petite.boot"
  "${RC}/scheme-pbchunk.boot@scheme.boot"
  "${RC}/racket-pbchunk.boot@racket.boot"
  "${RACKET_WASM_BACKEND}/.work/racket/racket/collects@/collects"
  "${RACKET_WASM_BACKEND}/.work/racket/racket/etc@/etc"
  "${RS}/cs/c/wasm-fonts/fonts.conf@/etc/fonts/fonts.conf"
  "${RS}/cs/c/wasm-fonts/DejaVuSans.ttf@/share/fonts/DejaVuSans.ttf")
# Optional package payload (racket/gui + the wx/qt backend): the unpacked tree from tools/unpack-share.py, holding share/ (and pkgs/).
set(RACKET_SHARE_DIR "" CACHE PATH "Unpacked payload tree (contains share/); empty = core collects only")
if(RACKET_SHARE_DIR)
  if(NOT EXISTS "${RACKET_SHARE_DIR}/share")
    message(FATAL_ERROR "RACKET_SHARE_DIR=${RACKET_SHARE_DIR} has no share/ directory")
  endif()
  list(APPEND RACKET_PRELOADS "${RACKET_SHARE_DIR}/share@/share")
  # --preload-file trees are invisible to Ninja; links.rktd is rewritten by every unpack-share.py run, so a new payload relinks.
  set_property(TARGET racketqt_wasm APPEND PROPERTY LINK_DEPENDS "${RACKET_SHARE_DIR}/share/links.rktd")
  if(EXISTS "${RACKET_SHARE_DIR}/pkgs")
    list(APPEND RACKET_PRELOADS "${RACKET_SHARE_DIR}/pkgs@/pkgs")
  endif()
endif()

set(RACKET_QT_MAIN "${CMAKE_CURRENT_LIST_DIR}/test/ffi-smoke.rkt" CACHE FILEPATH "Racket program preloaded as /app/main.rkt")
list(APPEND RACKET_PRELOADS "${RACKET_QT_MAIN}@/app/main.rkt")
set_property(TARGET racketqt_wasm APPEND PROPERTY LINK_DEPENDS "${RACKET_QT_MAIN}")   # preloaded files are invisible to Ninja
foreach(p ${RACKET_PRELOADS})
  target_link_options(racketqt_wasm PRIVATE "SHELL:--preload-file ${p}")
endforeach()
