#include "lua.h"

#include <ncurses.h>

int l_init(lua_State *L) {
    mousemask(BUTTON1_RELEASED, NULL);
    mouseinterval(0);
    return 0;
}

int l_close(lua_State *L) {
    mousemask(0, NULL);
    return 0;
}

int l_get_coords(lua_State *L) {
    MEVENT mouse_event;

    if (getmouse(&mouse_event) == OK && mouse_event.bstate == BUTTON1_RELEASED) {
        lua_pushinteger(L, mouse_event.x);
        lua_pushinteger(L, mouse_event.y);
        return 2;
    } else {
        return 0;
    }
}

int luaopen_vinspect_mouse(lua_State *L) {
    lua_newtable(L);
    lua_pushinteger(L, KEY_MOUSE);
    lua_setfield(L, -2, "KEY_MOUSE");
    lua_pushcfunction(L, l_init);
    lua_setfield(L, -2, "init");
    lua_pushcfunction(L, l_close);
    lua_setfield(L, -2, "close");
    lua_pushcfunction(L, l_get_coords);
    lua_setfield(L, -2, "get_coords");
    return 1;
}
