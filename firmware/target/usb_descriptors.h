#pragma once

// HID instances (order of HID interfaces in the configuration descriptor)
enum {
    HID_INST_KEYBOARD = 0,
    HID_INST_MOUSE    = 1,
};

// Report IDs on HID_INST_MOUSE. The keyboard interface has no report IDs (boot protocol).
enum {
    RID_MOUSE_ABS = 1,
    RID_MOUSE_REL = 2,
    RID_CONSUMER  = 3,
};
