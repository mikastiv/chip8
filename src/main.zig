const std = @import("std");
const c = @import("c.zig");

fn printSdlError() void {
    const msg = c.SDL_GetError();
    std.log.err("{s}", .{msg});
}

pub fn main() !void {
    const result = c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO);
    if (result < 0) {
        printSdlError();
        return error.SdlInitFailed;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow(
        "Chip8",
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        800,
        600,
        0,
    ) orelse return error.SdlWindowCreationFailed;
    defer c.SDL_DestroyWindow(window);

    //const renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED)
    //    orelse return error.SdlRendererCreationFailed;

    c.SDL_ShowWindow(window);

    var event: c.SDL_Event = undefined;
    while (true) {
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                else => {},
            }
        }
    }
}
