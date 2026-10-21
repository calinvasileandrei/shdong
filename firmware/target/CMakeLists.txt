add_executable(shdong_target
    main.c
    usb_descriptors.c
)

target_include_directories(shdong_target PRIVATE ${CMAKE_CURRENT_LIST_DIR})

target_link_libraries(shdong_target PRIVATE
    shd_common
    pico_stdlib
    pico_unique_id
    tinyusb_device
)

# UART0 is the board-to-board link and USB is ours, so no stdio anywhere
pico_enable_stdio_usb(shdong_target 0)
pico_enable_stdio_uart(shdong_target 0)

pico_add_extra_outputs(shdong_target)
