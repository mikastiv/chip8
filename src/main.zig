const std = @import("std");
const c = @import("c.zig");
const Sdl = @import("Sdl.zig");
const Chip8 = @import("Chip8.zig");

const usage =
    \\usage: ./chip8 <rom>
    \\
;

const max_rom_size = std.math.maxInt(u16);

const window_width = 800;
const window_height = 600;
const sample_rate = 48000;
const note_hz = 256.0;
const volume = 0.10;
const instructions_per_frame = 50000;
const fps = 60.0; // This should always be 60
const sec_per_frame = 1.0 / fps;
const ms_per_frame = sec_per_frame * std.time.ms_per_s;
const ns_per_frame: u64 = @intFromFloat(ms_per_frame * std.time.ns_per_ms);

const Keymap = std.AutoArrayHashMap(i32, Chip8.Key);

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    const stderr = std.io.getStdErr();
    if (args.len < 2) {
        try stderr.writeAll(usage);
        return error.MissingRomFile;
    }

    const rom = try readRomFile(args[1]);
    var chip8 = try Chip8.init(rom);

    var sdl = try Sdl.init(allocator, "chip-8", window_width, window_height, sample_rate, note_hz, volume);
    defer sdl.deinit();

    var audio_state = false;

    var instruction_count: u64 = 0;

    var timer_accumulator: u64 = 0;
    var last_instant = try std.time.Instant.now();

    while (true) {
        var quit = false;
        pollEvents(&chip8, &quit);
        if (quit) break;

        while (instruction_count > 0 and !chip8.key_event.waiting) : (instruction_count -= 1) {
            chip8.executeIns();
        }

        const now = try std.time.Instant.now();
        const duration = now.since(last_instant);
        timer_accumulator += duration;
        last_instant = now;

        const new_frames = timer_accumulator / ns_per_frame;

        if (new_frames > 0) {
            timer_accumulator -= ns_per_frame * new_frames;

            // Timers tick once per frame (60 Hz)
            chip8.dt -|= @intCast(new_frames);
            chip8.st -|= @intCast(new_frames);

            const is_audio_on = chip8.st != 0;
            if (audio_state != is_audio_on) {
                c.SDL_PauseAudioDevice(sdl.audio_device, @intFromBool(!is_audio_on));
            }

            audio_state = is_audio_on;

            var pixels: Chip8.PixelBuffer = undefined;
            chip8.renderToBuffer(&pixels);
            try sdl.presentFrame(&pixels);
        }

        instruction_count = @as(u64, @intFromFloat(instructions_per_frame)) * @max(new_frames, 1);

        if (chip8.key_event.waiting or new_frames == 0)
            c.SDL_Delay(@intFromFloat(ms_per_frame));
    }
}

fn pollEvents(chip8: *Chip8, quit: *bool) void {
    quit.* = false;

    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event) != 0) {
        switch (event.type) {
            c.SDL_QUIT => quit.* = true,
            c.SDL_KEYDOWN, c.SDL_KEYUP => {
                if (event.key.keysym.sym == c.SDLK_ESCAPE) {
                    quit.* = true;
                    break;
                }

                const maybe_key = matchKey(event.key.keysym.sym);
                if (maybe_key) |key| {
                    const key_value: u8 = @intFromEnum(key);
                    const is_key_down = event.key.type == c.SDL_KEYDOWN;
                    chip8.keyboard[key_value] = is_key_down;

                    if (chip8.key_event.waiting) {
                        if (is_key_down) {
                            chip8.regs[chip8.key_event.register] = key_value;
                        }

                        // wait for release
                        if (!is_key_down and chip8.regs[chip8.key_event.register] == key_value) {
                            chip8.key_event.waiting = false;
                        }
                    }
                }
            },
            else => {},
        }
    }
}

fn matchKey(sdl_key: c_int) ?Chip8.Key {
    return switch (sdl_key) {
        c.SDLK_0 => Chip8.Key.@"0",
        c.SDLK_1 => Chip8.Key.@"1",
        c.SDLK_2 => Chip8.Key.@"2",
        c.SDLK_3 => Chip8.Key.@"3",
        c.SDLK_4 => Chip8.Key.@"4",
        c.SDLK_5 => Chip8.Key.@"5",
        c.SDLK_6 => Chip8.Key.@"6",
        c.SDLK_7 => Chip8.Key.@"7",
        c.SDLK_8 => Chip8.Key.@"8",
        c.SDLK_9 => Chip8.Key.@"9",
        c.SDLK_a => Chip8.Key.a,
        c.SDLK_b => Chip8.Key.b,
        c.SDLK_c => Chip8.Key.c,
        c.SDLK_d => Chip8.Key.d,
        c.SDLK_e => Chip8.Key.e,
        c.SDLK_f => Chip8.Key.f,
        else => null,
    };
}

fn readRomFile(path: []const u8) ![]const u8 {
    const rom_file = try std.fs.cwd().openFile(path, .{});
    defer rom_file.close();

    const rom = try rom_file.readToEndAlloc(std.heap.page_allocator, max_rom_size);

    return rom;
}
