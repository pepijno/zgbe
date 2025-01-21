const CPU = @This();

const std = @import("std");
const Bus = @import("Bus.zig");

af: packed union {
    bit8: packed struct(u16) {
        _padding: u4,
        carry_flag: bool,
        half_carry_flag: bool,
        subtraction_flag: bool,
        zero_flag: bool,
        a: u8,
    },
    bit16: u16,
},
bc: packed union {
    bit8: packed struct(u16) {
        c: u8,
        b: u8,
    },
    bit16: u16,
},
de: packed union {
    bit8: packed struct(u16) {
        e: u8,
        d: u8,
    },
    bit16: u16,
},
hl: packed union {
    bit8: packed struct(u16) {
        l: u8,
        h: u8,
    },
    bit16: u16,
},
stack_pointer: u16,
program_counter: u16,
halted: bool = false,
running: bool = false,

pub const Register = enum {
    none,
    a,
    b,
    c,
    d,
    e,
    h,
    l,
    bc,
    de,
    hl,
    sp,
    address,

    pub fn isRegister16(self: @This()) bool {
        return self == .bc or self == .de or self == .hl or self == .sp;
    }
};

pub fn getRegister8(cpu: *const CPU, register: Register) u8 {
    return switch (register) {
        .a => cpu.af.bit8.a,
        .b => cpu.bc.bit8.b,
        .c => cpu.bc.bit8.c,
        .d => cpu.de.bit8.d,
        .e => cpu.de.bit8.e,
        .h => cpu.hl.bit8.h,
        .l => cpu.hl.bit8.l,
        else => 0,
    };
}

pub fn setRegister8(cpu: *CPU, value: u8, register: Register) void {
    switch (register) {
        .a => cpu.af.bit8.a = value,
        .b => cpu.bc.bit8.b = value,
        .c => cpu.bc.bit8.c = value,
        .d => cpu.de.bit8.d = value,
        .e => cpu.de.bit8.e = value,
        .h => cpu.hl.bit8.h = value,
        .l => cpu.hl.bit8.l = value,
        else => {},
    }
}

pub fn getRegister16(cpu: *const CPU, register: Register) u16 {
    return switch (register) {
        .bc => cpu.bc.bit16,
        .de => cpu.de.bit16,
        .hl => cpu.hl.bit16,
        .sp => cpu.stack_pointer,
        else => 0,
    };
}

pub fn setRegister16(cpu: *CPU, value: u16, register: Register) void {
    switch (register) {
        .bc => cpu.bc.bit16 = value,
        .de => cpu.de.bit16 = value,
        .hl => cpu.hl.bit16 = value,
        .sp => cpu.stack_pointer = value,
        else => {},
    }
}

pub fn initBeforeBoot() CPU {
    return .{
        .af = .{ .bit16 = 0 },
        .bc = .{ .bit16 = 0 },
        .de = .{ .bit16 = 0 },
        .hl = .{ .bit16 = 0 },
        .stack_pointer = 0,
        .program_counter = 0,
    };
}

pub fn initAfterBoot() CPU {
    return .{
        .af = .{ .bit16 = 0x01B0 },
        .bc = .{ .bit16 = 0x0013 },
        .de = .{ .bit16 = 0x00D8 },
        .hl = .{ .bit16 = 0x014D },
        .stack_pointer = 0xFFFE,
        .program_counter = 0x100,
    };
}

pub fn readU8(cpu: *CPU, bus: *const Bus) u8 {
    const value = bus.read8(cpu.program_counter);
    cpu.program_counter += 1;
    return value;
}

pub fn readU16(cpu: *CPU, bus: *const Bus) u16 {
    const value1 = cpu.readU8(bus);
    const value2 = cpu.readU8(bus);
    return @as(u16, value1) | (@as(u16, value2) << 8);
}

pub fn writeToStack16(cpu: *CPU, bus: *Bus, value: u16) void {
    cpu.stack_pointer -= 2;
    bus.write16(cpu.stack_pointer, value);
    // std.debug.print("Stack write 0x{X:0>4}\n", .{value});
}

pub fn readFromStack16(cpu: *CPU, bus: *const Bus) u16 {
    const value = bus.read16(cpu.stack_pointer);
    cpu.stack_pointer += 2;
    // std.debug.print("Stack read 0x{X:0>4}\n", .{value});
    return value;
}

var last_program_counter: u16 = 0;

fn flagToChar(flag: bool, flag_char: u8) u8 {
    return if (flag) flag_char else '-';
}

pub fn printState(cpu: *const CPU, bus: *const Bus, writer: anytype) !void {
    var flags: u8 = 0;
    if (cpu.af.bit8.zero_flag) {
        flags |= (1 << 7);
    }
    if (cpu.af.bit8.subtraction_flag) {
        flags |= (1 << 6);
    }
    if (cpu.af.bit8.half_carry_flag) {
        flags |= (1 << 5);
    }
    if (cpu.af.bit8.carry_flag) {
        flags |= (1 << 4);
    }
    try writer.print("A:{X:0>2} F:{X:0>2} B:{X:0>2} C:{X:0>2} D:{X:0>2} E:{X:0>2} H:{X:0>2} L:{X:0>2} SP:{X:0>4} PC:{X:0>4} PCMEM:{X:0>2},{X:0>2},{X:0>2},{X:0>2}\n", .{
        cpu.af.bit8.a,
        flags,
        cpu.bc.bit8.b,
        cpu.bc.bit8.c,
        cpu.de.bit8.d,
        cpu.de.bit8.e,
        cpu.hl.bit8.h,
        cpu.hl.bit8.l,
        cpu.stack_pointer,
        cpu.program_counter,
        bus.read8(cpu.program_counter),
        bus.read8(cpu.program_counter + 1),
        bus.read8(cpu.program_counter + 2),
        bus.read8(cpu.program_counter + 3),
    });
}

pub fn tick(cpu: *CPU, bus: *Bus) void {
    if (cpu.halted) {
        bus.tick(1);
        return;
    }

    const opcode = cpu.readU8(bus);
    bus.tick(1);
    // std.debug.print("Opcode 0x{X:0>2}\n", .{opcode});

    cpu.runInstruction(bus, opcode);
}

fn incRegister(cpu: *CPU, value: *u8) void {
    cpu.af.bit8.half_carry_flag = (value.* & 0xF) == 0xF;

    value.* +%= 1;

    cpu.af.bit8.zero_flag = value.* == 0;
    cpu.af.bit8.subtraction_flag = false;
}

fn decRegister(cpu: *CPU, value: *u8) void {
    cpu.af.bit8.half_carry_flag = (value.* & 0xF) == 0;

    value.* -%= 1;

    cpu.af.bit8.zero_flag = value.* == 0;
    cpu.af.bit8.subtraction_flag = true;
}

fn add2(cpu: *CPU, dest: *u16, value: u16) void {
    const result = @as(u32, dest.*) + @as(u32, value);

    cpu.af.bit8.carry_flag = (result & 0xFFFF0000) != 0;
    cpu.af.bit8.half_carry_flag = ((dest.* & 0xFFF) + (value & 0xFFF)) > 0xFFF;

    dest.* = @truncate(result & 0xFFFF);

    cpu.af.bit8.subtraction_flag = false;
}

fn adda(cpu: *CPU, value: u8) void {
    const result = @as(u16, cpu.af.bit8.a) + @as(u16, value);

    cpu.af.bit8.carry_flag = (result & 0xFF00) != 0;
    cpu.af.bit8.half_carry_flag = ((cpu.af.bit8.a & 0xF) + (value & 0xF)) > 0xF;

    cpu.af.bit8.a = @truncate(result & 0xFF);

    cpu.af.bit8.zero_flag = cpu.af.bit8.a == 0;
    cpu.af.bit8.subtraction_flag = false;
}

fn adca(cpu: *CPU, value: u8) void {
    const carry_bit: u8 = if (cpu.af.bit8.carry_flag) 1 else 0;
    const result = @as(u16, cpu.af.bit8.a) + @as(u16, value) + @as(u16, carry_bit);

    cpu.af.bit8.carry_flag = (result & 0xFF00) != 0;
    cpu.af.bit8.half_carry_flag = ((cpu.af.bit8.a & 0xF) + (value & 0xF) + carry_bit) > 0xF;

    cpu.af.bit8.a = @truncate(result & 0xFF);

    cpu.af.bit8.zero_flag = cpu.af.bit8.a == 0;
    cpu.af.bit8.subtraction_flag = false;
}

fn suba(cpu: *CPU, value: u8) void {
    cpu.af.bit8.carry_flag = value > cpu.af.bit8.a;

    cpu.af.bit8.half_carry_flag = (value & 0xF) > (cpu.af.bit8.a & 0xF);

    cpu.af.bit8.a -%= value;

    cpu.af.bit8.zero_flag = cpu.af.bit8.a == 0;
    cpu.af.bit8.subtraction_flag = true;
}

fn sbca(cpu: *CPU, value: u8) void {
    const carry_bit: u8 = if (cpu.af.bit8.carry_flag) 1 else 0;
    const result = cpu.af.bit8.a -% value -% carry_bit;

    cpu.af.bit8.carry_flag = @as(u16, value) + @as(u16, carry_bit) > @as(u16, cpu.af.bit8.a);
    cpu.af.bit8.half_carry_flag = ((@as(u16, value) & 0xF) + (@as(u16, carry_bit) & 0xF)) > (cpu.af.bit8.a & 0xF);

    cpu.af.bit8.a = result;

    cpu.af.bit8.zero_flag = cpu.af.bit8.a == 0;
    cpu.af.bit8.subtraction_flag = true;
}

fn anda(cpu: *CPU, value: u8) void {
    cpu.af.bit8.a &= value;

    cpu.af.bit8.zero_flag = cpu.af.bit8.a == 0;
    cpu.af.bit8.subtraction_flag = false;
    cpu.af.bit8.half_carry_flag = true;
    cpu.af.bit8.carry_flag = false;
}

fn xora(cpu: *CPU, value: u8) void {
    cpu.af.bit8.a ^= value;

    cpu.af.bit8.zero_flag = cpu.af.bit8.a == 0;
    cpu.af.bit8.subtraction_flag = false;
    cpu.af.bit8.half_carry_flag = false;
    cpu.af.bit8.carry_flag = false;
}

fn ora(cpu: *CPU, value: u8) void {
    cpu.af.bit8.a |= value;

    cpu.af.bit8.zero_flag = cpu.af.bit8.a == 0;
    cpu.af.bit8.subtraction_flag = false;
    cpu.af.bit8.half_carry_flag = false;
    cpu.af.bit8.carry_flag = false;
}

fn cpa(cpu: *CPU, value: u8) void {
    cpu.af.bit8.zero_flag = cpu.af.bit8.a == value;
    cpu.af.bit8.carry_flag = value > cpu.af.bit8.a;
    cpu.af.bit8.half_carry_flag = (value & 0xF) > (cpu.af.bit8.a & 0xF);
    cpu.af.bit8.subtraction_flag = true;
}

fn runInstruction(cpu: *CPU, bus: *Bus, opcode: u8) void {
    switch (opcode) {
        0x00 => {}, // NOP
        0x01 => {
            cpu.bc.bit16 = cpu.readU16(bus);
            bus.tick(2);
        },
        0x02 => {
            bus.write8(cpu.bc.bit16, cpu.af.bit8.a);
            bus.tick(1);
        },
        0x03 => {
            cpu.bc.bit16 +%= 1;
            bus.tick(1);
        },
        0x04 => {
            cpu.incRegister(&cpu.bc.bit8.b);
        },
        0x05 => {
            cpu.decRegister(&cpu.bc.bit8.b);
        },
        0x06 => {
            cpu.bc.bit8.b = cpu.readU8(bus);
            bus.tick(1);
        },
        0x07 => {
            const carry = (cpu.af.bit8.a & 0x80) >> 7;
            cpu.af.bit8.carry_flag = carry != 0;

            cpu.af.bit8.a = cpu.af.bit8.a << 1;
            cpu.af.bit8.a |= carry;

            cpu.af.bit8.zero_flag = false;
            cpu.af.bit8.subtraction_flag = false;
            cpu.af.bit8.half_carry_flag = false;
        },

        0x08 => {
            const operand = cpu.readU16(bus);
            bus.tick(2);
            bus.write16(operand, cpu.stack_pointer);
            bus.tick(2);
        },
        0x09 => {
            cpu.add2(&cpu.hl.bit16, cpu.bc.bit16);
            bus.tick(1);
        },
        0x0A => {
            cpu.af.bit8.a = bus.read8(cpu.bc.bit16);
            bus.tick(1);
        },
        0x0B => {
            cpu.bc.bit16 -%= 1;
            bus.tick(1);
        },
        0x0C => {
            cpu.incRegister(&cpu.bc.bit8.c);
        },
        0x0D => {
            cpu.decRegister(&cpu.bc.bit8.c);
        },
        0x0E => {
            cpu.bc.bit8.c = cpu.readU8(bus);
            bus.tick(1);
        },
        0x0F => {
            const carry = cpu.af.bit8.a & 0x1;
            cpu.af.bit8.carry_flag = carry != 0;

            cpu.af.bit8.a = cpu.af.bit8.a >> 1;
            if (carry != 0) cpu.af.bit8.a |= 0x80;

            cpu.af.bit8.zero_flag = false;
            cpu.af.bit8.subtraction_flag = false;
            cpu.af.bit8.half_carry_flag = false;
        },

        0x10 => {
            cpu.running = false;
        },
        0x11 => {
            cpu.de.bit16 = cpu.readU16(bus);
            bus.tick(2);
        },
        0x12 => {
            bus.write8(cpu.de.bit16, cpu.af.bit8.a);
            bus.tick(1);
        },
        0x13 => {
            cpu.de.bit16 +%= 1;
            bus.tick(1);
        },
        0x14 => {
            cpu.incRegister(&cpu.de.bit8.d);
        },
        0x15 => {
            cpu.decRegister(&cpu.de.bit8.d);
        },
        0x16 => {
            cpu.de.bit8.d = cpu.readU8(bus);
            bus.tick(1);
        },
        0x17 => {
            const carry: u8 = if (cpu.af.bit8.carry_flag) 1 else 0;
            cpu.af.bit8.carry_flag = (cpu.af.bit8.a & 0x80) != 0;

            cpu.af.bit8.a = cpu.af.bit8.a << 1;
            cpu.af.bit8.a +%= carry;

            cpu.af.bit8.half_carry_flag = false;
            cpu.af.bit8.subtraction_flag = false;
            cpu.af.bit8.zero_flag = false;
        },

        0x18 => {
            const value: i8 = @bitCast(cpu.readU8(bus));
            bus.tick(1);
            if (value < 0) {
                cpu.program_counter -%= @abs(value);
            } else {
                cpu.program_counter +%= @intCast(value);
            }
            bus.tick(1);
        },
        0x19 => {
            cpu.add2(&cpu.hl.bit16, cpu.de.bit16);
            bus.tick(1);
        },
        0x1A => {
            cpu.af.bit8.a = bus.read8(cpu.de.bit16);
            bus.tick(1);
        },
        0x1B => {
            cpu.de.bit16 -%= 1;
            bus.tick(1);
        },
        0x1C => {
            cpu.incRegister(&cpu.de.bit8.e);
        },
        0x1D => {
            cpu.decRegister(&cpu.de.bit8.e);
        },
        0x1E => {
            cpu.de.bit8.e = cpu.readU8(bus);
            bus.tick(1);
        },
        0x1F => {
            const carry: u8 = if (cpu.af.bit8.carry_flag) 1 else 0;

            cpu.af.bit8.carry_flag = (cpu.af.bit8.a & 0x01) != 0;
            cpu.af.bit8.a = cpu.af.bit8.a >> 1;
            cpu.af.bit8.a +%= (carry << 7);

            cpu.af.bit8.half_carry_flag = false;
            cpu.af.bit8.subtraction_flag = false;
            cpu.af.bit8.zero_flag = false;
        },

        0x20 => {
            const value: i8 = @bitCast(cpu.readU8(bus));
            bus.tick(1);
            if (!cpu.af.bit8.zero_flag) {
                if (value < 0) {
                    cpu.program_counter -%= @abs(value);
                } else {
                    cpu.program_counter +%= @intCast(value);
                }
                bus.tick(1);
            }
        },
        0x21 => {
            cpu.hl.bit16 = cpu.readU16(bus);
            bus.tick(2);
        },
        0x22 => {
            bus.write8(cpu.hl.bit16, cpu.af.bit8.a);
            cpu.hl.bit16 +%= 1;
            bus.tick(1);
        },
        0x23 => {
            cpu.hl.bit16 +%= 1;
            bus.tick(1);
        },
        0x24 => {
            cpu.incRegister(&cpu.hl.bit8.h);
        },
        0x25 => {
            cpu.decRegister(&cpu.hl.bit8.h);
        },
        0x26 => {
            cpu.hl.bit8.h = cpu.readU8(bus);
            bus.tick(1);
        },
        0x27 => {
            var offset: u8 = 0;
            var carry = false;

            if ((!cpu.af.bit8.subtraction_flag and (cpu.af.bit8.a & 0xF) > 0x9) or cpu.af.bit8.half_carry_flag) {
                offset |= 0x6;
            }
            if ((!cpu.af.bit8.subtraction_flag and cpu.af.bit8.a > 0x99) or cpu.af.bit8.carry_flag) {
                offset |= 0x60;
                carry = true;
            }

            if (cpu.af.bit8.subtraction_flag) {
                cpu.af.bit8.a -%= offset;
            } else {
                cpu.af.bit8.a +%= offset;
            }

            cpu.af.bit8.carry_flag = carry;
            cpu.af.bit8.half_carry_flag = false;
            cpu.af.bit8.zero_flag = cpu.af.bit8.a == 0;
        },

        0x28 => {
            const value: i8 = @bitCast(cpu.readU8(bus));
            bus.tick(1);
            if (cpu.af.bit8.zero_flag) {
                if (value < 0) {
                    cpu.program_counter -%= @abs(value);
                } else {
                    cpu.program_counter +%= @intCast(value);
                }
                bus.tick(1);
            }
        },
        0x29 => {
            cpu.add2(&cpu.hl.bit16, cpu.hl.bit16);
            bus.tick(1);
        },
        0x2A => {
            cpu.af.bit8.a = bus.read8(cpu.hl.bit16);
            cpu.hl.bit16 +%= 1;
            bus.tick(1);
        },
        0x2B => {
            cpu.hl.bit16 -%= 1;
            bus.tick(1);
        },
        0x2C => {
            cpu.incRegister(&cpu.hl.bit8.l);
        },
        0x2D => {
            cpu.decRegister(&cpu.hl.bit8.l);
        },
        0x2E => {
            cpu.hl.bit8.l = cpu.readU8(bus);
            bus.tick(1);
        },
        0x2F => {
            cpu.af.bit8.a = ~cpu.af.bit8.a;
            cpu.af.bit8.half_carry_flag = true;
            cpu.af.bit8.subtraction_flag = true;
        },

        0x30 => {
            const value: i8 = @bitCast(cpu.readU8(bus));
            bus.tick(1);
            if (!cpu.af.bit8.carry_flag) {
                if (value < 0) {
                    cpu.program_counter -%= @abs(value);
                } else {
                    cpu.program_counter +%= @intCast(value);
                }
                bus.tick(1);
            }
        },
        0x31 => {
            cpu.stack_pointer = cpu.readU16(bus);
            bus.tick(2);
        },
        0x32 => {
            bus.write8(cpu.hl.bit16, cpu.af.bit8.a);
            cpu.hl.bit16 -%= 1;
            bus.tick(1);
        },
        0x33 => {
            cpu.stack_pointer +%= 1;
            bus.tick(1);
        },
        0x34 => {
            var value = bus.read8(cpu.hl.bit16);
            cpu.incRegister(&value);
            bus.write8(cpu.hl.bit16, value);
            bus.tick(2);
        },
        0x35 => {
            var value = bus.read8(cpu.hl.bit16);
            cpu.decRegister(&value);
            bus.write8(cpu.hl.bit16, value);
            bus.tick(2);
        },
        0x36 => {
            bus.write8(cpu.hl.bit16, cpu.readU8(bus));
            bus.tick(2);
        },
        0x37 => {
            cpu.af.bit8.half_carry_flag = false;
            cpu.af.bit8.subtraction_flag = false;
            cpu.af.bit8.carry_flag = true;
        },

        0x38 => {
            const value: i8 = @bitCast(cpu.readU8(bus));
            bus.tick(1);
            if (cpu.af.bit8.carry_flag) {
                if (value < 0) {
                    cpu.program_counter -%= @abs(value);
                } else {
                    cpu.program_counter +%= @intCast(value);
                }
                bus.tick(1);
            }
        },
        0x39 => {
            cpu.add2(&cpu.hl.bit16, cpu.stack_pointer);
            bus.tick(1);
        },
        0x3A => {
            cpu.af.bit8.a = bus.read8(cpu.hl.bit16);
            cpu.hl.bit16 -%= 1;
            bus.tick(1);
        },
        0x3B => {
            cpu.stack_pointer -%= 1;
            bus.tick(1);
        },
        0x3C => {
            cpu.incRegister(&cpu.af.bit8.a);
        },
        0x3D => {
            cpu.decRegister(&cpu.af.bit8.a);
        },
        0x3E => {
            cpu.af.bit8.a = cpu.readU8(bus);
            bus.tick(1);
        },
        0x3F => {
            cpu.af.bit8.carry_flag = !cpu.af.bit8.carry_flag;
            cpu.af.bit8.half_carry_flag = false;
            cpu.af.bit8.subtraction_flag = false;
        },

        0x40 => {
            cpu.bc.bit8.b = cpu.bc.bit8.b;
        },
        0x41 => {
            cpu.bc.bit8.b = cpu.bc.bit8.c;
        },
        0x42 => {
            cpu.bc.bit8.b = cpu.de.bit8.d;
        },
        0x43 => {
            cpu.bc.bit8.b = cpu.de.bit8.e;
        },
        0x44 => {
            cpu.bc.bit8.b = cpu.hl.bit8.h;
        },
        0x45 => {
            cpu.bc.bit8.b = cpu.hl.bit8.l;
        },
        0x46 => {
            cpu.bc.bit8.b = bus.read8(cpu.hl.bit16);
            bus.tick(1);
        },
        0x47 => {
            cpu.bc.bit8.b = cpu.af.bit8.a;
        },

        0x48 => {
            cpu.bc.bit8.c = cpu.bc.bit8.b;
        },
        0x49 => {
            cpu.bc.bit8.c = cpu.bc.bit8.c;
        },
        0x4A => {
            cpu.bc.bit8.c = cpu.de.bit8.d;
        },
        0x4B => {
            cpu.bc.bit8.c = cpu.de.bit8.e;
        },
        0x4C => {
            cpu.bc.bit8.c = cpu.hl.bit8.h;
        },
        0x4D => {
            cpu.bc.bit8.c = cpu.hl.bit8.l;
        },
        0x4E => {
            cpu.bc.bit8.c = bus.read8(cpu.hl.bit16);
            bus.tick(1);
        },
        0x4F => {
            cpu.bc.bit8.c = cpu.af.bit8.a;
        },

        0x50 => {
            cpu.de.bit8.d = cpu.bc.bit8.b;
        },
        0x51 => {
            cpu.de.bit8.d = cpu.bc.bit8.c;
        },
        0x52 => {
            cpu.de.bit8.d = cpu.de.bit8.d;
        },
        0x53 => {
            cpu.de.bit8.d = cpu.de.bit8.e;
        },
        0x54 => {
            cpu.de.bit8.d = cpu.hl.bit8.h;
        },
        0x55 => {
            cpu.de.bit8.d = cpu.hl.bit8.l;
        },
        0x56 => {
            cpu.de.bit8.d = bus.read8(cpu.hl.bit16);
            bus.tick(1);
        },
        0x57 => {
            cpu.de.bit8.d = cpu.af.bit8.a;
        },

        0x58 => {
            cpu.de.bit8.e = cpu.bc.bit8.b;
        },
        0x59 => {
            cpu.de.bit8.e = cpu.bc.bit8.c;
        },
        0x5A => {
            cpu.de.bit8.e = cpu.de.bit8.d;
        },
        0x5B => {
            cpu.de.bit8.e = cpu.de.bit8.e;
        },
        0x5C => {
            cpu.de.bit8.e = cpu.hl.bit8.h;
        },
        0x5D => {
            cpu.de.bit8.e = cpu.hl.bit8.l;
        },
        0x5E => {
            cpu.de.bit8.e = bus.read8(cpu.hl.bit16);
            bus.tick(1);
        },
        0x5F => {
            cpu.de.bit8.e = cpu.af.bit8.a;
        },

        0x60 => {
            cpu.hl.bit8.h = cpu.bc.bit8.b;
        },
        0x61 => {
            cpu.hl.bit8.h = cpu.bc.bit8.c;
        },
        0x62 => {
            cpu.hl.bit8.h = cpu.de.bit8.d;
        },
        0x63 => {
            cpu.hl.bit8.h = cpu.de.bit8.e;
        },
        0x64 => {
            cpu.hl.bit8.h = cpu.hl.bit8.h;
        },
        0x65 => {
            cpu.hl.bit8.h = cpu.hl.bit8.l;
        },
        0x66 => {
            cpu.hl.bit8.h = bus.read8(cpu.hl.bit16);
            bus.tick(1);
        },
        0x67 => {
            cpu.hl.bit8.h = cpu.af.bit8.a;
        },

        0x68 => {
            cpu.hl.bit8.l = cpu.bc.bit8.b;
        },
        0x69 => {
            cpu.hl.bit8.l = cpu.bc.bit8.c;
        },
        0x6A => {
            cpu.hl.bit8.l = cpu.de.bit8.d;
        },
        0x6B => {
            cpu.hl.bit8.l = cpu.de.bit8.e;
        },
        0x6C => {
            cpu.hl.bit8.l = cpu.hl.bit8.h;
        },
        0x6D => {
            cpu.hl.bit8.l = cpu.hl.bit8.l;
        },
        0x6E => {
            cpu.hl.bit8.l = bus.read8(cpu.hl.bit16);
            bus.tick(1);
        },
        0x6F => {
            cpu.hl.bit8.l = cpu.af.bit8.a;
        },

        0x70 => {
            bus.write8(cpu.hl.bit16, cpu.bc.bit8.b);
            bus.tick(1);
        },
        0x71 => {
            bus.write8(cpu.hl.bit16, cpu.bc.bit8.c);
            bus.tick(1);
        },
        0x72 => {
            bus.write8(cpu.hl.bit16, cpu.de.bit8.d);
            bus.tick(1);
        },
        0x73 => {
            bus.write8(cpu.hl.bit16, cpu.de.bit8.e);
            bus.tick(1);
        },
        0x74 => {
            bus.write8(cpu.hl.bit16, cpu.hl.bit8.h);
            bus.tick(1);
        },
        0x75 => {
            bus.write8(cpu.hl.bit16, cpu.hl.bit8.l);
            bus.tick(1);
        },
        0x76 => {
            cpu.halted = true;
        },
        0x77 => {
            bus.write8(cpu.hl.bit16, cpu.af.bit8.a);
            bus.tick(1);
        },

        0x78 => {
            cpu.af.bit8.a = cpu.bc.bit8.b;
        },
        0x79 => {
            cpu.af.bit8.a = cpu.bc.bit8.c;
        },
        0x7A => {
            cpu.af.bit8.a = cpu.de.bit8.d;
        },
        0x7B => {
            cpu.af.bit8.a = cpu.de.bit8.e;
        },
        0x7C => {
            cpu.af.bit8.a = cpu.hl.bit8.h;
        },
        0x7D => {
            cpu.af.bit8.a = cpu.hl.bit8.l;
        },
        0x7E => {
            cpu.af.bit8.a = bus.read8(cpu.hl.bit16);
            bus.tick(1);
        },
        0x7F => {
            cpu.af.bit8.a = cpu.af.bit8.a;
        },

        0x80 => {
            cpu.adda(cpu.bc.bit8.b);
        },
        0x81 => {
            cpu.adda(cpu.bc.bit8.c);
        },
        0x82 => {
            cpu.adda(cpu.de.bit8.d);
        },
        0x83 => {
            cpu.adda(cpu.de.bit8.e);
        },
        0x84 => {
            cpu.adda(cpu.hl.bit8.h);
        },
        0x85 => {
            cpu.adda(cpu.hl.bit8.l);
        },
        0x86 => {
            cpu.adda(bus.read8(cpu.hl.bit16));
            bus.tick(1);
        },
        0x87 => {
            cpu.adda(cpu.af.bit8.a);
        },

        0x88 => {
            cpu.adca(cpu.bc.bit8.b);
        },
        0x89 => {
            cpu.adca(cpu.bc.bit8.c);
        },
        0x8A => {
            cpu.adca(cpu.de.bit8.d);
        },
        0x8B => {
            cpu.adca(cpu.de.bit8.e);
        },
        0x8C => {
            cpu.adca(cpu.hl.bit8.h);
        },
        0x8D => {
            cpu.adca(cpu.hl.bit8.l);
        },
        0x8E => {
            cpu.adca(bus.read8(cpu.hl.bit16));
            bus.tick(1);
        },
        0x8F => {
            cpu.adca(cpu.af.bit8.a);
        },

        0x90 => {
            cpu.suba(cpu.bc.bit8.b);
        },
        0x91 => {
            cpu.suba(cpu.bc.bit8.c);
        },
        0x92 => {
            cpu.suba(cpu.de.bit8.d);
        },
        0x93 => {
            cpu.suba(cpu.de.bit8.e);
        },
        0x94 => {
            cpu.suba(cpu.hl.bit8.h);
        },
        0x95 => {
            cpu.suba(cpu.hl.bit8.l);
        },
        0x96 => {
            cpu.suba(bus.read8(cpu.hl.bit16));
            bus.tick(1);
        },
        0x97 => {
            cpu.suba(cpu.af.bit8.a);
        },

        0x98 => {
            cpu.sbca(cpu.bc.bit8.b);
        },
        0x99 => {
            cpu.sbca(cpu.bc.bit8.c);
        },
        0x9A => {
            cpu.sbca(cpu.de.bit8.d);
        },
        0x9B => {
            cpu.sbca(cpu.de.bit8.e);
        },
        0x9C => {
            cpu.sbca(cpu.hl.bit8.h);
        },
        0x9D => {
            cpu.sbca(cpu.hl.bit8.l);
        },
        0x9E => {
            cpu.sbca(bus.read8(cpu.hl.bit16));
            bus.tick(1);
        },
        0x9F => {
            cpu.sbca(cpu.af.bit8.a);
        },

        0xA0 => {
            cpu.anda(cpu.bc.bit8.b);
        },
        0xA1 => {
            cpu.anda(cpu.bc.bit8.c);
        },
        0xA2 => {
            cpu.anda(cpu.de.bit8.d);
        },
        0xA3 => {
            cpu.anda(cpu.de.bit8.e);
        },
        0xA4 => {
            cpu.anda(cpu.hl.bit8.h);
        },
        0xA5 => {
            cpu.anda(cpu.hl.bit8.l);
        },
        0xA6 => {
            cpu.anda(bus.read8(cpu.hl.bit16));
            bus.tick(1);
        },
        0xA7 => {
            cpu.anda(cpu.af.bit8.a);
        },

        0xA8 => {
            cpu.xora(cpu.bc.bit8.b);
        },
        0xA9 => {
            cpu.xora(cpu.bc.bit8.c);
        },
        0xAA => {
            cpu.xora(cpu.de.bit8.d);
        },
        0xAB => {
            cpu.xora(cpu.de.bit8.e);
        },
        0xAC => {
            cpu.xora(cpu.hl.bit8.h);
        },
        0xAD => {
            cpu.xora(cpu.hl.bit8.l);
        },
        0xAE => {
            cpu.xora(bus.read8(cpu.hl.bit16));
            bus.tick(1);
        },
        0xAF => {
            cpu.xora(cpu.af.bit8.a);
        },

        0xB0 => {
            cpu.ora(cpu.bc.bit8.b);
        },
        0xB1 => {
            cpu.ora(cpu.bc.bit8.c);
        },
        0xB2 => {
            cpu.ora(cpu.de.bit8.d);
        },
        0xB3 => {
            cpu.ora(cpu.de.bit8.e);
        },
        0xB4 => {
            cpu.ora(cpu.hl.bit8.h);
        },
        0xB5 => {
            cpu.ora(cpu.hl.bit8.l);
        },
        0xB6 => {
            cpu.ora(bus.read8(cpu.hl.bit16));
            bus.tick(1);
        },
        0xB7 => {
            cpu.ora(cpu.af.bit8.a);
        },

        0xB8 => {
            cpu.cpa(cpu.bc.bit8.b);
        },
        0xB9 => {
            cpu.cpa(cpu.bc.bit8.c);
        },
        0xBA => {
            cpu.cpa(cpu.de.bit8.d);
        },
        0xBB => {
            cpu.cpa(cpu.de.bit8.e);
        },
        0xBC => {
            cpu.cpa(cpu.hl.bit8.h);
        },
        0xBD => {
            cpu.cpa(cpu.hl.bit8.l);
        },
        0xBE => {
            cpu.cpa(bus.read8(cpu.hl.bit16));
            bus.tick(1);
        },
        0xBF => {
            cpu.cpa(cpu.af.bit8.a);
        },

        0xC0 => {
            if (!cpu.af.bit8.zero_flag) {
                bus.tick(1);
                cpu.program_counter = cpu.readFromStack16(bus);
                bus.tick(3);
            } else {
                bus.tick(1);
            }
        },
        0xC1 => {
            cpu.bc.bit16 = cpu.readFromStack16(bus);
            bus.tick(2);
        },
        0xC2 => {
            const value = cpu.readU16(bus);
            bus.tick(2);
            if (!cpu.af.bit8.zero_flag) {
                cpu.program_counter = value;
                bus.tick(1);
            }
        },
        0xC3 => {
            cpu.program_counter = cpu.readU16(bus);
            bus.tick(3);
        },
        0xC4 => {
            const operand = cpu.readU16(bus);
            bus.tick(2);
            if (!cpu.af.bit8.zero_flag) {
                cpu.writeToStack16(bus, cpu.program_counter);
                bus.tick(2);
                cpu.program_counter = operand;
                bus.tick(1);
            }
        },
        0xC5 => {
            cpu.writeToStack16(bus, cpu.bc.bit16);
            bus.tick(3);
        },
        0xC6 => {
            cpu.adda(cpu.readU8(bus));
            bus.tick(1);
        },
        0xC7 => {
            cpu.writeToStack16(bus, cpu.program_counter);
            bus.tick(3);
            cpu.program_counter = 0x0000;
        },

        0xC8 => {
            if (cpu.af.bit8.zero_flag) {
                bus.tick(1);
                cpu.program_counter = cpu.readFromStack16(bus);
                bus.tick(3);
            } else {
                bus.tick(1);
            }
        },
        0xC9 => {
            cpu.program_counter = cpu.readFromStack16(bus);
            bus.tick(3);
        },
        0xCA => {
            const operand = cpu.readU16(bus);
            bus.tick(2);
            if (cpu.af.bit8.zero_flag) {
                cpu.program_counter = operand;
                bus.tick(1);
            }
        },
        0xCB => {
            const prefix = cpu.readU8(bus);
            bus.tick(1);
            const instruction = prefixInstructions[prefix];
            instruction(cpu, bus);
        },
        0xCC => {
            const operand = cpu.readU16(bus);
            bus.tick(2);
            if (cpu.af.bit8.zero_flag) {
                bus.tick(1);
                cpu.writeToStack16(bus, cpu.program_counter);
                bus.tick(2);
                cpu.program_counter = operand;
            }
        },
        0xCD => {
            const operand = cpu.readU16(bus);
            bus.tick(2);
            cpu.writeToStack16(bus, cpu.program_counter);
            bus.tick(2);
            cpu.program_counter = operand;
            bus.tick(1);
        },
        0xCE => {
            cpu.adca(cpu.readU8(bus));
            bus.tick(1);
        },
        0xCF => {
            cpu.writeToStack16(bus, cpu.program_counter);
            bus.tick(2);
            cpu.program_counter = 0x0008;
            bus.tick(1);
        },

        0xD0 => {
            if (!cpu.af.bit8.carry_flag) {
                bus.tick(1);
                cpu.program_counter = cpu.readFromStack16(bus);
                bus.tick(3);
            } else {
                bus.tick(1);
            }
        },
        0xD1 => {
            cpu.de.bit16 = cpu.readFromStack16(bus);
            bus.tick(2);
        },
        0xD2 => {
            const operand = cpu.readU16(bus);
            bus.tick(2);
            if (!cpu.af.bit8.carry_flag) {
                cpu.program_counter = operand;
                bus.tick(1);
            }
        },
        0xD4 => {
            const operand = cpu.readU16(bus);
            bus.tick(2);
            if (!cpu.af.bit8.carry_flag) {
                cpu.writeToStack16(bus, cpu.program_counter);
                bus.tick(2);
                cpu.program_counter = operand;
                bus.tick(1);
            }
        },
        0xD5 => {
            cpu.writeToStack16(bus, cpu.de.bit16);
            bus.tick(3);
        },
        0xD6 => {
            cpu.suba(cpu.readU8(bus));
            bus.tick(1);
        },
        0xD7 => {
            cpu.writeToStack16(bus, cpu.program_counter);
            bus.tick(2);
            cpu.program_counter = 0x0010;
            bus.tick(1);
        },

        0xD8 => {
            if (cpu.af.bit8.carry_flag) {
                bus.tick(1);
                cpu.program_counter = cpu.readFromStack16(bus);
                bus.tick(3);
            } else {
                bus.tick(1);
            }
        },
        0xD9 => {
            cpu.program_counter = cpu.readFromStack16(bus);
            bus.tick(3);
            bus.interrupt.master_enable = true;
        },
        0xDA => {
            const operand = cpu.readU16(bus);
            bus.tick(2);
            if (cpu.af.bit8.carry_flag) {
                cpu.program_counter = operand;
                bus.tick(1);
            }
        },
        0xDC => {
            const operand = cpu.readU16(bus);
            bus.tick(2);
            if (cpu.af.bit8.carry_flag) {
                cpu.writeToStack16(bus, cpu.program_counter);
                bus.tick(2);
                cpu.program_counter = operand;
                bus.tick(1);
            }
        },
        0xDE => {
            cpu.sbca(cpu.readU8(bus));
            bus.tick(1);
        },
        0xDF => {
            cpu.writeToStack16(bus, cpu.program_counter);
            bus.tick(2);
            cpu.program_counter = 0x0018;
            bus.tick(1);
        },

        0xE0 => {
            const operand = cpu.readU8(bus);
            bus.tick(1);
            bus.write8(0xFF00 + @as(u16, operand), cpu.af.bit8.a);
            bus.tick(1);
        },
        0xE1 => {
            cpu.hl.bit16 = cpu.readFromStack16(bus);
            bus.tick(2);
        },
        0xE2 => {
            bus.write8(0xFF00 + @as(u16, cpu.bc.bit8.c), cpu.af.bit8.a);
            bus.tick(1);
        },
        0xE5 => {
            cpu.writeToStack16(bus, cpu.hl.bit16);
            bus.tick(3);
        },
        0xE6 => {
            cpu.anda(cpu.readU8(bus));
            bus.tick(1);
        },
        0xE7 => {
            cpu.writeToStack16(bus, cpu.program_counter);
            bus.tick(2);
            cpu.program_counter = 0x0020;
            bus.tick(1);
        },

        0xE8 => {
            const value: i8 = @bitCast(cpu.readU8(bus));
            bus.tick(1);
            var result = cpu.stack_pointer;
            bus.tick(1);
            if (value < 0) {
                result -%= @abs(value);
                cpu.af.bit8.carry_flag = (result & 0xFF) <= (cpu.stack_pointer & 0xFF);
                cpu.af.bit8.half_carry_flag = (result & 0xF) <= (cpu.stack_pointer & 0xF);
            } else {
                result +%= @intCast(value);
                cpu.af.bit8.carry_flag = ((cpu.stack_pointer & 0xFF) + @abs(value)) > 0xFF;
                cpu.af.bit8.half_carry_flag = ((cpu.stack_pointer & 0xF) + (@abs(value) & 0xF)) > 0xF;
            }

            cpu.stack_pointer = result;
            bus.tick(1);

            cpu.af.bit8.zero_flag = false;
            cpu.af.bit8.subtraction_flag = false;
        },
        0xE9 => {
            cpu.program_counter = cpu.hl.bit16;
        },
        0xEA => {
            const operand = cpu.readU16(bus);
            bus.tick(2);
            bus.write8(operand, cpu.af.bit8.a);
            bus.tick(1);
        },
        0xEE => {
            cpu.xora(cpu.readU8(bus));
            bus.tick(1);
        },
        0xEF => {
            cpu.writeToStack16(bus, cpu.program_counter);
            bus.tick(2);
            cpu.program_counter = 0x0028;
            bus.tick(1);
        },

        0xF0 => {
            const operand = cpu.readU8(bus);
            bus.tick(1);
            cpu.af.bit8.a = bus.read8(0xFF00 + @as(u16, operand));
            bus.tick(1);
        },
        0xF1 => {
            cpu.af.bit16 = cpu.readFromStack16(bus) & 0xFFF0;
            bus.tick(2);
        },
        0xF2 => {
            cpu.af.bit8.a = bus.read8(0xFF00 + @as(u16, cpu.bc.bit8.c));
            bus.tick(1);
        },
        0xF3 => {
            bus.interrupt.master_enable = false;
        },
        0xF5 => {
            cpu.writeToStack16(bus, cpu.af.bit16);
            bus.tick(3);
        },
        0xF6 => {
            cpu.ora(cpu.readU8(bus));
            bus.tick(1);
        },
        0xF7 => {
            cpu.writeToStack16(bus, cpu.program_counter);
            bus.tick(2);
            cpu.program_counter = 0x0030;
            bus.tick(1);
        },

        0xF8 => {
            const value: i8 = @bitCast(cpu.readU8(bus));
            bus.tick(1);
            var result: u32 = @intCast(cpu.stack_pointer);
            if (value < 0) {
                result -%= @abs(value);
                cpu.af.bit8.carry_flag = (result & 0xFF) <= (cpu.stack_pointer & 0xFF);
                cpu.af.bit8.half_carry_flag = (result & 0xF) <= (cpu.stack_pointer & 0xF);
            } else {
                result +%= @intCast(value);
                cpu.af.bit8.carry_flag = ((cpu.stack_pointer & 0xFF) + @abs(value)) > 0xFF;
                cpu.af.bit8.half_carry_flag = ((cpu.stack_pointer & 0xF) + (@abs(value) & 0xF)) > 0xF;
            }

            cpu.af.bit8.zero_flag = false;
            cpu.af.bit8.subtraction_flag = false;

            cpu.hl.bit16 = @truncate(result & 0xFFFF);
            bus.tick(1);
        },
        0xF9 => {
            cpu.stack_pointer = cpu.hl.bit16;
            bus.tick(1);
        },
        0xFA => {
            const operand = cpu.readU16(bus);
            bus.tick(2);
            cpu.af.bit8.a = bus.read8(operand);
            bus.tick(1);
        },
        0xFB => {
            bus.interrupt.master_enable_next_instruction = true;
        },
        0xFE => {
            cpu.cpa(cpu.readU8(bus));
            bus.tick(1);
        },
        0xFF => {
            cpu.writeToStack16(bus, cpu.program_counter);
            bus.tick(2);
            cpu.program_counter = 0x0038;
            bus.tick(1);
        },

        else => {
            std.debug.panic("Unknown opcode 0x{X:0>2}\n", .{opcode});
        },
    }
}

const InstructionRegister = enum {
    A,
    B,
    C,
    D,
    E,
    H,
    L,
    HL,
};

const PrefixInstructionType = struct {
    reg: InstructionRegister,
    type: union(enum) {
        RLC: void,
        RRC: void,
        RL: void,
        RR: void,
        SLA: void,
        SRA: void,
        SWAP: void,
        SRL: void,
        BIT: u3,
        RES: u3,
        SET: u3,
    },
};

fn createPrefixInstruction(comptime instructionType: PrefixInstructionType) *const fn (cpu: *CPU, bus: *Bus) void {
    return struct {
        fn instruction(cpu: *CPU, bus: *Bus) void {
            var reg_value: *u8 = switch (comptime instructionType.reg) {
                .A => &cpu.af.bit8.a,
                .B => &cpu.bc.bit8.b,
                .C => &cpu.bc.bit8.c,
                .D => &cpu.de.bit8.d,
                .E => &cpu.de.bit8.e,
                .H => &cpu.hl.bit8.h,
                .L => &cpu.hl.bit8.l,
                .HL => &cpu.hl.bit8.l,
            };
            if (instructionType.reg == .HL) {
                var value = bus.read8(cpu.hl.bit16);
                bus.tick(1);
                reg_value = &value;
            }
            switch (comptime instructionType.type) {
                .RLC => {
                    const carry: u8 = (reg_value.* & 0x80) >> 7;

                    cpu.af.bit8.carry_flag = (reg_value.* & 0x80) != 0;

                    reg_value.* = reg_value.* << 1;
                    reg_value.* +%= carry;

                    cpu.af.bit8.zero_flag = reg_value.* == 0;
                    cpu.af.bit8.half_carry_flag = false;
                    cpu.af.bit8.subtraction_flag = false;
                },
                .RRC => {
                    const carry = reg_value.* & 0x1;

                    reg_value.* = reg_value.* >> 1;

                    if (carry == 1) {
                        cpu.af.bit8.carry_flag = true;
                        reg_value.* |= 0x80;
                    } else {
                        cpu.af.bit8.carry_flag = false;
                    }

                    cpu.af.bit8.zero_flag = reg_value.* == 0;
                    cpu.af.bit8.half_carry_flag = false;
                    cpu.af.bit8.subtraction_flag = false;
                },
                .RL => {
                    const carry: u8 = if (cpu.af.bit8.carry_flag) 1 else 0;

                    cpu.af.bit8.carry_flag = (reg_value.* & 0x80) != 0;

                    reg_value.* = reg_value.* << 1;
                    reg_value.* +%= carry;

                    cpu.af.bit8.zero_flag = reg_value.* == 0;
                    cpu.af.bit8.half_carry_flag = false;
                    cpu.af.bit8.subtraction_flag = false;
                },
                .RR => {
                    const old_value = reg_value.*;
                    reg_value.* = reg_value.* >> 1;

                    if (cpu.af.bit8.carry_flag) {
                        reg_value.* |= 0x80;
                    }
                    cpu.af.bit8.carry_flag = (old_value & 0x1) != 0;

                    cpu.af.bit8.zero_flag = reg_value.* == 0;
                    cpu.af.bit8.half_carry_flag = false;
                    cpu.af.bit8.subtraction_flag = false;
                },
                .SLA => {
                    cpu.af.bit8.carry_flag = (reg_value.* & 0x80) != 0;
                    reg_value.* = reg_value.* << 1;
                    cpu.af.bit8.zero_flag = reg_value.* == 0;
                    cpu.af.bit8.half_carry_flag = false;
                    cpu.af.bit8.subtraction_flag = false;
                },
                .SRA => {
                    cpu.af.bit8.carry_flag = (reg_value.* & 0x1) != 0;
                    reg_value.* = (reg_value.* >> 1) | (reg_value.* & 0x80);
                    cpu.af.bit8.zero_flag = reg_value.* == 0;
                    cpu.af.bit8.half_carry_flag = false;
                    cpu.af.bit8.subtraction_flag = false;
                },
                .SWAP => {
                    reg_value.* = ((reg_value.* & 0xF) << 4) | ((reg_value.* & 0xF0) >> 4);
                    cpu.af.bit8.zero_flag = reg_value.* == 0;
                    cpu.af.bit8.carry_flag = false;
                    cpu.af.bit8.half_carry_flag = false;
                    cpu.af.bit8.subtraction_flag = false;
                },
                .SRL => {
                    cpu.af.bit8.carry_flag = (reg_value.* & 0x1) != 0;
                    reg_value.* = reg_value.* >> 1;
                    cpu.af.bit8.zero_flag = reg_value.* == 0;
                    cpu.af.bit8.half_carry_flag = false;
                    cpu.af.bit8.subtraction_flag = false;
                },
                .BIT => |b| {
                    cpu.af.bit8.zero_flag = (reg_value.* & (@as(u8, 1) << b)) == 0;
                    cpu.af.bit8.half_carry_flag = true;
                    cpu.af.bit8.subtraction_flag = false;
                },
                .RES => |b| {
                    reg_value.* &= ~(@as(u8, 1) << b);
                },
                .SET => |b| {
                    reg_value.* |= (@as(u8, 1) << b);
                },
            }
            if (instructionType.reg == .HL and instructionType.type != .BIT) {
                bus.write8(cpu.hl.bit16, reg_value.*);
                bus.tick(1);
            }
        }
    }.instruction;
}

const prefixInstructions = [256]*const fn (cpu: *CPU, bus: *Bus) void{
    createPrefixInstruction(.{ .reg = .B, .type = .{ .RLC = {} } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .RLC = {} } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .RLC = {} } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .RLC = {} } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .RLC = {} } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .RLC = {} } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .RLC = {} } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .RLC = {} } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .RRC = {} } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .RRC = {} } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .RRC = {} } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .RRC = {} } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .RRC = {} } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .RRC = {} } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .RRC = {} } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .RRC = {} } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .RL = {} } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .RL = {} } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .RL = {} } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .RL = {} } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .RL = {} } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .RL = {} } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .RL = {} } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .RL = {} } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .RR = {} } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .RR = {} } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .RR = {} } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .RR = {} } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .RR = {} } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .RR = {} } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .RR = {} } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .RR = {} } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .SLA = {} } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .SLA = {} } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .SLA = {} } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .SLA = {} } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .SLA = {} } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .SLA = {} } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .SLA = {} } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .SLA = {} } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .SRA = {} } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .SRA = {} } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .SRA = {} } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .SRA = {} } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .SRA = {} } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .SRA = {} } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .SRA = {} } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .SRA = {} } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .SWAP = {} } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .SWAP = {} } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .SWAP = {} } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .SWAP = {} } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .SWAP = {} } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .SWAP = {} } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .SWAP = {} } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .SWAP = {} } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .SRL = {} } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .SRL = {} } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .SRL = {} } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .SRL = {} } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .SRL = {} } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .SRL = {} } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .SRL = {} } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .SRL = {} } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .BIT = 0 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .BIT = 0 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .BIT = 0 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .BIT = 0 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .BIT = 0 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .BIT = 0 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .BIT = 0 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .BIT = 0 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .BIT = 1 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .BIT = 1 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .BIT = 1 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .BIT = 1 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .BIT = 1 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .BIT = 1 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .BIT = 1 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .BIT = 1 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .BIT = 2 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .BIT = 2 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .BIT = 2 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .BIT = 2 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .BIT = 2 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .BIT = 2 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .BIT = 2 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .BIT = 2 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .BIT = 3 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .BIT = 3 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .BIT = 3 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .BIT = 3 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .BIT = 3 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .BIT = 3 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .BIT = 3 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .BIT = 3 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .BIT = 4 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .BIT = 4 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .BIT = 4 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .BIT = 4 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .BIT = 4 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .BIT = 4 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .BIT = 4 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .BIT = 4 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .BIT = 5 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .BIT = 5 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .BIT = 5 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .BIT = 5 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .BIT = 5 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .BIT = 5 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .BIT = 5 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .BIT = 5 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .BIT = 6 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .BIT = 6 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .BIT = 6 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .BIT = 6 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .BIT = 6 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .BIT = 6 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .BIT = 6 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .BIT = 6 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .BIT = 7 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .BIT = 7 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .BIT = 7 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .BIT = 7 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .BIT = 7 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .BIT = 7 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .BIT = 7 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .BIT = 7 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .RES = 0 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .RES = 0 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .RES = 0 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .RES = 0 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .RES = 0 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .RES = 0 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .RES = 0 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .RES = 0 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .RES = 1 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .RES = 1 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .RES = 1 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .RES = 1 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .RES = 1 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .RES = 1 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .RES = 1 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .RES = 1 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .RES = 2 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .RES = 2 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .RES = 2 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .RES = 2 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .RES = 2 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .RES = 2 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .RES = 2 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .RES = 2 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .RES = 3 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .RES = 3 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .RES = 3 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .RES = 3 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .RES = 3 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .RES = 3 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .RES = 3 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .RES = 3 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .RES = 4 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .RES = 4 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .RES = 4 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .RES = 4 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .RES = 4 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .RES = 4 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .RES = 4 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .RES = 4 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .RES = 5 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .RES = 5 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .RES = 5 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .RES = 5 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .RES = 5 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .RES = 5 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .RES = 5 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .RES = 5 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .RES = 6 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .RES = 6 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .RES = 6 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .RES = 6 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .RES = 6 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .RES = 6 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .RES = 6 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .RES = 6 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .RES = 7 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .RES = 7 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .RES = 7 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .RES = 7 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .RES = 7 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .RES = 7 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .RES = 7 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .RES = 7 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .SET = 0 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .SET = 0 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .SET = 0 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .SET = 0 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .SET = 0 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .SET = 0 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .SET = 0 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .SET = 0 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .SET = 1 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .SET = 1 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .SET = 1 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .SET = 1 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .SET = 1 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .SET = 1 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .SET = 1 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .SET = 1 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .SET = 2 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .SET = 2 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .SET = 2 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .SET = 2 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .SET = 2 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .SET = 2 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .SET = 2 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .SET = 2 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .SET = 3 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .SET = 3 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .SET = 3 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .SET = 3 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .SET = 3 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .SET = 3 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .SET = 3 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .SET = 3 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .SET = 4 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .SET = 4 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .SET = 4 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .SET = 4 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .SET = 4 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .SET = 4 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .SET = 4 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .SET = 4 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .SET = 5 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .SET = 5 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .SET = 5 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .SET = 5 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .SET = 5 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .SET = 5 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .SET = 5 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .SET = 5 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .SET = 6 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .SET = 6 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .SET = 6 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .SET = 6 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .SET = 6 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .SET = 6 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .SET = 6 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .SET = 6 } }),

    createPrefixInstruction(.{ .reg = .B, .type = .{ .SET = 7 } }),
    createPrefixInstruction(.{ .reg = .C, .type = .{ .SET = 7 } }),
    createPrefixInstruction(.{ .reg = .D, .type = .{ .SET = 7 } }),
    createPrefixInstruction(.{ .reg = .E, .type = .{ .SET = 7 } }),
    createPrefixInstruction(.{ .reg = .H, .type = .{ .SET = 7 } }),
    createPrefixInstruction(.{ .reg = .L, .type = .{ .SET = 7 } }),
    createPrefixInstruction(.{ .reg = .HL, .type = .{ .SET = 7 } }),
    createPrefixInstruction(.{ .reg = .A, .type = .{ .SET = 7 } }),
};
