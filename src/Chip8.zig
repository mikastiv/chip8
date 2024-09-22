const std = @import("std");
const c = @import("c.zig");

pub const screen_width = 64;
pub const screen_height = 32;
pub const execution_frequency = 1.0 / 500.0;
pub const memory_size = 4096;

const program_start_address = 0x200;

regs: Registers,
memory: Memory,
frame: Frame,
rng: std.Random.DefaultPrng,

pub const Memory = [memory_size]u8;
pub const Opcode = u16;

pub const Registers = struct {
    pub const count = 16;
    pub const flags = 0xF;

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

pub const Frame = struct {
    pub const Color = enum { black, white };
    pub const Pixel = u32;
    pub const width = screen_width;
    pub const height = screen_height;
    pub const pitch = width * @sizeOf(Pixel);
    pub const size = width * height * @sizeOf(Pixel);

    pixels: [size]u8,

    pub const init: Frame = .{ .pixels = std.mem.zeroes([size]u8) };

    pub inline fn putPixel(self: *Frame, x: usize, y: usize, color: Color) void {
        const index = (y * pitch) + (x * @sizeOf(Pixel));

        const color_rgb: u8 = switch (color) {
            .black => 0,
            .white => 255,
        };

        self.pixels[index + 0] = color_rgb;
        self.pixels[index + 1] = color_rgb;
        self.pixels[index + 2] = color_rgb;
        self.pixels[index + 3] = @intCast(c.SDL_ALPHA_OPAQUE);
    }

    pub fn clear(self: *Frame) void {
        @memset(&self.pixels, 0);
    }
};

pub fn init(rom: []const u8) !@This() {
    if (rom.len > memory_size - program_start_address)
        return error.ProgramTooLarge;

    var self: @This() = .{
        .regs = .init,
        .memory = std.mem.zeroes(Memory),
        .frame = .init,
        .rng = std.Random.DefaultPrng.init(0),
    };

    @memcpy(self.memory[0..default_character_set.len], &default_character_set);
    @memcpy(self.memory[program_start_address .. program_start_address + rom.len], rom);

    return self;
}

pub fn stepFrame(self: *@This()) void {
    var done = false;
    while (!done) {
        const opcode = self.readNextOpcode();
        const v = &self.regs.v;

        const nnn = opcode & 0xFFF;
        const n = opcode & 0xF;
        _ = n; // autofix
        const x = (opcode >> 8) & 0xF;
        const y = (opcode >> 4) & 0xF;
        const kk: u8 = @intCast(opcode & 0xFF);
        switch (opcode) {
            0x00E0 => self.frame.clear(),
            0x00EE => {}, // RET
            else => switch (opcode & 0xF000) {
                0x0000 => {},
                0x1000 => self.regs.pc = nnn,
                0x2000 => {}, // Call
                0x3000 => if (v[x] == kk) {
                    self.regs.pc +%= 2;
                },
                0x4000 => if (v[y] != kk) {
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
                        v[Registers.flags] = @intFromBool(v[x] > v[y]);
                        v[x] -%= v[y];
                    },
                    0x6 => {
                        v[Registers.flags] = @intFromBool(v[x] & 0x1 != 0);
                        v[x] >>= 1;
                    },
                    0x7 => {
                        v[Registers.flags] = @intFromBool(v[y] > v[x]);
                        v[x] = v[y] - v[x];
                    },
                    0xE => {
                        v[Registers.flags] = @intFromBool(v[x] & 0x8 != 0);
                        v[x] <<= 1;
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
                0xD000 => done = true, // draw
                0xE000 => switch (opcode & 0xFF) {
                    0x9E => {},
                    0xA1 => {},
                    else => invalidInstruction(opcode),
                },
                0xF000 => switch (opcode & 0xFF) {
                    0x07 => v[x] = self.regs.dt,
                    0xA0 => {},
                    0x15 => self.regs.dt = v[x],
                    0x18 => self.regs.st = v[x],
                    0x1E => self.regs.i +%= v[x],
                    0x29 => self.regs.i = character_size *% v[x],
                    0x33 => {
                        const units = v[x] % 10;
                        const tens = v[x] / 10 % 10;
                        const hundreds = v[x] / 100;

                        self.memory[self.regs.i + 0] = hundreds;
                        self.memory[self.regs.i + 1] = tens;
                        self.memory[self.regs.i + 2] = units;
                    },
                    0x55 => inline for (0..Registers.count) |index| {
                        const address = self.regs.i + index;
                        self.memory[address] = self.regs.v[index];
                    },
                    0x65 => inline for (0..Registers.count) |index| {
                        const address = self.regs.i + index;
                        self.regs.v[index] = self.memory[address];
                    },
                    else => invalidInstruction(opcode),
                },
                else => invalidInstruction(opcode),
            },
        }
    }
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
