const std = @import("std");
const c = @import("c.zig");

pub const screen_width = 64;
pub const screen_height = 32;

pub const Frame = struct {
    pub const Color = struct {
        r: u8,
        g: u8,
        b: u8,
    };

    pub const Pixel = u32;
    pub const width = screen_width;
    pub const height = screen_height;
    pub const pitch = width * @sizeOf(Pixel);
    pub const size = width * height * @sizeOf(Pixel);

    pixels: [size]u8,

    pub const init: @This() = .{ .pixels = std.mem.zeroes([size]u8) };

    pub inline fn putPixel(self: *Frame, x: usize, y: usize, color: Color) void {
        const index = (y * pitch) + (x * @sizeOf(Pixel));
        self.pixels[index + 0] = color.r;
        self.pixels[index + 1] = color.g;
        self.pixels[index + 2] = color.b;
        self.pixels[index + 3] = @intCast(c.SDL_ALPHA_OPAQUE);
    }

    pub fn clear(self: *Frame) void {
        @memset(&self.pixels, 0);
    }
};
