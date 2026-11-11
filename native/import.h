#include "lv_conf.h"
#include "lvgl.h"
#include "host.h"

#if LVGL_VERSION_MAJOR != 9 || LVGL_VERSION_MINOR != 6
#error "ZUI currently targets LVGL 9.6.x"
#endif
