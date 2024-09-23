const std = @import("std");
const c = @import("c.zig");
const Sdl = @import("Sdl.zig");

pub const screen_width = 64;
pub const screen_height = 32;

const execution_frequency = 1.0 / 500.0;
const memory_size = 4096;
const stack_size = 16;

const program_start_address = 0x200;

regs: Registers,
stack: Stack,
memory: Memory,
frame: Frame,
rng: std.Random.DefaultPrng,
keyboard: [Key.count]bool,

pub const Frame = struct {
    pub const Color = enum(u8) {
        black = 0x00,
        white = 0xFF,

        fn fromByte(byte: u8, bit: u3) Color {
            const mask = @as(u8, 0x80) >> bit;
            return if (byte & mask == 0) .black else .white;
        }
    };

    pub const Pixel = u32;
    pub const width = screen_width;
    pub const height = screen_height;
    pub const pitch = width * @sizeOf(Pixel);
    pub const size = width * height * @sizeOf(Pixel);

    pixels: [size]u8,

    pub const init: Frame = .{ .pixels = std.mem.zeroes([size]u8) };

    pub fn setByte(self: *Frame, x: usize, y: usize, byte: u8) void {
        inline for (0..8) |offset| {
            const color = Color.fromByte(byte, @intCast(offset));

            const index = (y * pitch) + (x * @sizeOf(Pixel)) + (offset * @sizeOf(Pixel));

            self.pixels[index + 0] ^= @intFromEnum(color);
            self.pixels[index + 1] ^= @intFromEnum(color);
            self.pixels[index + 2] ^= @intFromEnum(color);
            self.pixels[index + 3] = @intCast(c.SDL_ALPHA_OPAQUE);
        }
    }

    pub fn hasCollision(self: *const Frame, x: usize, y: usize, byte: u8) bool {
        var result = false;

        inline for (0..8) |offset| {
            const new_color = Color.fromByte(byte, @intCast(offset));

            const index = (y * pitch) + (x * @sizeOf(Pixel)) + (offset * @sizeOf(Pixel));
            const old_color: Color = @enumFromInt(self.pixels[index]);

            if (new_color == .black and old_color == .white)
                result = true;
        }

        return result;
    }

    pub fn clear(self: *Frame) void {
        @memset(&self.pixels, 0);
    }
};

const Stack = [stack_size]u16;
const Memory = [memory_size]u8;
const Opcode = u16;

const Registers = struct {
    const count = 16;
    const flags = 0xF;

    v: [count]u8,
    i: u16,
    dt: u8,
    st: u8,
    sp: u8,
    pc: u16,

    const init: Registers = .{
        .v = std.mem.zeroes([count]u8),
        .i = 0,
        .dt = 0,
        .st = 0,
        .sp = 0,
        .pc = 0x200,
    };
};

const Key = enum {
    const count = std.enums.values(Key).len;

    @"0",
    @"1",
    @"2",
    @"3",
    @"4",
    @"5",
    @"6",
    @"7",
    @"8",
    @"9",
    a,
    b,
    c,
    d,
    e,
    f,

    fn fromSdlKey(key: i32) ?Key {
        return switch (key) {
            c.SDLK_0 => .@"0",
            c.SDLK_1 => .@"1",
            c.SDLK_2 => .@"2",
            c.SDLK_3 => .@"3",
            c.SDLK_4 => .@"4",
            c.SDLK_5 => .@"5",
            c.SDLK_6 => .@"6",
            c.SDLK_7 => .@"7",
            c.SDLK_8 => .@"8",
            c.SDLK_9 => .@"9",
            c.SDLK_a => .a,
            c.SDLK_b => .b,
            c.SDLK_c => .c,
            c.SDLK_d => .d,
            c.SDLK_e => .e,
            c.SDLK_f => .f,
            else => return null,
        };
    }
};

pub fn init(rom: []const u8) !@This() {
    if (rom.len > memory_size - program_start_address)
        return error.ProgramTooLarge;

    var self: @This() = .{
        .regs = .init,
        .stack = std.mem.zeroes(Stack),
        .memory = std.mem.zeroes(Memory),
        .frame = .init,
        .rng = std.Random.DefaultPrng.init(0),
        .keyboard = std.mem.zeroes([Key.count]bool),
    };

    @memcpy(self.memory[0..default_character_set.len], &default_character_set);
    @memcpy(self.memory[program_start_address .. program_start_address + rom.len], rom);

    return self;
}

pub fn run(self: *@This(), sdl: *Sdl) !void {
    var running = true;
    while (running) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => running = false,
                c.SDL_KEYDOWN, c.SDL_KEYUP => {
                    const maybe_key = Key.fromSdlKey(event.key.keysym.sym);
                    if (maybe_key) |key| {
                        self.keyboard[@intFromEnum(key)] = event.key.type == c.SDL_KEYDOWN;
                    }
                },
                else => {},
            }
        }

        const opcode = self.readNextOpcode();
        var render_frame = false;
        self.execute(opcode, &running, &render_frame);

        if (render_frame) {
            try sdl.presentFrame(&self.frame);
        }
    }
}

fn execute(self: *@This(), opcode: Opcode, running: *bool, render: *bool) void {
    const v = &self.regs.v;

    const nnn = opcode & 0xFFF;
    const n = opcode & 0xF;
    const x = (opcode >> 8) & 0xF;
    const y = (opcode >> 4) & 0xF;
    const kk: u8 = @intCast(opcode & 0xFF);
    switch (opcode) {
        0x00E0 => self.frame.clear(),
        0x00EE => self.regs.pc = self.pop(),
        else => switch (opcode & 0xF000) {
            0x0000 => {},
            0x1000 => self.regs.pc = nnn,
            0x2000 => {
                self.push(self.regs.pc);
                self.regs.pc = nnn;
            },
            0x3000 => if (v[x] == kk) {
                self.regs.pc +%= 2;
            },
            0x4000 => if (v[x] != kk) {
                self.regs.pc +%= 2;
            },
            0x5000 => switch (opcode & 0xF) {
                0x0 => if (v[x] == v[y]) {
                    self.regs.pc +%= 2;
                },
                else => invalidInstruction(opcode),
            },
            0x6000 => v[x] = kk,
            0x7000 => v[x] +%= kk,
            0x8000 => switch (opcode & 0xF) {
                0x0 => v[x] = v[y],
                0x1 => v[x] |= v[y],
                0x2 => v[x] &= v[y],
                0x3 => v[x] ^= v[y],
                0x4 => {
                    const result = @as(u16, v[x]) + @as(u16, v[y]);
                    v[x] = @truncate(result);
                    v[Registers.flags] = @intFromBool(result > 0xFF);
                },
                0x5 => {
                    const flag = v[x] >= v[y];
                    v[x] -%= v[y];
                    v[Registers.flags] = @intFromBool(flag);
                },
                0x6 => {
                    const flag = v[x] & 0x1 != 0;
                    v[x] >>= 1;
                    v[Registers.flags] = @intFromBool(flag);
                },
                0x7 => {
                    const flag = v[y] >= v[x];
                    v[x] = v[y] -% v[x];
                    v[Registers.flags] = @intFromBool(flag);
                },
                0xE => {
                    const flag = v[x] & 0x8 != 0;
                    v[x] <<= 1;
                    v[Registers.flags] = @intFromBool(flag);
                },
                else => invalidInstruction(opcode),
            },
            0x9000 => switch (opcode & 0xF) {
                0x0 => if (v[x] != v[y]) {
                    self.regs.pc +%= 2;
                },
                else => invalidInstruction(opcode),
            },
            0xA000 => self.regs.i = nnn,
            0xB000 => self.regs.pc = nnn +% v[0],
            0xC000 => v[x] = self.rng.random().int(u8) & kk,
            0xD000 => {
                const address = self.regs.i;
                const sprite = self.memory[address .. address + n];

                var collision = false;

                for (sprite, 0..) |byte, sprite_y| {
                    const col = v[x] % screen_width;
                    const row = (v[y] + sprite_y) % screen_height;

                    if (self.frame.hasCollision(col, row, byte))
                        collision = true;

                    self.frame.setByte(col, row, byte);
                }

                self.regs.v[Registers.flags] = @intFromBool(collision);

                render.* = true;
            },
            0xE000 => switch (opcode & 0xFF) {
                0x9E => if (self.keyboard[v[x]]) {
                    self.regs.pc +%= 2;
                },
                0xA1 => if (!self.keyboard[v[x]]) {
                    self.regs.pc +%= 2;
                },
                else => invalidInstruction(opcode),
            },
            0xF000 => switch (opcode & 0xFF) {
                0x07 => v[x] = self.regs.dt,
                0x0A => loop: while (true) {
                    var event: c.SDL_Event = undefined;
                    while (c.SDL_PollEvent(&event) != 0) {
                        switch (event.type) {
                            c.SDL_QUIT => {
                                running.* = false;
                                break :loop;
                            },
                            c.SDL_KEYDOWN, c.SDL_KEYUP => {
                                const maybe_key = Key.fromSdlKey(event.key.keysym.sym);
                                if (maybe_key) |key| {
                                    self.keyboard[@intFromEnum(key)] = event.key.type == c.SDL_KEYDOWN;
                                    break :loop;
                                }
                            },
                            else => {},
                        }
                    }
                },
                0x15 => self.regs.dt = v[x],
                0x18 => self.regs.st = v[x],
                0x1E => self.regs.i +%= v[x],
                0x29 => self.regs.i = character_size *% v[x],
                0x33 => {
                    const units = v[x] % 10;
                    const tens = (v[x] / 10) % 10;
                    const hundreds = v[x] / 100;

                    self.memory[self.regs.i + 0] = hundreds;
                    self.memory[self.regs.i + 1] = tens;
                    self.memory[self.regs.i + 2] = units;
                },
                0x55 => for (0..x + 1) |index| {
                    const address = self.regs.i + index;
                    self.memory[address] = self.regs.v[index];
                },
                0x65 => for (0..x + 1) |index| {
                    const address = self.regs.i + index;
                    self.regs.v[index] = self.memory[address];
                },
                else => invalidInstruction(opcode),
            },
            else => invalidInstruction(opcode),
        },
    }
}

fn push(self: *@This(), value: u16) void {
    self.stack[self.regs.sp] = value;
    self.regs.sp +%= 1;
}

fn pop(self: *@This()) u16 {
    self.regs.sp -%= 1;
    return self.stack[self.regs.sp];
}

fn readNextOpcode(self: *@This()) Opcode {
    const pc = self.regs.pc;
    const bytes = self.memory[pc .. pc + @sizeOf(Opcode)];
    const opcode = std.mem.readInt(Opcode, @ptrCast(bytes), .big);
    self.regs.pc +%= 2;

    return opcode;
}

fn invalidInstruction(opcode: Opcode) void {
    std.log.warn("invalid instruction: 0x{X:0>4}", .{opcode});
}

const character_size = 5;
const default_character_set = [_]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};
