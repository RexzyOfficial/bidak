cmake_minimum_required(VERSION 3.22)
project(bidak_engine LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(ROOT "${CMAKE_CURRENT_SOURCE_DIR}/..")
set(SF16 "${ROOT}/external/sf16/src")
set(SF11 "${ROOT}/external/sf11/src")

if (ANDROID_ABI STREQUAL "arm64-v8a")
  message(STATUS "bidak: building Stockfish 16.1 for arm64-v8a")
  set(ENGINE_SRC_DIR "${SF16}")
  set(ENGINE_STD 17)
  set(SF_SOURCES
    "${SF16}/benchmark.cpp"
    "${SF16}/bitboard.cpp"
    "${SF16}/evaluate.cpp"
    "${SF16}/main.cpp"
    "${SF16}/misc.cpp"
    "${SF16}/movegen.cpp"
    "${SF16}/movepick.cpp"
    "${SF16}/position.cpp"
    "${SF16}/search.cpp"
    "${SF16}/thread.cpp"
    "${SF16}/timeman.cpp"
    "${SF16}/tt.cpp"
    "${SF16}/tune.cpp"
    "${SF16}/uci.cpp"
    "${SF16}/ucioption.cpp"
    "${SF16}/nnue/evaluate_nnue.cpp"
    "${SF16}/nnue/features/half_ka_v2_hm.cpp"
  )
elseif (ANDROID_ABI STREQUAL "armeabi-v7a")
  message(STATUS "bidak: building Stockfish 11 for armeabi-v7a")
  set(ENGINE_SRC_DIR "${SF11}")
  set(ENGINE_STD 11)
  set(SF_SOURCES
    "${SF11}/benchmark.cpp"
    "${SF11}/bitbase.cpp"
    "${SF11}/bitboard.cpp"
    "${SF11}/endgame.cpp"
    "${SF11}/evaluate.cpp"
    "${SF11}/main.cpp"
    "${SF11}/material.cpp"
    "${SF11}/misc.cpp"
    "${SF11}/movegen.cpp"
    "${SF11}/movepick.cpp"
    "${SF11}/pawns.cpp"
    "${SF11}/position.cpp"
    "${SF11}/psqt.cpp"
    "${SF11}/search.cpp"
    "${SF11}/thread.cpp"
    "${SF11}/timeman.cpp"
    "${SF11}/tt.cpp"
    "${SF11}/uci.cpp"
    "${SF11}/ucioption.cpp"
    "${SF11}/syzygy/tbprobe.cpp"
  )
else()
  message(FATAL_ERROR "ABI tidak didukung: ${ANDROID_ABI}")
endif()

add_library(stockfish SHARED
  "${CMAKE_CURRENT_SOURCE_DIR}/sf_bridge.cpp"
  ${SF_SOURCES}
)

target_compile_options(stockfish PRIVATE
  -Dmain=stockfish_main
  -fvisibility=hidden
  -O3
  -funroll-loops
)

target_compile_definitions(stockfish PRIVATE NDEBUG)

target_include_directories(stockfish PRIVATE "${ENGINE_SRC_DIR}")

set_target_properties(stockfish PROPERTIES
  CXX_STANDARD ${ENGINE_STD}
  CXX_STANDARD_REQUIRED ON
  OUTPUT_NAME "stockfish"
  PREFIX "lib"
)

target_link_libraries(stockfish PRIVATE log atomic)
