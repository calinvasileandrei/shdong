add_executable(shdong_bridge
    main.c
    usb_descriptors.c
)

target_include_directories(shdong_bridge PRIVATE ${CMAKE_CURRENT_LIST_DIR})

target_link_libraries(shdong_bridge PRIVATE
    shd_common
    pico_stdlib
    pico_unique_id
    tinyusb_device
)

pico_enable_stdio_usb(shdong_bridge 0)
pico_enable_stdio_uart(shdong_bridge 0)

pico_add_extra_outputs(shdong_bridge)
