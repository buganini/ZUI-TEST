#include "import.h"
#include <SDL.h>
#include <stdlib.h>

struct zui_host {
    lv_display_t *display;
    lv_group_t *group;
    lv_indev_t *pointer;
    lv_indev_t *keyboard;
    SDL_atomic_t closing;
};

/* The SDL driver otherwise deinitializes LVGL inside its timer callback.
 * Defer quit until Zig has detached callbacks and destroyed its mounted tree.
 * This host exclusively owns SDL and LVGL; embedding is not supported yet. */
static int filter_event(void *data, SDL_Event *event) {
    zui_host *host = data;
    if(event->type == SDL_QUIT ||
       (event->type == SDL_WINDOWEVENT && event->window.event == SDL_WINDOWEVENT_CLOSE)) {
        SDL_AtomicSet(&host->closing, 1);
        return 0;
    }
    return 1;
}

zui_host *zui_host_create(const char *title, int width, int height) {
    if(lv_is_initialized()) return NULL;
    zui_host *host = calloc(1, sizeof(*host));
    if(!host) return NULL;
    lv_init();
    host->display = lv_sdl_window_create(width, height);
    if(!host->display || !lv_sdl_window_get_renderer(host->display)) goto fail;
    host->group = lv_group_create();
    if(!host->group) goto fail;
    lv_group_set_default(host->group);
    host->pointer = lv_sdl_mouse_create();
    host->keyboard = lv_sdl_keyboard_create();
    if(!host->pointer || !host->keyboard) goto fail;
    lv_indev_set_group(host->pointer, host->group);
    lv_indev_set_group(host->keyboard, host->group);
    lv_sdl_window_set_title(host->display, title);
    SDL_SetEventFilter(filter_event, host);
    SDL_StartTextInput();
    return host;
fail:
    zui_host_destroy(host);
    return NULL;
}

void zui_host_destroy(zui_host *host) {
    if(!host) return;
    SDL_SetEventFilter(NULL, NULL);
    SDL_StopTextInput();
    if(host->keyboard) lv_indev_delete(host->keyboard);
    if(host->pointer) lv_indev_delete(host->pointer);
    if(host->group) {
        lv_group_set_default(NULL);
        lv_group_delete(host->group);
    }
    if(host->display) lv_display_delete(host->display);
    lv_sdl_quit();
    lv_deinit();
    free(host);
}
bool zui_host_closing(const zui_host *host) { return SDL_AtomicGet((SDL_atomic_t *)&host->closing) != 0; }
void zui_host_request_close(zui_host *host) { SDL_AtomicSet(&host->closing, 1); }
void zui_host_push_quit(void) { SDL_Event event = {0}; event.type = SDL_QUIT; SDL_PushEvent(&event); }
uint32_t zui_host_pump(zui_host *host) { return zui_host_closing(host) ? 0 : lv_timer_handler(); }
void zui_host_delay(uint32_t milliseconds) { SDL_Delay(milliseconds); }
