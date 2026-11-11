#ifndef ZUI_HOST_H
#define ZUI_HOST_H
#include <stdbool.h>
#include <stdint.h>
typedef struct zui_host zui_host;
zui_host *zui_host_create(const char *title, int width, int height);
void zui_host_destroy(zui_host *host);
bool zui_host_closing(const zui_host *host);
void zui_host_request_close(zui_host *host);
void zui_host_push_quit(void);
uint32_t zui_host_pump(zui_host *host);
void zui_host_delay(uint32_t milliseconds);
bool zui_host_save_bmp(zui_host *host, const char *path);
#endif
