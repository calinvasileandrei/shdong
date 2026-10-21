# Locates the Pico SDK: uses PICO_SDK_PATH (env or -D) if set, otherwise downloads it.
# Must be included before project().

if (DEFINED ENV{PICO_SDK_PATH} AND (NOT PICO_SDK_PATH))
    set(PICO_SDK_PATH $ENV{PICO_SDK_PATH})
endif ()

if (NOT PICO_SDK_PATH)
    include(FetchContent)
    message(STATUS "PICO_SDK_PATH not set, downloading Pico SDK")
    FetchContent_Declare(pico_sdk
        GIT_REPOSITORY https://github.com/raspberrypi/pico-sdk
        GIT_TAG 2.1.1
        GIT_SUBMODULES lib/tinyusb
    )
    FetchContent_GetProperties(pico_sdk)
    if (NOT pico_sdk_POPULATED)
        FetchContent_Populate(pico_sdk)
    endif ()
    set(PICO_SDK_PATH ${pico_sdk_SOURCE_DIR})
endif ()

get_filename_component(PICO_SDK_PATH "${PICO_SDK_PATH}" REALPATH BASE_DIR "${CMAKE_BINARY_DIR}")
if (NOT EXISTS ${PICO_SDK_PATH}/pico_sdk_init.cmake)
    message(FATAL_ERROR "Not a Pico SDK: ${PICO_SDK_PATH}")
endif ()

set(PICO_SDK_PATH ${PICO_SDK_PATH} CACHE PATH "Path to the Pico SDK" FORCE)
include(${PICO_SDK_PATH}/pico_sdk_init.cmake)
