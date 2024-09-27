const std = @import("std");
const c = @import("c.zig");
const Sdl = @import("Sdl.zig");

const color_on = 0xFF1CA5FF;
const color_off = 0xFF0055CC;

pub const Pixel = u32;
pub const PixelBuffer = [screen_width * screen_height]Pixel;

pub const screen_width = 64;
pub const screen_height = 32;

const execution_frequency = 1.0 / 600.0;
const timer_frequency = 1.0 / 60.0;
const memory_size = 4096;
const display_memory_size = screen_width * screen_height / 8;
const stack_size = 16;
const register_count = 16;

const program_address = 0x200;
const font_address = 0x50;
const flags = 0xF;

regs: Registers,
i: u16,
pc: u16,
dt: u8,
st: u8,
sp: u8,
stack: Stack,
memory: Memory,
display_memory: DisplayMemory,
rng: std.Random.DefaultPrng,
keyboard: Keyboard,
key_event: packed struct {
    register: u8,
    waiting: bool,
},

const Registers = [register_count]u8;
const Stack = [stack_size]u16;
const Memory = [memory_size]u8;
const DisplayMemory = [display_memory_size]u8;
const Opcode = u16;
const Keyboard = [Key.count]bool;

pub fn init(rom: []const u8) !@This() {
    if (rom.len > memory_size - program_address)
        return error.ProgramTooLarge;

    var self = std.mem.zeroes(@This());
    self.pc = program_address;
    self.rng = std.Random.DefaultPrng.init(0);

    @memcpy(self.memory[font_address .. font_address + font.len], &font);
    @memcpy(self.memory[program_address .. program_address + rom.len], rom);

    return self;
}

pub fn renderToBuffer(self: *const @This(), pixels: []Pixel) void {
    for (0..pixels.len) |index| {
        const bit: u3 = @intCast(index % 8);
        const byte = index / 8;
        const mask = @as(u8, 1) << (7 - bit);

        if (self.display_memory[byte] & mask != 0) {
            pixels[index] = color_on;
        } else {
            pixels[index] = color_off;
        }
    }
}

pub fn executeIns(self: *@This()) void {
    const opcode = self.readNextOpcode();

    const v = &self.regs;
    const nnn = opcode & 0xFFF;
    const n = opcode & 0xF;
    const x: u8 = @intCast((opcode >> 8) & 0xF);
    const y: u8 = @intCast((opcode >> 4) & 0xF);
    const kk: u8 = @intCast(opcode & 0xFF);

    switch (opcode) {
        0x00E0 => @memset(&self.display_memory, 0),
        0x00EE => self.pc = self.pop(),
        else => switch (opcode & 0xF000) {
            0x0000 => {},
            0x1000 => self.pc = nnn,
            0x2000 => {
                self.push(self.pc);
                self.pc = nnn;
            },
            0x3000 => if (v[x] == kk) {
                self.pc +%= 2;
            },
            0x4000 => if (v[x] != kk) {
                self.pc +%= 2;
            },
            0x5000 => switch (opcode & 0xF) {
                0x0 => if (v[x] == v[y]) {
                    self.pc +%= 2;
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
                    const sum = @as(u16, v[x]) + @as(u16, v[y]);
                    v[x] = @truncate(sum);
                    v[flags] = @intFromBool(sum > 0xFF);
                },
                0x5 => {
                    const flag = v[x] >= v[y];
                    v[x] -%= v[y];
                    v[flags] = @intFromBool(flag);
                },
                0x6 => {
                    const flag = v[x] & 0x1 != 0;
                    v[x] >>= 1;
                    v[flags] = @intFromBool(flag);
                },
                0x7 => {
                    const flag = v[y] >= v[x];
                    v[x] = v[y] -% v[x];
                    v[flags] = @intFromBool(flag);
                },
                0xE => {
                    const flag = v[x] & 0x8 != 0;
                    v[x] <<= 1;
                    v[flags] = @intFromBool(flag);
                },
                else => invalidInstruction(opcode),
            },
            0x9000 => switch (opcode & 0xF) {
                0x0 => if (v[x] != v[y]) {
                    self.pc +%= 2;
                },
                else => invalidInstruction(opcode),
            },
            0xA000 => self.i = nnn,
            0xB000 => self.pc = nnn +% v[x],
            0xC000 => v[x] = self.rng.random().int(u8) & kk,
            0xD000 => {
                const address = self.i;
                const sprite = self.memory[address .. address + n];

                var collision: u8 = 0;

                for (v[y]..v[y] + n, 0..) |row, index| {
                    // Handles cases when x is not at a byte boundary.
                    const sprite_row: u16 = sprite[index];
                    const sprite_part1: u8 = @truncate(sprite_row >> @intCast(v[x] % 8));
                    const sprite_part2: u8 = @truncate(sprite_row << @intCast(8 - (v[x] % 8)));

                    const row_offset = (row % screen_height) * screen_width;
                    const disp_address1 = (v[x] % screen_width) + row_offset;
                    const disp_address2 = ((v[x] + 7) % screen_width) + row_offset;

                    self.display_memory[disp_address1 / 8] ^= sprite_part1;
                    self.display_memory[disp_address2 / 8] ^= sprite_part2;

                    collision |= (self.display_memory[disp_address1 / 8] ^ sprite_part1) & sprite_part1;
                    collision |= (self.display_memory[disp_address2 / 8] ^ sprite_part2) & sprite_part2;
                }

                v[flags] = @intFromBool(collision != 0);
            },
            0xE000 => switch (opcode & 0xFF) {
                0x9E => if (self.keyboard[v[x]]) {
                    self.pc +%= 2;
                },
                0xA1 => if (!self.keyboard[v[x]]) {
                    self.pc +%= 2;
                },
                else => invalidInstruction(opcode),
            },
            0xF000 => switch (opcode & 0xFF) {
                0x07 => v[x] = self.dt,
                0x0A => self.key_event = .{
                    .register = x,
                    .waiting = true,
                },
                0x15 => self.dt = v[x],
                0x18 => self.st = v[x],
                0x1E => self.i +%= v[x],
                0x29 => self.i = character_size *% v[x],
                0x33 => {
                    const units = v[x] % 10;
                    const tens = (v[x] / 10) % 10;
                    const hundreds = v[x] / 100;

                    self.memory[self.i + 0] = hundreds;
                    self.memory[self.i + 1] = tens;
                    self.memory[self.i + 2] = units;
                },
                0x55 => for (0..x + 1) |index| {
                    const address = self.i + index;
                    self.memory[address] = self.regs[index];
                },
                0x65 => for (0..x + 1) |index| {
                    const address = self.i + index;
                    self.regs[index] = self.memory[address];
                },
                else => invalidInstruction(opcode),
            },
            else => invalidInstruction(opcode),
        },
    }
}

fn push(self: *@This(), value: u16) void {
    self.sp +%= 1;
    self.sp %= stack_size;
    self.stack[self.sp] = value;
}

fn pop(self: *@This()) u16 {
    const value = self.stack[self.sp];
    self.sp -%= 1;
    self.sp %= stack_size;
    return value;
}

fn readNextOpcode(self: *@This()) Opcode {
    const pc = self.pc;
    const bytes = self.memory[pc .. pc + @sizeOf(Opcode)];
    const opcode = std.mem.readInt(Opcode, @ptrCast(bytes), .big);
    self.pc +%= 2;

    return opcode;
}

fn invalidInstruction(opcode: Opcode) void {
    std.log.warn("invalid instruction: 0x{X:0>4}", .{opcode});
}

const character_size = 5;
const font = [_]u8{
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

pub const Key = enum {
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
};
