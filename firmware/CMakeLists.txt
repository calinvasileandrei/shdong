cmake_minimum_required(VERSION 3.13)

set(PICO_BOARD waveshare_rp2040_zero CACHE STRING "Board type")

include(pico_sdk_import.cmake)

project(shdong C CXX ASM)
set(CMAKE_C_STANDARD 11)

pico_sdk_init()

add_library(shd_common INTERFACE)
target_sources(shd_common INTERFACE
    ${CMAKE_CURRENT_LIST_DIR}/common/protocol.c
    ${CMAKE_CURRENT_LIST_DIR}/common/link.c
)
target_include_directories(shd_common INTERFACE ${CMAKE_CURRENT_LIST_DIR}/common)
target_link_libraries(shd_common INTERFACE pico_stdlib hardware_uart hardware_irq)

add_subdirectory(target)
add_subdirectory(bridge)
