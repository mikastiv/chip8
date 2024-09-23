const std = @import("std");
const c = @import("c.zig");
const Sdl = @import("Sdl.zig");
const Chip8 = @import("Chip8.zig");

const usage =
    \\usage: ./chip8 <rom>
    \\
;

const max_rom_size = std.math.maxInt(u16);

pub const window_width = 800;
pub const window_height = 600;
pub const note_hz = 256.0;
pub const sample_rate = 48000.0;

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);

    const stderr = std.io.getStdErr();
    if (args.len < 2) {
        try stderr.writeAll(usage);
        return error.MissingRomFile;
    }

    const rom = try readRomFile(args[1]);

    var chip8 = try Chip8.init(rom);

    var sdl = try Sdl.init(
        "chip-8",
        window_width,
        window_height,
        sample_rate,
        @ptrCast(&chip8.audio_context),
    );
    defer sdl.deinit();

    try chip8.run(&sdl, note_hz);
}

pub fn readRomFile(path: []const u8) ![]const u8 {
    const rom_file = try std.fs.cwd().openFile(path, .{});
    defer rom_file.close();

    const rom = try rom_file.readToEndAlloc(std.heap.page_allocator, max_rom_size);

    return rom;
}
