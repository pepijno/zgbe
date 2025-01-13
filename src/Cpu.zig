const Cpu = @This();

const std = @import("std");
const Memory = @import("Memory.zig");

const Interrupt = struct {
    master: bool,
};

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
interrupt: Interrupt,

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

pub fn getRegister8(cpu: *const Cpu, register: Register) u8 {
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

pub fn setRegister8(cpu: *Cpu, value: u8, register: Register) void {
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

pub fn getRegister16(cpu: *const Cpu, register: Register) u16 {
    return switch (register) {
        .bc => cpu.bc.bit16,
        .de => cpu.de.bit16,
        .hl => cpu.hl.bit16,
        .sp => cpu.stack_pointer,
        else => 0,
    };
}

pub fn setRegister16(cpu: *Cpu, value: u16, register: Register) void {
    switch (register) {
        .bc => cpu.bc.bit16 = value,
        .de => cpu.de.bit16 = value,
        .hl => cpu.hl.bit16 = value,
        .sp => cpu.stack_pointer = value,
        else => {},
    }
}

pub fn init() Cpu {
    return .{
        .af = .{ .bit16 = 0x0100 },
        .bc = .{ .bit16 = 0 },
        .de = .{ .bit16 = 0 },
        .hl = .{ .bit16 = 0 },
        .stack_pointer = 0,
        .program_counter = 0x100,
        .interrupt = .{
            .master = true,
        },
    };
}

pub fn readU8(cpu: *Cpu, memory: Memory) u8 {
    const value = memory.read8(cpu.program_counter);
    cpu.program_counter += 1;
    return value;
}

pub fn readU16(cpu: *Cpu, memory: Memory) u16 {
    const value1 = cpu.readU8(memory);
    const value2 = cpu.readU8(memory);
    return @as(u16, value1) | (@as(u16, value2) << 8);
}

pub fn writeToStack16(cpu: *Cpu, memory: *Memory, value: u16) void {
    cpu.stack_pointer -= 2;
    memory.write16(cpu.stack_pointer, value);
    std.debug.print("Stack write 0x{X:0>4}\n", .{value});
}

pub fn readFromStack16(cpu: *Cpu, memory: Memory) u16 {
    const value = memory.read16(cpu.stack_pointer);
    cpu.stack_pointer += 2;
    std.debug.print("Stack read 0x{X:0>4}\n", .{value});
    return value;
}

var last_program_counter: u16 = 0;

pub fn debugJump(cpu: *Cpu) void {
    if (cpu.program_counter != last_program_counter) {
        std.debug.print("Jumped to 0x{X:0>4}\n", .{cpu.program_counter});
        last_program_counter = cpu.program_counter;
    }
}

fn flagToChar(flag: bool, flag_char: u8) u8 {
    return if (flag) flag_char else '-';
}

pub fn printState(cpu: Cpu, memory: Memory, writer: anytype) !void {
    try writer.print("Cpu state:\n", .{});
    try writer.print("        AF: 0x{X:0>4}        A: 0x{X:0>2}        Flags: {c} {c} {c} {c}\n", .{
        cpu.af.bit16,
        cpu.af.bit8.a,
        flagToChar(cpu.af.bit8.zero_flag, 'Z'),
        flagToChar(cpu.af.bit8.subtraction_flag, 'N'),
        flagToChar(cpu.af.bit8.half_carry_flag, 'H'),
        flagToChar(cpu.af.bit8.carry_flag, 'C'),
    });
    try writer.print("        BC: 0x{X:0>4}        B: 0x{X:0>2}        C: 0x{X:0>2}\n", .{ cpu.bc.bit16, cpu.bc.bit8.b, cpu.bc.bit8.c });
    try writer.print("        DE: 0x{X:0>4}        D: 0x{X:0>2}        E: 0x{X:0>2}\n", .{ cpu.de.bit16, cpu.de.bit8.d, cpu.de.bit8.e });
    try writer.print("        HL: 0x{X:0>4}        H: 0x{X:0>2}        L: 0x{X:0>2}\n", .{ cpu.hl.bit16, cpu.hl.bit8.h, cpu.hl.bit8.l });
    try writer.print("        SP: 0x{X:0>4}\n", .{cpu.stack_pointer});
    try writer.print("        PC: 0x{X:0>4}\n", .{cpu.program_counter});
    try writer.print("       MEM: {X:0>2} {X:0>2} {X:0>2} ...\n", .{ memory.read8(cpu.program_counter), memory.read8(cpu.program_counter + 1), memory.read8(cpu.program_counter + 2) });
    try writer.print("\n", .{});
}

pub fn cpuTick(cpu: *Cpu, memory: *Memory) void {
    if (cpu.halted) {
        return;
    }

    const opcode = cpu.readU8(memory.*);
    std.debug.print("Opcode 0x{X:0>2}\n", .{opcode});

    cpu.runInstruction(memory, opcode);

    cpu.printState(memory.*, std.io.getStdOut().writer()) catch unreachable;
}

pub fn cpuRun(cpu: *Cpu, memory: *Memory) void {
    cpu.running = true;
    while (cpu.running) {
        cpu.cpuTick(memory);
    }
}

fn incRegister(cpu: *Cpu, value: *u8) void {
    cpu.af.bit8.half_carry_flag = (value.* & 0xF) == 0xF;

    value.* +%= 1;

    cpu.af.bit8.zero_flag = value.* == 0;
    cpu.af.bit8.subtraction_flag = false;
}

fn decRegister(cpu: *Cpu, value: *u8) void {
    cpu.af.bit8.half_carry_flag = (value.* & 0xF) == 0;

    value.* -%= 1;

    cpu.af.bit8.zero_flag = value.* == 0;
    cpu.af.bit8.subtraction_flag = true;
}

fn add2(cpu: *Cpu, dest: *u16, value: u16) void {
    const result = @as(u32, dest.*) + @as(u32, value);

    cpu.af.bit8.carry_flag = (result & 0xFFFF0000) != 0;
    dest.* = @truncate(result & 0xFFFF);

    cpu.af.bit8.half_carry_flag = ((dest.* & 0xF) + (value & 0xF)) > 0xF;

    cpu.af.bit8.subtraction_flag = false;
}

fn adda(cpu: *Cpu, value: u8) void {
    const result = @as(u16, cpu.af.bit8.a) + @as(u16, value);

    cpu.af.bit8.carry_flag = (result & 0xFF00) != 0;
    cpu.af.bit8.a = @truncate(result & 0xFF);

    cpu.af.bit8.zero_flag = cpu.af.bit8.a == 0;
    cpu.af.bit8.half_carry_flag = ((cpu.af.bit8.a & 0xF) + (value & 0xF)) > 0xF;

    cpu.af.bit8.subtraction_flag = false;
}

fn adca(cpu: *Cpu, value: u8) void {
    const result: u8 = value +% @as(u8, if (cpu.af.bit8.carry_flag) 1 else 0);
    const ress = @as(u16, cpu.af.bit8.a) + @as(u16, result);

    cpu.af.bit8.carry_flag = (ress & 0xFF00) != 0;

    cpu.af.bit8.zero_flag = cpu.af.bit8.a == ress;
    cpu.af.bit8.half_carry_flag = ((cpu.af.bit8.a & 0xF) + (value & 0xF)) > 0xF;

    cpu.af.bit8.subtraction_flag = false;

    cpu.af.bit8.a = @truncate(ress & 0xFF);
}

fn suba(cpu: *Cpu, value: u8) void {
    cpu.af.bit8.carry_flag = value > cpu.af.bit8.a;

    cpu.af.bit8.half_carry_flag = (value & 0xF) > (cpu.af.bit8.a & 0xF);

    cpu.af.bit8.a -%= value;

    cpu.af.bit8.zero_flag = cpu.af.bit8.a == 0;
    cpu.af.bit8.subtraction_flag = true;
}

fn sbca(cpu: *Cpu, value: u8) void {
    const result: u8 = value +% @as(u8, if (cpu.af.bit8.carry_flag) 1 else 0);
    cpu.af.bit8.subtraction_flag = true;

    cpu.af.bit8.carry_flag = result > cpu.af.bit8.a;

    cpu.af.bit8.half_carry_flag = (result & 0xF) > (cpu.af.bit8.a & 0xF);

    cpu.af.bit8.a -%= result;

    cpu.af.bit8.zero_flag = cpu.af.bit8.a == 0;
}

fn anda(cpu: *Cpu, value: u8) void {
    cpu.af.bit8.a &= value;

    cpu.af.bit8.zero_flag = cpu.af.bit8.a == 0;
    cpu.af.bit8.subtraction_flag = false;
    cpu.af.bit8.half_carry_flag = true;
    cpu.af.bit8.carry_flag = false;
}

fn xora(cpu: *Cpu, value: u8) void {
    cpu.af.bit8.a ^= value;

    cpu.af.bit8.zero_flag = cpu.af.bit8.a == 0;
    cpu.af.bit8.subtraction_flag = false;
    cpu.af.bit8.half_carry_flag = false;
    cpu.af.bit8.carry_flag = false;
}

fn ora(cpu: *Cpu, value: u8) void {
    cpu.af.bit8.a |= value;

    cpu.af.bit8.zero_flag = cpu.af.bit8.a == 0;
    cpu.af.bit8.subtraction_flag = false;
    cpu.af.bit8.half_carry_flag = false;
    cpu.af.bit8.carry_flag = false;
}

fn cpa(cpu: *Cpu, value: u8) void {
    cpu.af.bit8.zero_flag = cpu.af.bit8.a == value;
    cpu.af.bit8.carry_flag = value > cpu.af.bit8.a;
    cpu.af.bit8.half_carry_flag = (value & 0xF) > (cpu.af.bit8.a & 0xF);
    cpu.af.bit8.subtraction_flag = true;
}

fn runInstruction(cpu: *Cpu, memory: *Memory, opcode: u8) void {
    switch (opcode) {
        0x00 => {}, // NOP
        0x01 => {
            cpu.bc.bit16 = cpu.readU16(memory.*);
        },
        0x02 => {
            memory.write8(cpu.bc.bit16, cpu.af.bit8.a);
        },
        0x03 => {
            cpu.bc.bit16 +%= 1;
        },
        0x04 => {
            cpu.incRegister(&cpu.bc.bit8.b);
        },
        0x05 => {
            cpu.decRegister(&cpu.bc.bit8.b);
        },
        0x06 => {
            cpu.bc.bit8.b = cpu.readU8(memory.*);
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
            const operand = cpu.readU16(memory.*);
            memory.write16(operand, cpu.stack_pointer);
        },
        0x09 => {
            cpu.add2(&cpu.hl.bit16, cpu.bc.bit16);
        },
        0x0A => {
            cpu.af.bit8.a = memory.read8(cpu.bc.bit16);
        },
        0x0B => {
            cpu.bc.bit16 -%= 1;
        },
        0x0C => {
            cpu.incRegister(&cpu.bc.bit8.c);
        },
        0x0D => {
            cpu.decRegister(&cpu.bc.bit8.c);
        },
        0x0E => {
            cpu.bc.bit8.c = cpu.readU8(memory.*);
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
            cpu.de.bit16 = cpu.readU16(memory.*);
        },
        0x12 => {
            memory.write8(cpu.de.bit16, cpu.af.bit8.a);
        },
        0x13 => {
            cpu.de.bit16 +%= 1;
        },
        0x14 => {
            cpu.incRegister(&cpu.de.bit8.d);
        },
        0x15 => {
            cpu.decRegister(&cpu.de.bit8.d);
        },
        0x16 => {
            cpu.de.bit8.d = cpu.readU8(memory.*);
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
            const operand = cpu.readU8(memory.*);
            const val: i8 = @bitCast(operand);
            cpu.program_counter += @intCast(val);
            cpu.debugJump();
        },
        0x19 => {
            cpu.add2(&cpu.hl.bit16, cpu.de.bit16);
        },
        0x1A => {
            cpu.af.bit8.a = memory.read8(cpu.de.bit16);
        },
        0x1B => {
            cpu.de.bit16 -%= 1;
        },
        0x1C => {
            cpu.incRegister(&cpu.de.bit8.e);
        },
        0x1D => {
            cpu.decRegister(&cpu.de.bit8.e);
        },
        0x1E => {
            cpu.de.bit8.e = cpu.readU8(memory.*);
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
            if (!cpu.af.bit8.zero_flag) {
                cpu.program_counter += cpu.readU8(memory.*);
                cpu.debugJump();
            }
        },
        0x21 => {
            cpu.hl.bit16 = cpu.readU16(memory.*);
        },
        0x22 => {
            memory.write8(cpu.hl.bit16, cpu.af.bit8.a);
            cpu.hl.bit16 +%= 1;
        },
        0x23 => {
            cpu.hl.bit16 +%= 1;
        },
        0x24 => {
            cpu.incRegister(&cpu.hl.bit8.h);
        },
        0x25 => {
            cpu.decRegister(&cpu.hl.bit8.h);
        },
        0x26 => {
            cpu.hl.bit8.h = cpu.readU8(memory.*);
        },
        0x27 => {
            var adj: u8 = cpu.af.bit8.a;

            if (cpu.af.bit8.subtraction_flag) {
                if (cpu.af.bit8.half_carry_flag) adj -%= 0x6;
                if (cpu.af.bit8.carry_flag) adj -%= 0x60;
            } else {
                if (cpu.af.bit8.half_carry_flag or (adj & 0xF) > 9) adj +%= 0x6;
                if (cpu.af.bit8.carry_flag or adj > 0x9F) adj +%= 0x60;
            }

            cpu.af.bit8.a = adj;
            cpu.af.bit8.half_carry_flag = false;

            cpu.af.bit8.zero_flag = cpu.af.bit8.a == 0;

            if (adj >= 0x100) cpu.af.bit8.carry_flag = true;
        },

        0x28 => {
            if (cpu.af.bit8.zero_flag) {
                cpu.program_counter +%= cpu.readU8(memory.*);
                cpu.debugJump();
            }
        },
        0x29 => {
            cpu.add2(&cpu.hl.bit16, cpu.hl.bit16);
        },
        0x2A => {
            cpu.af.bit8.a = memory.read8(cpu.hl.bit16);
            cpu.hl.bit16 +%= 1;
        },
        0x2B => {
            cpu.hl.bit16 -%= 1;
        },
        0x2C => {
            cpu.incRegister(&cpu.hl.bit8.l);
        },
        0x2D => {
            cpu.decRegister(&cpu.hl.bit8.l);
        },
        0x2E => {
            cpu.hl.bit8.l = cpu.readU8(memory.*);
        },
        0x2F => {
            cpu.af.bit8.a = ~cpu.af.bit8.a;
            cpu.af.bit8.half_carry_flag = true;
            cpu.af.bit8.subtraction_flag = true;
        },

        0x30 => {
            if (!cpu.af.bit8.carry_flag) {
                cpu.program_counter += cpu.readU8(memory.*);
                cpu.debugJump();
            }
        },
        0x31 => {
            cpu.stack_pointer = cpu.readU16(memory.*);
        },
        0x32 => {
            memory.write8(cpu.hl.bit16, cpu.af.bit8.a);
            cpu.hl.bit16 -%= 1;
        },
        0x33 => {
            cpu.stack_pointer +%= 1;
        },
        0x34 => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.incRegister(&value);
            memory.write8(cpu.hl.bit16, value);
        },
        0x35 => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.decRegister(&value);
            memory.write8(cpu.hl.bit16, value);
        },
        0x36 => {
            memory.write8(cpu.hl.bit16, cpu.readU8(memory.*));
        },
        0x37 => {
            cpu.af.bit8.carry_flag = true;
        },

        0x38 => {
            if (cpu.af.bit8.carry_flag) {
                cpu.program_counter +%= cpu.readU8(memory.*);
                cpu.debugJump();
            }
        },
        0x39 => {
            cpu.add2(&cpu.hl.bit16, cpu.stack_pointer);
        },
        0x3A => {
            cpu.af.bit8.a = memory.read8(cpu.hl.bit16);
            cpu.hl.bit16 -%= 1;
        },
        0x3B => {
            cpu.stack_pointer -%= 1;
        },
        0x3C => {
            cpu.incRegister(&cpu.af.bit8.a);
        },
        0x3D => {
            cpu.decRegister(&cpu.af.bit8.a);
        },
        0x3E => {
            cpu.af.bit8.a = cpu.readU8(memory.*);
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
            cpu.bc.bit8.b = memory.read8(cpu.hl.bit16);
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
            cpu.bc.bit8.c = memory.read8(cpu.hl.bit16);
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
            cpu.de.bit8.d = memory.read8(cpu.hl.bit16);
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
            cpu.de.bit8.e = memory.read8(cpu.hl.bit16);
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
            cpu.hl.bit8.h = memory.read8(cpu.hl.bit16);
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
            cpu.hl.bit8.l = memory.read8(cpu.hl.bit16);
        },
        0x6F => {
            cpu.hl.bit8.l = cpu.af.bit8.a;
        },

        0x70 => {
            memory.write8(cpu.hl.bit16, cpu.bc.bit8.b);
        },
        0x71 => {
            memory.write8(cpu.hl.bit16, cpu.bc.bit8.c);
        },
        0x72 => {
            memory.write8(cpu.hl.bit16, cpu.de.bit8.d);
        },
        0x73 => {
            memory.write8(cpu.hl.bit16, cpu.de.bit8.e);
        },
        0x74 => {
            memory.write8(cpu.hl.bit16, cpu.hl.bit8.h);
        },
        0x75 => {
            memory.write8(cpu.hl.bit16, cpu.hl.bit8.l);
        },
        0x76 => {
            cpu.halted = true;
        },
        0x77 => {
            memory.write8(cpu.hl.bit16, cpu.af.bit8.a);
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
            cpu.af.bit8.a = memory.read8(cpu.hl.bit16);
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
            cpu.adda(memory.read8(cpu.hl.bit16));
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
            cpu.adca(memory.read8(cpu.hl.bit16));
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
            cpu.suba(memory.read8(cpu.hl.bit16));
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
            cpu.sbca(memory.read8(cpu.hl.bit16));
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
            cpu.anda(memory.read8(cpu.hl.bit16));
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
            cpu.xora(memory.read8(cpu.hl.bit16));
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
            cpu.ora(memory.read8(cpu.hl.bit16));
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
            cpu.cpa(memory.read8(cpu.hl.bit16));
        },
        0xBF => {
            cpu.cpa(cpu.af.bit8.a);
        },

        0xC0 => {
            if (!cpu.af.bit8.zero_flag) {
                cpu.program_counter = cpu.readFromStack16(memory.*);
                cpu.debugJump();
            }
        },
        0xC1 => {
            cpu.bc.bit16 = cpu.readFromStack16(memory.*);
        },
        0xC2 => {
            if (!cpu.af.bit8.zero_flag) {
                cpu.program_counter = cpu.readU16(memory.*);
                cpu.debugJump();
            }
        },
        0xC3 => {
            cpu.program_counter = cpu.readU16(memory.*);
            cpu.debugJump();
        },
        0xC4 => {
            if (!cpu.af.bit8.zero_flag) {
                const operand = cpu.readU16(memory.*);
                cpu.writeToStack16(memory, cpu.program_counter);
                cpu.program_counter = operand;
                cpu.debugJump();
            }
        },
        0xC5 => {
            cpu.writeToStack16(memory, cpu.bc.bit16);
        },
        0xC6 => {
            cpu.adda(cpu.readU8(memory.*));
        },
        0xC7 => {
            cpu.writeToStack16(memory, cpu.program_counter);
            cpu.program_counter = 0x0000;
        },

        0xC8 => {
            if (cpu.af.bit8.zero_flag) {
                cpu.program_counter = cpu.readFromStack16(memory.*);
                cpu.debugJump();
            }
        },
        0xC9 => {
            cpu.program_counter = cpu.readFromStack16(memory.*);
            cpu.debugJump();
        },
        0xCA => {
            if (cpu.af.bit8.zero_flag) {
                cpu.program_counter += cpu.readU16(memory.*);
                cpu.debugJump();
            }
        },
        0xCB => {
            const prefix = cpu.readU8(memory.*);
            cpu.runPrefixInstruction(memory, prefix);
        },
        0xCC => {
            if (cpu.af.bit8.zero_flag) {
                const operand = cpu.readU16(memory.*);
                cpu.writeToStack16(memory, cpu.program_counter);
                cpu.program_counter = operand;
                cpu.debugJump();
            }
        },
        0xCD => {
            const operand = cpu.readU16(memory.*);
            cpu.writeToStack16(memory, cpu.program_counter);
            cpu.program_counter = operand;
            cpu.debugJump();
        },
        0xCE => {
            cpu.adca(cpu.readU8(memory.*));
        },
        0xCF => {
            cpu.writeToStack16(memory, cpu.program_counter);
            cpu.program_counter = 0x0008;
        },

        0xD0 => {
            if (!cpu.af.bit8.carry_flag) {
                cpu.program_counter = cpu.readFromStack16(memory.*);
                cpu.debugJump();
            }
        },
        0xD1 => {
            cpu.de.bit16 = cpu.readFromStack16(memory.*);
        },
        0xD2 => {
            if (!cpu.af.bit8.carry_flag) {
                cpu.program_counter = cpu.readU16(memory.*);
                cpu.debugJump();
            }
        },
        0xD4 => {
            if (!cpu.af.bit8.carry_flag) {
                const operand = cpu.readU16(memory.*);
                cpu.writeToStack16(memory, cpu.program_counter);
                cpu.program_counter = operand;
                cpu.debugJump();
            }
        },
        0xD5 => {
            cpu.writeToStack16(memory, cpu.de.bit16);
        },
        0xD6 => {
            cpu.suba(cpu.readU8(memory.*));
        },
        0xD7 => {
            cpu.writeToStack16(memory, cpu.program_counter);
            cpu.program_counter = 0x0010;
        },

        0xD8 => {
            if (cpu.af.bit8.carry_flag) {
                cpu.program_counter = cpu.readFromStack16(memory.*);
                cpu.debugJump();
            }
        },
        0xD9 => {
            cpu.program_counter = cpu.readFromStack16(memory.*);
            cpu.debugJump();
            cpu.interrupt.master = true;
        },
        0xDA => {
            if (cpu.af.bit8.carry_flag) {
                cpu.program_counter += cpu.readU16(memory.*);
                cpu.debugJump();
            }
        },
        0xDC => {
            if (cpu.af.bit8.carry_flag) {
                const operand = cpu.readU16(memory.*);
                cpu.writeToStack16(memory, cpu.program_counter);
                cpu.program_counter = operand;
                cpu.debugJump();
            }
        },
        0xDE => {
            cpu.sbca(cpu.readU8(memory.*));
        },
        0xDF => {
            cpu.writeToStack16(memory, cpu.program_counter);
            cpu.program_counter = 0x0018;
        },

        0xE0 => {
            const operand = cpu.readU8(memory.*);
            memory.write8(0xFF00 + @as(u16, operand), cpu.af.bit8.a);
        },
        0xE1 => {
            cpu.hl.bit16 = cpu.readFromStack16(memory.*);
        },
        0xE2 => {
            memory.write8(0xFF00 + @as(u16, cpu.bc.bit8.c), cpu.af.bit8.a);
        },
        0xE5 => {
            cpu.writeToStack16(memory, cpu.hl.bit16);
        },
        0xE6 => {
            cpu.anda(cpu.readU8(memory.*));
        },
        0xE7 => {
            cpu.writeToStack16(memory, cpu.program_counter);
            cpu.program_counter = 0x0020;
        },

        0xE8 => {
            const operand = cpu.readU8(memory.*);
            const result = @as(u32, cpu.stack_pointer) + @as(u32, operand);
            cpu.af.bit8.carry_flag = (result & 0xFFFF0000) != 0;

            cpu.stack_pointer = @truncate(result & 0xFFFF);

            cpu.af.bit8.half_carry_flag = ((cpu.stack_pointer & 0xF) + (operand & 0xF)) > 0xF;
            cpu.af.bit8.zero_flag = false;
            cpu.af.bit8.subtraction_flag = false;
        },
        0xE9 => {
            cpu.program_counter = cpu.hl.bit16;
            cpu.debugJump();
        },
        0xEA => {
            const operand = cpu.readU16(memory.*);
            memory.write8(operand, cpu.af.bit8.a);
        },
        0xEE => {
            cpu.xora(cpu.readU8(memory.*));
        },
        0xEF => {
            cpu.writeToStack16(memory, cpu.program_counter);
            cpu.program_counter = 0x0028;
        },

        0xF0 => {
            const operand = cpu.readU8(memory.*);
            cpu.af.bit8.a = memory.read8(0xFF00 + @as(u16, operand));
        },
        0xF1 => {
            cpu.af.bit16 = cpu.readFromStack16(memory.*);
        },
        0xF2 => {
            cpu.af.bit8.a = memory.read8(0xFF00 + @as(u16, cpu.bc.bit8.c));
        },
        0xF3 => {
            cpu.interrupt.master = false;
        },
        0xF5 => {
            cpu.writeToStack16(memory, cpu.af.bit16);
        },
        0xF6 => {
            cpu.ora(cpu.readU8(memory.*));
        },
        0xF7 => {
            cpu.writeToStack16(memory, cpu.program_counter);
            cpu.program_counter = 0x0030;
        },

        0xF8 => {
            const operand = cpu.readU8(memory.*);
            const result = @as(u32, cpu.stack_pointer) + @as(u32, operand);
            cpu.af.bit8.carry_flag = (result & 0xFFFF0000) != 0;

            cpu.af.bit8.half_carry_flag = ((cpu.stack_pointer & 0xF) + (operand & 0xF)) > 0xF;
            cpu.af.bit8.zero_flag = false;
            cpu.af.bit8.subtraction_flag = false;

            cpu.hl.bit16 = @truncate(result & 0xFFFF);
        },
        0xF9 => {
            cpu.stack_pointer = cpu.hl.bit16;
        },
        0xFA => {
            const operand = cpu.readU16(memory.*);
            cpu.af.bit8.a = memory.read8(operand);
        },
        0xFB => {
            cpu.interrupt.master = true;
        },
        0xFE => {
            cpu.cpa(cpu.readU8(memory.*));
        },
        0xFF => {
            cpu.writeToStack16(memory, cpu.program_counter);
            cpu.program_counter = 0x0038;
        },

        else => {
            std.debug.panic("Unknown opcode 0x{X:0>2}\n", .{opcode});
        },
    }
}

fn rlc(cpu: *Cpu, value: *u8) void {
    const carry: u8 = (value.* & 0x80) >> 7;

    cpu.af.bit8.carry_flag = (value.* & 0x80) != 0;

    value.* = value.* << 1;
    value.* +%= carry;

    cpu.af.bit8.zero_flag = value.* == 0;
    cpu.af.bit8.half_carry_flag = false;
    cpu.af.bit8.subtraction_flag = false;
}

fn rrc(cpu: *Cpu, value: *u8) void {
    const carry = value.* & 0x1;

    value.* = value.* >> 1;

    if (carry == 1) {
        cpu.af.bit8.carry_flag = true;
        value.* |= 0x80;
    } else {
        cpu.af.bit8.carry_flag = false;
    }

    cpu.af.bit8.zero_flag = value.* == 0;
    cpu.af.bit8.half_carry_flag = false;
    cpu.af.bit8.subtraction_flag = false;
}

fn rl(cpu: *Cpu, value: *u8) void {
    const carry: u8 = if (cpu.af.bit8.carry_flag) 1 else 0;

    cpu.af.bit8.carry_flag = (value.* & 0x80) != 0;

    value.* = value.* << 1;
    value.* +%= carry;

    cpu.af.bit8.zero_flag = value.* == 0;
    cpu.af.bit8.half_carry_flag = false;
    cpu.af.bit8.subtraction_flag = false;
}

fn rr(cpu: *Cpu, value: *u8) void {
    value.* = value.* >> 1;

    if (cpu.af.bit8.carry_flag) {
        value.* |= 0x80;
    }
    cpu.af.bit8.carry_flag = (value.* & 0x1) != 0;

    cpu.af.bit8.zero_flag = value.* == 0;
    cpu.af.bit8.half_carry_flag = false;
    cpu.af.bit8.subtraction_flag = false;
}

fn sla(cpu: *Cpu, value: *u8) void {
    cpu.af.bit8.carry_flag = (value.* & 0x80) != 0;
    value.* = value.* << 1;
    cpu.af.bit8.zero_flag = value.* == 0;
    cpu.af.bit8.half_carry_flag = false;
    cpu.af.bit8.subtraction_flag = false;
}

fn sra(cpu: *Cpu, value: *u8) void {
    cpu.af.bit8.carry_flag = (value.* & 0x1) != 0;
    value.* = (value.* >> 1) | (value.* & 0x80);
    cpu.af.bit8.zero_flag = value.* == 0;
    cpu.af.bit8.half_carry_flag = false;
    cpu.af.bit8.subtraction_flag = false;
}

fn swap(cpu: *Cpu, value: *u8) void {
    value.* = ((value.* & 0xF) << 4) | ((value.* & 0xF0) >> 4);
    cpu.af.bit8.zero_flag = value.* == 0;
    cpu.af.bit8.carry_flag = false;
    cpu.af.bit8.half_carry_flag = false;
    cpu.af.bit8.subtraction_flag = false;
}

fn srl(cpu: *Cpu, value: *u8) void {
    cpu.af.bit8.carry_flag = (value.* & 0x1) != 0;

    value.* = value.* >> 1;
    cpu.af.bit8.zero_flag = value.* == 0;
    cpu.af.bit8.half_carry_flag = false;
    cpu.af.bit8.subtraction_flag = false;
}

fn bit(cpu: *Cpu, b: u3, value: u8) void {
    cpu.af.bit8.zero_flag = (value & (@as(u8, 1) << b)) != 0;
    cpu.af.bit8.half_carry_flag = true;
    cpu.af.bit8.subtraction_flag = false;
}

fn res(cpu: *Cpu, b: u3, value: *u8) void {
    _ = cpu;
    value.* &= ~(@as(u8, 1) << b);
}

fn set(cpu: *Cpu, b: u3, value: *u8) void {
    _ = cpu;
    value.* |= (@as(u8, 1) << b);
}

fn runPrefixInstruction(cpu: *Cpu, memory: *Memory, opcode: u8) void {
    switch (opcode) {
        0x00 => {
            cpu.rlc(&cpu.bc.bit8.b);
        },
        0x01 => {
            cpu.rlc(&cpu.bc.bit8.c);
        },
        0x02 => {
            cpu.rlc(&cpu.de.bit8.d);
        },
        0x03 => {
            cpu.rlc(&cpu.de.bit8.e);
        },
        0x04 => {
            cpu.rlc(&cpu.hl.bit8.h);
        },
        0x05 => {
            cpu.rlc(&cpu.hl.bit8.l);
        },
        0x06 => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.rlc(&value);
            memory.write8(cpu.hl.bit16, value);
        },
        0x07 => {
            cpu.rlc(&cpu.af.bit8.a);
        },

        0x08 => {
            cpu.rrc(&cpu.bc.bit8.b);
        },
        0x09 => {
            cpu.rrc(&cpu.bc.bit8.c);
        },
        0x0A => {
            cpu.rrc(&cpu.de.bit8.d);
        },
        0x0B => {
            cpu.rrc(&cpu.de.bit8.e);
        },
        0x0C => {
            cpu.rrc(&cpu.hl.bit8.h);
        },
        0x0D => {
            cpu.rrc(&cpu.hl.bit8.l);
        },
        0x0E => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.rrc(&value);
            memory.write8(cpu.hl.bit16, value);
        },
        0x0F => {
            cpu.rrc(&cpu.af.bit8.a);
        },

        0x10 => {
            cpu.rl(&cpu.bc.bit8.b);
        },
        0x11 => {
            cpu.rl(&cpu.bc.bit8.c);
        },
        0x12 => {
            cpu.rl(&cpu.de.bit8.d);
        },
        0x13 => {
            cpu.rl(&cpu.de.bit8.e);
        },
        0x14 => {
            cpu.rl(&cpu.hl.bit8.h);
        },
        0x15 => {
            cpu.rl(&cpu.hl.bit8.l);
        },
        0x16 => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.rl(&value);
            memory.write8(cpu.hl.bit16, value);
        },
        0x17 => {
            cpu.rl(&cpu.af.bit8.a);
        },

        0x18 => {
            cpu.rr(&cpu.bc.bit8.b);
        },
        0x19 => {
            cpu.rr(&cpu.bc.bit8.c);
        },
        0x1A => {
            cpu.rr(&cpu.de.bit8.d);
        },
        0x1B => {
            cpu.rr(&cpu.de.bit8.e);
        },
        0x1C => {
            cpu.rr(&cpu.hl.bit8.h);
        },
        0x1D => {
            cpu.rr(&cpu.hl.bit8.l);
        },
        0x1E => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.rr(&value);
            memory.write8(cpu.hl.bit16, value);
        },
        0x1F => {
            cpu.rr(&cpu.af.bit8.a);
        },

        0x20 => {
            cpu.sla(&cpu.bc.bit8.b);
        },
        0x21 => {
            cpu.sla(&cpu.bc.bit8.c);
        },
        0x22 => {
            cpu.sla(&cpu.de.bit8.d);
        },
        0x23 => {
            cpu.sla(&cpu.de.bit8.e);
        },
        0x24 => {
            cpu.sla(&cpu.hl.bit8.h);
        },
        0x25 => {
            cpu.sla(&cpu.hl.bit8.l);
        },
        0x26 => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.sla(&value);
            memory.write8(cpu.hl.bit16, value);
        },
        0x27 => {
            cpu.sla(&cpu.af.bit8.a);
        },

        0x28 => {
            cpu.sra(&cpu.bc.bit8.b);
        },
        0x29 => {
            cpu.sra(&cpu.bc.bit8.c);
        },
        0x2A => {
            cpu.sra(&cpu.de.bit8.d);
        },
        0x2B => {
            cpu.sra(&cpu.de.bit8.e);
        },
        0x2C => {
            cpu.sra(&cpu.hl.bit8.h);
        },
        0x2D => {
            cpu.sra(&cpu.hl.bit8.l);
        },
        0x2E => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.sra(&value);
            memory.write8(cpu.hl.bit16, value);
        },
        0x2F => {
            cpu.sra(&cpu.af.bit8.a);
        },

        0x30 => {
            cpu.swap(&cpu.bc.bit8.b);
        },
        0x31 => {
            cpu.swap(&cpu.bc.bit8.c);
        },
        0x32 => {
            cpu.swap(&cpu.de.bit8.d);
        },
        0x33 => {
            cpu.swap(&cpu.de.bit8.e);
        },
        0x34 => {
            cpu.swap(&cpu.hl.bit8.h);
        },
        0x35 => {
            cpu.swap(&cpu.hl.bit8.l);
        },
        0x36 => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.swap(&value);
            memory.write8(cpu.hl.bit16, value);
        },
        0x37 => {
            cpu.swap(&cpu.af.bit8.a);
        },

        0x38 => {
            cpu.srl(&cpu.bc.bit8.b);
        },
        0x39 => {
            cpu.srl(&cpu.bc.bit8.c);
        },
        0x3A => {
            cpu.srl(&cpu.de.bit8.d);
        },
        0x3B => {
            cpu.srl(&cpu.de.bit8.e);
        },
        0x3C => {
            cpu.srl(&cpu.hl.bit8.h);
        },
        0x3D => {
            cpu.srl(&cpu.hl.bit8.l);
        },
        0x3E => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.srl(&value);
            memory.write8(cpu.hl.bit16, value);
        },
        0x3F => {
            cpu.srl(&cpu.af.bit8.a);
        },

        0x40 => {
            cpu.bit(0, cpu.bc.bit8.b);
        },
        0x41 => {
            cpu.bit(0, cpu.bc.bit8.c);
        },
        0x42 => {
            cpu.bit(0, cpu.de.bit8.d);
        },
        0x43 => {
            cpu.bit(0, cpu.de.bit8.e);
        },
        0x44 => {
            cpu.bit(0, cpu.hl.bit8.h);
        },
        0x45 => {
            cpu.bit(0, cpu.hl.bit8.l);
        },
        0x46 => {
            cpu.bit(0, memory.read8(cpu.hl.bit16));
        },
        0x47 => {
            cpu.bit(0, cpu.af.bit8.a);
        },

        0x48 => {
            cpu.bit(1, cpu.bc.bit8.b);
        },
        0x49 => {
            cpu.bit(1, cpu.bc.bit8.c);
        },
        0x4A => {
            cpu.bit(1, cpu.de.bit8.d);
        },
        0x4B => {
            cpu.bit(1, cpu.de.bit8.e);
        },
        0x4C => {
            cpu.bit(1, cpu.hl.bit8.h);
        },
        0x4D => {
            cpu.bit(1, cpu.hl.bit8.l);
        },
        0x4E => {
            cpu.bit(1, memory.read8(cpu.hl.bit16));
        },
        0x4F => {
            cpu.bit(1, cpu.af.bit8.a);
        },

        0x50 => {
            cpu.bit(2, cpu.bc.bit8.b);
        },
        0x51 => {
            cpu.bit(2, cpu.bc.bit8.c);
        },
        0x52 => {
            cpu.bit(2, cpu.de.bit8.d);
        },
        0x53 => {
            cpu.bit(2, cpu.de.bit8.e);
        },
        0x54 => {
            cpu.bit(2, cpu.hl.bit8.h);
        },
        0x55 => {
            cpu.bit(2, cpu.hl.bit8.l);
        },
        0x56 => {
            cpu.bit(2, memory.read8(cpu.hl.bit16));
        },
        0x57 => {
            cpu.bit(2, cpu.af.bit8.a);
        },

        0x58 => {
            cpu.bit(3, cpu.bc.bit8.b);
        },
        0x59 => {
            cpu.bit(3, cpu.bc.bit8.c);
        },
        0x5A => {
            cpu.bit(3, cpu.de.bit8.d);
        },
        0x5B => {
            cpu.bit(3, cpu.de.bit8.e);
        },
        0x5C => {
            cpu.bit(3, cpu.hl.bit8.h);
        },
        0x5D => {
            cpu.bit(3, cpu.hl.bit8.l);
        },
        0x5E => {
            cpu.bit(3, memory.read8(cpu.hl.bit16));
        },
        0x5F => {
            cpu.bit(3, cpu.af.bit8.a);
        },

        0x60 => {
            cpu.bit(4, cpu.bc.bit8.b);
        },
        0x61 => {
            cpu.bit(4, cpu.bc.bit8.c);
        },
        0x62 => {
            cpu.bit(4, cpu.de.bit8.d);
        },
        0x63 => {
            cpu.bit(4, cpu.de.bit8.e);
        },
        0x64 => {
            cpu.bit(4, cpu.hl.bit8.h);
        },
        0x65 => {
            cpu.bit(4, cpu.hl.bit8.l);
        },
        0x66 => {
            cpu.bit(4, memory.read8(cpu.hl.bit16));
        },
        0x67 => {
            cpu.bit(4, cpu.af.bit8.a);
        },

        0x68 => {
            cpu.bit(5, cpu.bc.bit8.b);
        },
        0x69 => {
            cpu.bit(5, cpu.bc.bit8.c);
        },
        0x6A => {
            cpu.bit(5, cpu.de.bit8.d);
        },
        0x6B => {
            cpu.bit(5, cpu.de.bit8.e);
        },
        0x6C => {
            cpu.bit(5, cpu.hl.bit8.h);
        },
        0x6D => {
            cpu.bit(5, cpu.hl.bit8.l);
        },
        0x6E => {
            cpu.bit(5, memory.read8(cpu.hl.bit16));
        },
        0x6F => {
            cpu.bit(5, cpu.af.bit8.a);
        },

        0x70 => {
            cpu.bit(6, cpu.bc.bit8.b);
        },
        0x71 => {
            cpu.bit(6, cpu.bc.bit8.c);
        },
        0x72 => {
            cpu.bit(6, cpu.de.bit8.d);
        },
        0x73 => {
            cpu.bit(6, cpu.de.bit8.e);
        },
        0x74 => {
            cpu.bit(6, cpu.hl.bit8.h);
        },
        0x75 => {
            cpu.bit(6, cpu.hl.bit8.l);
        },
        0x76 => {
            cpu.bit(6, memory.read8(cpu.hl.bit16));
        },
        0x77 => {
            cpu.bit(6, cpu.af.bit8.a);
        },

        0x78 => {
            cpu.bit(7, cpu.bc.bit8.b);
        },
        0x79 => {
            cpu.bit(7, cpu.bc.bit8.c);
        },
        0x7A => {
            cpu.bit(7, cpu.de.bit8.d);
        },
        0x7B => {
            cpu.bit(7, cpu.de.bit8.e);
        },
        0x7C => {
            cpu.bit(7, cpu.hl.bit8.h);
        },
        0x7D => {
            cpu.bit(7, cpu.hl.bit8.l);
        },
        0x7E => {
            cpu.bit(7, memory.read8(cpu.hl.bit16));
        },
        0x7F => {
            cpu.bit(7, cpu.af.bit8.a);
        },

        0x80 => {
            cpu.res(0, &cpu.bc.bit8.b);
        },
        0x81 => {
            cpu.res(0, &cpu.bc.bit8.c);
        },
        0x82 => {
            cpu.res(0, &cpu.de.bit8.d);
        },
        0x83 => {
            cpu.res(0, &cpu.de.bit8.e);
        },
        0x84 => {
            cpu.res(0, &cpu.hl.bit8.h);
        },
        0x85 => {
            cpu.res(0, &cpu.hl.bit8.l);
        },
        0x86 => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.res(0, &value);
            memory.write8(cpu.hl.bit16, value);
        },
        0x87 => {
            cpu.res(0, &cpu.af.bit8.a);
        },

        0x88 => {
            cpu.res(1, &cpu.bc.bit8.b);
        },
        0x89 => {
            cpu.res(1, &cpu.bc.bit8.c);
        },
        0x8A => {
            cpu.res(1, &cpu.de.bit8.d);
        },
        0x8B => {
            cpu.res(1, &cpu.de.bit8.e);
        },
        0x8C => {
            cpu.res(1, &cpu.hl.bit8.h);
        },
        0x8D => {
            cpu.res(1, &cpu.hl.bit8.l);
        },
        0x8E => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.res(1, &value);
            memory.write8(cpu.hl.bit16, value);
        },
        0x8F => {
            cpu.res(1, &cpu.af.bit8.a);
        },

        0x90 => {
            cpu.res(2, &cpu.bc.bit8.b);
        },
        0x91 => {
            cpu.res(2, &cpu.bc.bit8.c);
        },
        0x92 => {
            cpu.res(2, &cpu.de.bit8.d);
        },
        0x93 => {
            cpu.res(2, &cpu.de.bit8.e);
        },
        0x94 => {
            cpu.res(2, &cpu.hl.bit8.h);
        },
        0x95 => {
            cpu.res(2, &cpu.hl.bit8.l);
        },
        0x96 => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.res(2, &value);
            memory.write8(cpu.hl.bit16, value);
        },
        0x97 => {
            cpu.res(2, &cpu.af.bit8.a);
        },

        0x98 => {
            cpu.res(3, &cpu.bc.bit8.b);
        },
        0x99 => {
            cpu.res(3, &cpu.bc.bit8.c);
        },
        0x9A => {
            cpu.res(3, &cpu.de.bit8.d);
        },
        0x9B => {
            cpu.res(3, &cpu.de.bit8.e);
        },
        0x9C => {
            cpu.res(3, &cpu.hl.bit8.h);
        },
        0x9D => {
            cpu.res(3, &cpu.hl.bit8.l);
        },
        0x9E => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.res(3, &value);
            memory.write8(cpu.hl.bit16, value);
        },
        0x9F => {
            cpu.res(3, &cpu.af.bit8.a);
        },

        0xA0 => {
            cpu.res(4, &cpu.bc.bit8.b);
        },
        0xA1 => {
            cpu.res(4, &cpu.bc.bit8.c);
        },
        0xA2 => {
            cpu.res(4, &cpu.de.bit8.d);
        },
        0xA3 => {
            cpu.res(4, &cpu.de.bit8.e);
        },
        0xA4 => {
            cpu.res(4, &cpu.hl.bit8.h);
        },
        0xA5 => {
            cpu.res(4, &cpu.hl.bit8.l);
        },
        0xA6 => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.res(4, &value);
            memory.write8(cpu.hl.bit16, value);
        },
        0xA7 => {
            cpu.res(4, &cpu.af.bit8.a);
        },

        0xA8 => {
            cpu.res(5, &cpu.bc.bit8.b);
        },
        0xA9 => {
            cpu.res(5, &cpu.bc.bit8.c);
        },
        0xAA => {
            cpu.res(5, &cpu.de.bit8.d);
        },
        0xAB => {
            cpu.res(5, &cpu.de.bit8.e);
        },
        0xAC => {
            cpu.res(5, &cpu.hl.bit8.h);
        },
        0xAD => {
            cpu.res(5, &cpu.hl.bit8.l);
        },
        0xAE => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.res(5, &value);
            memory.write8(cpu.hl.bit16, value);
        },
        0xAF => {
            cpu.res(5, &cpu.af.bit8.a);
        },

        0xB0 => {
            cpu.res(6, &cpu.bc.bit8.b);
        },
        0xB1 => {
            cpu.res(6, &cpu.bc.bit8.c);
        },
        0xB2 => {
            cpu.res(6, &cpu.de.bit8.d);
        },
        0xB3 => {
            cpu.res(6, &cpu.de.bit8.e);
        },
        0xB4 => {
            cpu.res(6, &cpu.hl.bit8.h);
        },
        0xB5 => {
            cpu.res(6, &cpu.hl.bit8.l);
        },
        0xB6 => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.res(6, &value);
            memory.write8(cpu.hl.bit16, value);
        },
        0xB7 => {
            cpu.res(6, &cpu.af.bit8.a);
        },

        0xB8 => {
            cpu.res(7, &cpu.bc.bit8.b);
        },
        0xB9 => {
            cpu.res(7, &cpu.bc.bit8.c);
        },
        0xBA => {
            cpu.res(7, &cpu.de.bit8.d);
        },
        0xBB => {
            cpu.res(7, &cpu.de.bit8.e);
        },
        0xBC => {
            cpu.res(7, &cpu.hl.bit8.h);
        },
        0xBD => {
            cpu.res(7, &cpu.hl.bit8.l);
        },
        0xBE => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.res(7, &value);
            memory.write8(cpu.hl.bit16, value);
        },
        0xBF => {
            cpu.res(7, &cpu.af.bit8.a);
        },

        0xC0 => {
            cpu.set(0, &cpu.bc.bit8.b);
        },
        0xC1 => {
            cpu.set(0, &cpu.bc.bit8.c);
        },
        0xC2 => {
            cpu.set(0, &cpu.de.bit8.d);
        },
        0xC3 => {
            cpu.set(0, &cpu.de.bit8.e);
        },
        0xC4 => {
            cpu.set(0, &cpu.hl.bit8.h);
        },
        0xC5 => {
            cpu.set(0, &cpu.hl.bit8.l);
        },
        0xC6 => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.set(0, &value);
            memory.write8(cpu.hl.bit16, value);
        },
        0xC7 => {
            cpu.set(0, &cpu.af.bit8.a);
        },

        0xC8 => {
            cpu.set(1, &cpu.bc.bit8.b);
        },
        0xC9 => {
            cpu.set(1, &cpu.bc.bit8.c);
        },
        0xCA => {
            cpu.set(1, &cpu.de.bit8.d);
        },
        0xCB => {
            cpu.set(1, &cpu.de.bit8.e);
        },
        0xCC => {
            cpu.set(1, &cpu.hl.bit8.h);
        },
        0xCD => {
            cpu.set(1, &cpu.hl.bit8.l);
        },
        0xCE => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.set(1, &value);
            memory.write8(cpu.hl.bit16, value);
        },
        0xCF => {
            cpu.set(1, &cpu.af.bit8.a);
        },

        0xD0 => {
            cpu.set(2, &cpu.bc.bit8.b);
        },
        0xD1 => {
            cpu.set(2, &cpu.bc.bit8.c);
        },
        0xD2 => {
            cpu.set(2, &cpu.de.bit8.d);
        },
        0xD3 => {
            cpu.set(2, &cpu.de.bit8.e);
        },
        0xD4 => {
            cpu.set(2, &cpu.hl.bit8.h);
        },
        0xD5 => {
            cpu.set(2, &cpu.hl.bit8.l);
        },
        0xD6 => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.set(2, &value);
            memory.write8(cpu.hl.bit16, value);
        },
        0xD7 => {
            cpu.set(2, &cpu.af.bit8.a);
        },

        0xD8 => {
            cpu.set(3, &cpu.bc.bit8.b);
        },
        0xD9 => {
            cpu.set(3, &cpu.bc.bit8.c);
        },
        0xDA => {
            cpu.set(3, &cpu.de.bit8.d);
        },
        0xDB => {
            cpu.set(3, &cpu.de.bit8.e);
        },
        0xDC => {
            cpu.set(3, &cpu.hl.bit8.h);
        },
        0xDD => {
            cpu.set(3, &cpu.hl.bit8.l);
        },
        0xDE => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.set(3, &value);
            memory.write8(cpu.hl.bit16, value);
        },
        0xDF => {
            cpu.set(3, &cpu.af.bit8.a);
        },

        0xE0 => {
            cpu.set(4, &cpu.bc.bit8.b);
        },
        0xE1 => {
            cpu.set(4, &cpu.bc.bit8.c);
        },
        0xE2 => {
            cpu.set(4, &cpu.de.bit8.d);
        },
        0xE3 => {
            cpu.set(4, &cpu.de.bit8.e);
        },
        0xE4 => {
            cpu.set(4, &cpu.hl.bit8.h);
        },
        0xE5 => {
            cpu.set(4, &cpu.hl.bit8.l);
        },
        0xE6 => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.set(4, &value);
            memory.write8(cpu.hl.bit16, value);
        },
        0xE7 => {
            cpu.set(4, &cpu.af.bit8.a);
        },

        0xE8 => {
            cpu.set(5, &cpu.bc.bit8.b);
        },
        0xE9 => {
            cpu.set(5, &cpu.bc.bit8.c);
        },
        0xEA => {
            cpu.set(5, &cpu.de.bit8.d);
        },
        0xEB => {
            cpu.set(5, &cpu.de.bit8.e);
        },
        0xEC => {
            cpu.set(5, &cpu.hl.bit8.h);
        },
        0xED => {
            cpu.set(5, &cpu.hl.bit8.l);
        },
        0xEE => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.set(5, &value);
            memory.write8(cpu.hl.bit16, value);
        },
        0xEF => {
            cpu.set(5, &cpu.af.bit8.a);
        },

        0xF0 => {
            cpu.set(6, &cpu.bc.bit8.b);
        },
        0xF1 => {
            cpu.set(6, &cpu.bc.bit8.c);
        },
        0xF2 => {
            cpu.set(6, &cpu.de.bit8.d);
        },
        0xF3 => {
            cpu.set(6, &cpu.de.bit8.e);
        },
        0xF4 => {
            cpu.set(6, &cpu.hl.bit8.h);
        },
        0xF5 => {
            cpu.set(6, &cpu.hl.bit8.l);
        },
        0xF6 => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.set(6, &value);
            memory.write8(cpu.hl.bit16, value);
        },
        0xF7 => {
            cpu.set(6, &cpu.af.bit8.a);
        },

        0xF8 => {
            cpu.set(7, &cpu.bc.bit8.b);
        },
        0xF9 => {
            cpu.set(7, &cpu.bc.bit8.c);
        },
        0xFA => {
            cpu.set(7, &cpu.de.bit8.d);
        },
        0xFB => {
            cpu.set(7, &cpu.de.bit8.e);
        },
        0xFC => {
            cpu.set(7, &cpu.hl.bit8.h);
        },
        0xFD => {
            cpu.set(7, &cpu.hl.bit8.l);
        },
        0xFE => {
            var value = memory.read8(cpu.hl.bit16);
            cpu.set(7, &value);
            memory.write8(cpu.hl.bit16, value);
        },
        0xFF => {
            cpu.set(7, &cpu.af.bit8.a);
        },
    }
}
