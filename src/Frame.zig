const std = @import("std");
const c = @import("c.zig");
const Chip8 = @import("Chip8.zig");

const Pixel = u32;
const Color = packed struct(Pixel) {
    const off: Color = .{
        .r = 0xCC,
        .g = 0x55,
        .b = 0x00,
        .a = @intCast(c.SDL_ALPHA_OPAQUE),
    };
    const on: Color = .{
        .r = 0xFF,
        .g = 0xA5,
        .b = 0x1C,
        .a = @intCast(c.SDL_ALPHA_OPAQUE),
    };

    r: u8,
    g: u8,
    b: u8,
    a: u8,

    fn fromByte(byte: u8, bit: u3) Color {
        const mask = @as(u8, 0x80) >> bit;
        return if (byte & mask == 0) off else on;
    }

    fn eql(a: Color, b: Color) bool {
        return @as(Pixel, @bitCast(a)) == @as(Pixel, @bitCast(b));
    }
};

pub const width = Chip8.screen_width;
pub const height = Chip8.screen_height;
pub const pitch = width * @sizeOf(Pixel);
pub const size = width * height * @sizeOf(Pixel);

pixels: [size]u8,

pub const init: @This() = .{ .pixels = std.mem.zeroes([size]u8) };

pub fn setByte(self: *@This(), x: usize, y: usize, byte: u8) void {
    inline for (0..8) |offset| {
        const new_color = Color.fromByte(byte, @intCast(offset));
        const index = (y * pitch) + (x * @sizeOf(Pixel)) + (offset * @sizeOf(Pixel));

        const old_color = self.readColor(index);

        if (old_color.eql(new_color)) {
            self.writeColor(index, Color.off);
        } else if (!new_color.eql(Color.off)) {
            self.writeColor(index, new_color);
        }
    }
}

pub fn hasCollision(self: *const @This(), x: usize, y: usize, byte: u8) bool {
    var result = false;

    inline for (0..8) |offset| {
        const new_color = Color.fromByte(byte, @intCast(offset));
        const index = (y * pitch) + (x * @sizeOf(Pixel)) + (offset * @sizeOf(Pixel));
        const old_color = self.readColor(index);

        if (new_color.eql(Color.off) and old_color.eql(Color.on))
            result = true;
    }

    return result;
}

pub fn clear(self: *@This()) void {
    const pixels = std.mem.bytesAsSlice(Pixel, &self.pixels);
    @memset(pixels, @bitCast(Color.off));
}

fn readColor(self: *const @This(), index: usize) Color {
    return .{
        .r = self.pixels[index + 0],
        .g = self.pixels[index + 1],
        .b = self.pixels[index + 2],
        .a = self.pixels[index + 3],
    };
}

fn writeColor(self: *@This(), index: usize, color: Color) void {
    self.pixels[index + 0] = color.r;
    self.pixels[index + 1] = color.g;
    self.pixels[index + 2] = color.b;
    self.pixels[index + 3] = color.a;
}
