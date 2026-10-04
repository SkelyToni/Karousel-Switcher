/* SPDX-License-Identifier: GPL-2.0-or-later
 * Input driver for the separate virtual KWin smoke test only. */
#include "fake-input-client.h"
#include <wayland-client.h>
#include <linux/input-event-codes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static struct org_kde_kwin_fake_input *input;
static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version)
{
    if (!strcmp(interface, "org_kde_kwin_fake_input"))
        input = wl_registry_bind(registry, name, &org_kde_kwin_fake_input_interface,
                                 version < 6 ? version : 6);
}
static void removed(void *data, struct wl_registry *registry, uint32_t name) {}
static const struct wl_registry_listener listener = {global, removed};

static void key(struct wl_display *display, unsigned code, unsigned state)
{
    org_kde_kwin_fake_input_keyboard_key(input, code, state);
    wl_display_roundtrip(display);
}

int main(int argc, char **argv)
{
    const char *socket = getenv("WAYLAND_DISPLAY");
    if (!getenv("SCROLLTAB_TEST_SESSION") || !socket || strcmp(socket, "scrolltab-test")) {
        fprintf(stderr, "This input driver only runs in the isolated ScrollTab test session.\n");
        return 2;
    }
    int steps = argc > 1 ? atoi(argv[1]) : 1;
    int hold_ms = argc > 2 ? atoi(argv[2]) : 0;
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) return 3;
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &listener, NULL);
    wl_display_roundtrip(display);
    if (!input) {
        fprintf(stderr, "Fake input protocol unavailable in the test session\n");
        return 4;
    }
    org_kde_kwin_fake_input_authenticate(input, "ScrollTab smoke test", "Test isolated Alt+Tab behavior");
    wl_display_roundtrip(display);
    key(display, KEY_LEFTALT, 1);
    if (steps < 0) key(display, KEY_LEFTSHIFT, 1);
    for (int i = 0; i < abs(steps); ++i) {
        key(display, KEY_TAB, 1);
        /* Let KGlobalAccel deliver the initial shortcut before the next key;
         * normal physical key presses also span more than one event-loop turn. */
        usleep(15000);
        key(display, KEY_TAB, 0);
    }
    if (hold_ms > 0) usleep(hold_ms * 1000);
    if (argc > 3 && !strcmp(argv[3], "cancel")) {
        key(display, KEY_ESC, 1);
        key(display, KEY_ESC, 0);
    }
    if (steps < 0) key(display, KEY_LEFTSHIFT, 0);
    key(display, KEY_LEFTALT, 0);
    org_kde_kwin_fake_input_destroy(input);
    wl_display_roundtrip(display);
    wl_display_disconnect(display);
    return 0;
}
