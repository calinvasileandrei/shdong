// USB identity of the target board, as seen by the Sharer Mac.
#pragma once

// pid.codes test VID/PID: fine for development, replace before shipping.
#define SHD_USB_VID          0x1209
#define SHD_USB_PID          0x0001

#define SHD_USB_MANUFACTURER "Generic"
#define SHD_USB_PRODUCT      "USB Keyboard and Mouse"

// Release everything if the controller goes silent this long (app sends PING every 250 ms).
#define SHD_LINK_TIMEOUT_MS  1000
