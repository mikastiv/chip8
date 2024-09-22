const std = @import("std");
const c = @import("c.zig");
const Sdl = @import("Sdl.zig");
const Chip8 = @import("Chip8.zig");

pub fn main() !void {
    var sdl = try Sdl.init("chip-8", 800, 600);
    defer sdl.deinit();

    var frame: Chip8.Frame = .init;

    var running = true;
    while (running) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => running = false,
                else => {},
            }
        }

        frame.clear();
        try sdl.presentFrame(&frame);
    }
}
