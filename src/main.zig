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
pub const sample_rate = 48000;
pub const note_hz = 256.0;

const Keymap = std.AutoArrayHashMap(i32, Chip8.Key);

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);

    const stderr = std.io.getStdErr();
    if (args.len < 2) {
        try stderr.writeAll(usage);
        return error.MissingRomFile;
    }

    const rom = try readRomFile(args[1]);
    var chip8 = try Chip8.init(rom);

    var sdl = try Sdl.init("chip-8", window_width, window_height, sample_rate, note_hz);
    defer sdl.deinit();

    const keymap = try generateKeymap(std.heap.page_allocator, .{
        .{ c.SDLK_0, Chip8.Key.@"0" },
        .{ c.SDLK_1, Chip8.Key.@"1" },
        .{ c.SDLK_2, Chip8.Key.@"2" },
        .{ c.SDLK_3, Chip8.Key.@"3" },
        .{ c.SDLK_4, Chip8.Key.@"4" },
        .{ c.SDLK_5, Chip8.Key.@"5" },
        .{ c.SDLK_6, Chip8.Key.@"6" },
        .{ c.SDLK_7, Chip8.Key.@"7" },
        .{ c.SDLK_8, Chip8.Key.@"8" },
        .{ c.SDLK_9, Chip8.Key.@"9" },
        .{ c.SDLK_a, Chip8.Key.a },
        .{ c.SDLK_b, Chip8.Key.b },
        .{ c.SDLK_c, Chip8.Key.c },
        .{ c.SDLK_d, Chip8.Key.d },
        .{ c.SDLK_e, Chip8.Key.e },
        .{ c.SDLK_f, Chip8.Key.f },
    });

    const fps = 60.0;
    const instructions_per_sec = 600;

    const sec_per_frame = 1.0 / fps;
    const ms_per_frame = sec_per_frame * std.time.ms_per_s;
    const ns_per_frame = ms_per_frame * std.time.ns_per_ms;
    const instructions_per_frame = sec_per_frame * instructions_per_sec;

    var audio_state = false;

    var instruction_count: u32 = 0;
    var frames_to_render: u32 = 0;

    var timer_accumulator: u64 = 0;
    var last_instant = try std.time.Instant.now();

    while (true) {
        var quit = false;
        pollEvents(&chip8, &keymap, &quit);
        if (quit) break;

        while (instruction_count > 0 and !chip8.waiting_for_key.waiting) : (instruction_count -= 1) {
            chip8.executeIns();
        }

        const now = try std.time.Instant.now();
        const duration = now.since(last_instant);
        timer_accumulator += duration;
        last_instant = now;

        const ns: u64 = @intFromFloat(ns_per_frame);
        while (timer_accumulator > ns) {
            timer_accumulator -= ns;
            frames_to_render += 1;
        }

        if (frames_to_render > 0) {
            // Timers tick once per frame (60 Hz)
            chip8.regs.dt -|= 1;
            chip8.regs.st -|= 1;

            const chip8_audio = chip8.regs.st == 0;
            if (audio_state != chip8_audio) {
                c.SDL_PauseAudioDevice(sdl.audio_device, @intFromBool(chip8_audio));
            }

            audio_state = chip8_audio;

            var pixels: Chip8.PixelBuffer = undefined;
            chip8.renderToBuffer(&pixels);
            try sdl.presentFrame(&pixels);

            instruction_count += @intFromFloat(instructions_per_frame);
            frames_to_render -= 1;
        }

        if (chip8.waiting_for_key.waiting or frames_to_render == 0)
            c.SDL_Delay(@intFromFloat(ms_per_frame));
    }
}

fn pollEvents(chip8: *Chip8, keymap: *const Keymap, quit: *bool) void {
    quit.* = false;

    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event) != 0) {
        switch (event.type) {
            c.SDL_QUIT => quit.* = true,
            c.SDL_KEYDOWN, c.SDL_KEYUP => {
                const maybe_key = keymap.get(event.key.keysym.sym);
                if (maybe_key) |key| {
                    const key_value: u8 = @intFromEnum(key);
                    const is_key_down = event.key.type == c.SDL_KEYDOWN;
                    chip8.keyboard[key_value] = is_key_down;

                    if (chip8.waiting_for_key.waiting) {
                        if (is_key_down) {
                            chip8.regs.v[chip8.waiting_for_key.register] = key_value;
                        }

                        // wait for release
                        if (!is_key_down and chip8.regs.v[chip8.waiting_for_key.register] == key_value) {
                            chip8.waiting_for_key.waiting = false;
                        }
                    }
                }
            },
            else => {},
        }
    }
}

fn generateKeymap(allocator: std.mem.Allocator, pairs: anytype) !Keymap {
    const type_info = @typeInfo(@TypeOf(pairs));
    const len = type_info.@"struct".fields.len;
    const fields = type_info.@"struct".fields;

    var keymap = Keymap.init(allocator);
    try keymap.ensureUnusedCapacity(len);

    inline for (fields) |field| {
        const key = @field(pairs, field.name)[0];
        const value = @field(pairs, field.name)[1];
        keymap.putAssumeCapacity(key, value);
    }

    return keymap;
}

fn readRomFile(path: []const u8) ![]const u8 {
    const rom_file = try std.fs.cwd().openFile(path, .{});
    defer rom_file.close();

    const rom = try rom_file.readToEndAlloc(std.heap.page_allocator, max_rom_size);

    return rom;
}
