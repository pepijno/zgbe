const CPU = @This();

const std = @import("std");
const Bus = @import("Bus.zig");
const Interrupt = @import("Interrupt.zig");

fn bitSet(value: u8, bit: u3) bool {
    return (value & (@as(u8, 1) << bit)) != 0;
}

fn Register(comptime lsb: [:0]const u8, comptime msb: [:0]const u8) type {
    const struct_type = @Type(.{ .Struct = .{
        .layout = .@"packed",
        .backing_integer = u16,
        .fields = &.{
            .{
                .name = lsb,
                .type = u8,
                .default_value = null,
                .is_comptime = false,
                .alignment = 0,
            },
            .{
                .name = msb,
                .type = u8,
                .default_value = null,
                .is_comptime = false,
                .alignment = 0,
            },
        },
        .decls = &.{},
        .is_tuple = false,
    } });

    return packed union {
        bit8: struct_type,
        bit16: u16,
    };
}

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
bc: Register("c", "b"),
de: Register("e", "d"),
hl: Register("l", "h"),
wz: Register("z", "w"),

stack_pointer: Register("lsb", "msb"),
program_counter: Register("lsb", "msb"),

instruction_queue: []const []const QueueItem = &.{},

halted: bool = false,
running: bool = false,
interrupts_enabled: bool = false,
enable_interrupts: bool = false,

const AsMemoryLocation = enum(u1) {
    True,
    False,
};

const Location8 = union(enum) {
    A,
    F,
    B,
    C,
    D,
    E,
    H,
    L,
    W,
    Z,
    lsb_sp,
    msb_sp,
    lsb_pc,
    msb_pc,
};
const Location16 = union(enum) {
    AF,
    BC,
    DE,
    HL,
    WZ,
    PC,
    SP,
};

const QueueItem = union(enum) {
    NOP,
    READ_8: struct { address: Location16, to: Location8 },
    READ_8_HIGH: struct { address: Location8, to: Location8 },
    INC_REG_8: Location8,
    INC_REG_16: Location16,
    DEC_REG_8: Location8,
    DEC_REG_16: Location16,
    ASSIGN_8: struct { from: Location8, to: Location8 },
    ASSIGN_16: struct { from: Location16, to: Location16 },
    WRITE_8: struct { value: Location8, address: Location16 },
    WRITE_8_HIGH: struct { value: Location8, address: Location8 },

    SET_PC: u16,

    ADD: struct { value: Location8, to: Location8 },
    ADD_CARRY: struct { value: Location8, to: Location8 },
    ADD_SP: Location8,
    ADD_SP_CARRY: Location8,
    ADD_SP_HL: Location8,
    ADD_SP_HL_CARRY: Location8,
    ADD_A: Location8,
    SUB: Location8,
    ADC: Location8,
    SBC: Location8,
    OR: Location8,
    AND: Location8,
    XOR: Location8,
    CP: Location8,

    CHECK_ZERO,
    CHECK_NOT_ZERO,
    CHECK_CARRY,
    CHECK_NOT_CARRY,

    STOP,
    HALT,
    DISABLE_INTERRUPTS,
    ENABLE_INTERRUPTS_IMMEDIATE,
    ENABLE_INTERRUPTS,
    JUMP_RELATIVE: Location8,

    RLCA,
    RRCA,
    RLA,
    RRA,
    DAA,
    CPL,
    SCF,
    CCF,

    PREFIX: Location8,

    // Prefix instructions
    RLC: Location8,
    RRC: Location8,
    RL: Location8,
    RR: Location8,
    SLA: Location8,
    SRA: Location8,
    SWAP: Location8,
    SRL: Location8,
    BIT: struct { register: Location8, bit: u3 },
    RES: struct { register: Location8, bit: u3 },
    SET: struct { register: Location8, bit: u3 },
};

pub fn initBeforeBoot() CPU {
    return .{
        .af = .{ .bit16 = 0 },
        .bc = .{ .bit16 = 0 },
        .de = .{ .bit16 = 0 },
        .hl = .{ .bit16 = 0 },
        .wz = .{ .bit16 = 0x0000 },
        .stack_pointer = .{ .bit16 = 0 },
        .program_counter = .{ .bit16 = 0 },
        .interrupts_enabled = false,
    };
}

pub fn initAfterBoot() CPU {
    return .{
        .af = .{ .bit16 = 0x01B0 },
        .bc = .{ .bit16 = 0x0013 },
        .de = .{ .bit16 = 0x00D8 },
        .hl = .{ .bit16 = 0x014D },
        .wz = .{ .bit16 = 0x0000 },
        .stack_pointer = .{ .bit16 = 0xFFFE },
        .program_counter = .{ .bit16 = 0x100 },
        .interrupts_enabled = false,
    };
}

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
    try writer.print("A:{X:0>2} F:{X:0>2} B:{X:0>2} C:{X:0>2} D:{X:0>2} E:{X:0>2} H:{X:0>2} L:{X:0>2} SP:{X:0>4} PC:{X:0>4} PCMEM:{X:0>2},{X:0>2},{X:0>2},{X:0>2} ({s})", .{
        cpu.af.bit8.a,
        flags,
        cpu.bc.bit8.b,
        cpu.bc.bit8.c,
        cpu.de.bit8.d,
        cpu.de.bit8.e,
        cpu.hl.bit8.h,
        cpu.hl.bit8.l,
        cpu.stack_pointer.bit16,
        cpu.program_counter.bit16,
        bus.read(cpu.program_counter.bit16),
        bus.read(cpu.program_counter.bit16 + 1),
        bus.read(cpu.program_counter.bit16 + 2),
        bus.read(cpu.program_counter.bit16 + 3),
        instStrs[bus.read(cpu.program_counter.bit16)],
    });

    if (comptime false) {
        try writer.print(" STACK:{X:0>2},{X:0>2},{X:0>2},{X:0>2} SP:{X:0>2},{X:0>2}", .{
            if (cpu.stack_pointer.bit16 < 0xFFFF) bus.read(cpu.stack_pointer.bit16) else 0,
            if (@as(u32, cpu.stack_pointer.bit16) + 1 < 0xFFFF) bus.read(cpu.stack_pointer.bit16 + 1) else 0,
            if (@as(u32, cpu.stack_pointer.bit16) + 2 < 0xFFFF) bus.read(cpu.stack_pointer.bit16 + 2) else 0,
            if (@as(u32, cpu.stack_pointer.bit16) + 3 < 0xFFFF) bus.read(cpu.stack_pointer.bit16 + 3) else 0,
            cpu.stack_pointer.bit8.msb,
            cpu.stack_pointer.bit8.lsb,
        });
    }

    try writer.print("\n", .{});
}

pub fn maybeHandleInterrupts(cpu: *CPU, bus: *Bus) bool {
    var flags: Interrupt.InterruptFlags = @bitCast(bus.read(0xFF0F));
    const enabled: Interrupt.InterruptFlags = @bitCast(bus.read(0xFFFF));

    if ((flags.bit8 & enabled.bit8) == 0) {
        return false;
    }

    cpu.halted = false;

    if (!cpu.interrupts_enabled) {
        return false;
    }

    cpu.interrupts_enabled = false;
    cpu.enable_interrupts = false;

    const enabled_flags = Interrupt.InterruptFlags{ .bit8 = flags.bit8 & enabled.bit8 };
    if (enabled_flags.as_flags.vblank) {
        cpu.instruction_queue = &vblankInstructions;
        flags.as_flags.vblank = false;
    } else if (enabled_flags.as_flags.lcd) {
        cpu.instruction_queue = &lcdInstructions;
        flags.as_flags.lcd = false;
    } else if (enabled_flags.as_flags.timer) {
        cpu.instruction_queue = &timerInstructions;
        flags.as_flags.timer = false;
    } else if (enabled_flags.as_flags.serial) {
        cpu.instruction_queue = &serialInstructions;
        flags.as_flags.serial = false;
    } else if (enabled_flags.as_flags.joypad) {
        cpu.instruction_queue = &joypadInstructions;
        flags.as_flags.joypad = false;
    }
    bus.write(0xFF0F, flags.bit8);

    return true;
}

const vblankInstructions: [5][]const QueueItem = .{
    &.{},
    &.{},
    &.{ .{ .DEC_REG_16 = .SP }, .{ .WRITE_8 = .{ .value = .msb_pc, .address = .SP } } },
    &.{ .{ .DEC_REG_16 = .SP }, .{ .WRITE_8 = .{ .value = .lsb_pc, .address = .SP } } },
    &.{.{ .SET_PC = 0x0040 }},
};

const lcdInstructions: [5][]const QueueItem = .{
    &.{},
    &.{},
    &.{ .{ .DEC_REG_16 = .SP }, .{ .WRITE_8 = .{ .value = .msb_pc, .address = .SP } } },
    &.{ .{ .DEC_REG_16 = .SP }, .{ .WRITE_8 = .{ .value = .lsb_pc, .address = .SP } } },
    &.{.{ .SET_PC = 0x0048 }},
};

const timerInstructions: [5][]const QueueItem = .{
    &.{},
    &.{},
    &.{ .{ .DEC_REG_16 = .SP }, .{ .WRITE_8 = .{ .value = .msb_pc, .address = .SP } } },
    &.{ .{ .DEC_REG_16 = .SP }, .{ .WRITE_8 = .{ .value = .lsb_pc, .address = .SP } } },
    &.{.{ .SET_PC = 0x0050 }},
};

const serialInstructions: [5][]const QueueItem = .{
    &.{},
    &.{},
    &.{ .{ .DEC_REG_16 = .SP }, .{ .WRITE_8 = .{ .value = .msb_pc, .address = .SP } } },
    &.{ .{ .DEC_REG_16 = .SP }, .{ .WRITE_8 = .{ .value = .lsb_pc, .address = .SP } } },
    &.{.{ .SET_PC = 0x0058 }},
};

const joypadInstructions: [5][]const QueueItem = .{
    &.{},
    &.{},
    &.{ .{ .DEC_REG_16 = .SP }, .{ .WRITE_8 = .{ .value = .msb_pc, .address = .SP } } },
    &.{ .{ .DEC_REG_16 = .SP }, .{ .WRITE_8 = .{ .value = .lsb_pc, .address = .SP } } },
    &.{.{ .SET_PC = 0x0060 }},
};

pub fn tick(cpu: *CPU, bus: *Bus) void {
    if (cpu.halted) {
        if (bus.read(0xFF0F) != 0) {
            cpu.halted = false;
        }
    } else {
        if (cpu.instruction_queue.len == 0) {
            const opcode = bus.read(cpu.program_counter.bit16);
            cpu.program_counter.bit16 += 1;
            cpu.instruction_queue = getInstructions(bus, opcode);
        }

        const instructions = cpu.instruction_queue[0];
        cpu.instruction_queue = cpu.instruction_queue[1..];
        for (instructions) |item| {
            cpu.executeInstruction(bus, item);
        }
    }

    if (cpu.instruction_queue.len == 0) {
        if (cpu.interrupts_enabled) {
            _ = cpu.maybeHandleInterrupts(bus);
            cpu.enable_interrupts = false;
        }

        if (cpu.enable_interrupts) {
            cpu.interrupts_enabled = true;
        }
    }
}

fn register8Value(cpu: *CPU, location: Location8) *u8 {
    return switch (location) {
        .A => &cpu.af.bit8.a,
        .F => @ptrCast(&cpu.af.bit8._padding),
        .B => &cpu.bc.bit8.b,
        .C => &cpu.bc.bit8.c,
        .D => &cpu.de.bit8.d,
        .E => &cpu.de.bit8.e,
        .H => &cpu.hl.bit8.h,
        .L => &cpu.hl.bit8.l,
        .W => &cpu.wz.bit8.w,
        .Z => &cpu.wz.bit8.z,
        .lsb_sp => &cpu.stack_pointer.bit8.lsb,
        .msb_sp => &cpu.stack_pointer.bit8.msb,
        .lsb_pc => &cpu.program_counter.bit8.lsb,
        .msb_pc => &cpu.program_counter.bit8.msb,
    };
}

fn register16Value(cpu: *CPU, location: Location16) *u16 {
    return switch (location) {
        .AF => &cpu.af.bit16,
        .BC => &cpu.bc.bit16,
        .DE => &cpu.de.bit16,
        .HL => &cpu.hl.bit16,
        .WZ => &cpu.wz.bit16,
        .PC => &cpu.program_counter.bit16,
        .SP => &cpu.stack_pointer.bit16,
    };
}

fn executeInstruction(cpu: *CPU, bus: *Bus, item: QueueItem) void {
    switch (item) {
        .NOP => {},
        .READ_8 => |loc| {
            const address = cpu.register16Value(loc.address).*;
            const value = bus.read(address);
            cpu.register8Value(loc.to).* = value;
        },
        .READ_8_HIGH => |loc| {
            const address = 0xFF00 + @as(u16, cpu.register8Value(loc.address).*);
            const value = bus.read(address);
            cpu.register8Value(loc.to).* = value;
        },
        .INC_REG_8 => |loc| {
            const value = cpu.register8Value(loc);
            cpu.incRegister(value);
        },
        .INC_REG_16 => |loc| {
            const value = cpu.register16Value(loc);
            value.* +%= 1;
        },
        .DEC_REG_8 => |loc| {
            const value = cpu.register8Value(loc);
            cpu.decRegister(value);
        },
        .DEC_REG_16 => |loc| {
            const value = cpu.register16Value(loc);
            value.* -%= 1;
        },
        .ASSIGN_8 => |loc| {
            const value = cpu.register8Value(loc.from).*;
            cpu.register8Value(loc.to).* = value;
        },
        .ASSIGN_16 => |loc| {
            var value = cpu.register16Value(loc.from).*;
            if (loc.to == .AF) {
                value &= 0xFFF0;
            }
            cpu.register16Value(loc.to).* = value;
        },
        .WRITE_8 => |data| {
            var value = cpu.register8Value(data.value).*;
            if (data.value == .F) {
                value &= 0xF0;
            }
            const address = cpu.register16Value(data.address).*;
            bus.write(address, value);
        },
        .WRITE_8_HIGH => |data| {
            const value = cpu.register8Value(data.value).*;
            const address: u16 = 0xFF00 + @as(u16, cpu.register8Value(data.address).*);
            bus.write(address, value);
        },
        .SET_PC => |value| {
            cpu.program_counter.bit16 = value;
        },
        .ADD => |data| {
            const left = cpu.register8Value(data.to).*;
            const right = cpu.register8Value(data.value).*;
            const value = @as(u16, left) + @as(u16, right);
            cpu.register8Value(data.to).* = @truncate(value & 0xFF);
            cpu.af.bit8.subtraction_flag = false;
            cpu.af.bit8.half_carry_flag = ((left & 0xF) + (right & 0xF)) > 0xF;
            cpu.af.bit8.carry_flag = value > 0x00FF;
        },
        .ADD_CARRY => |data| {
            const left = cpu.register8Value(data.to).*;
            const right = cpu.register8Value(data.value).*;
            const carry_bit = @as(u8, @intFromBool(cpu.af.bit8.carry_flag));
            const result = @as(u16, left) + @as(u16, right) + @as(u16, carry_bit);

            cpu.af.bit8.carry_flag = result > 0x00FF;
            cpu.af.bit8.half_carry_flag = ((left & 0xF) + (right & 0xF) + carry_bit) > 0xF;
            cpu.af.bit8.subtraction_flag = false;

            cpu.register8Value(data.to).* = @truncate(result & 0xFF);
        },
        .ADD_SP_HL => |loc| {
            const left = cpu.stack_pointer.bit8.lsb;
            const right = cpu.register8Value(loc).*;
            const value = @as(u16, left) + @as(u16, right);
            cpu.hl.bit8.l = @truncate(value & 0xFF);
            cpu.af.bit8.zero_flag = false;
            cpu.af.bit8.subtraction_flag = false;
            cpu.af.bit8.half_carry_flag = ((left & 0xF) + (right & 0xF)) > 0xF;
            cpu.af.bit8.carry_flag = value > 0x00FF;
        },
        .ADD_SP_HL_CARRY => |loc| {
            const left = cpu.stack_pointer.bit8.msb;
            const value = cpu.register8Value(loc).*;
            const adj: u8 = if (bitSet(value, 7)) 0xFF else 0x00;
            const carry_bit = @as(u8, @intFromBool(cpu.af.bit8.carry_flag));
            const result = left +% adj +% carry_bit;
            cpu.hl.bit8.h = result;
        },
        .ADD_SP => |loc| {
            const left = cpu.stack_pointer.bit8.lsb;
            const right = cpu.register8Value(loc).*;
            const value = @as(u16, left) + @as(u16, right);
            cpu.stack_pointer.bit8.lsb = @truncate(value & 0xFF);
            cpu.af.bit8.zero_flag = false;
            cpu.af.bit8.subtraction_flag = false;
            cpu.af.bit8.half_carry_flag = ((left & 0xF) + (right & 0xF)) > 0xF;
            cpu.af.bit8.carry_flag = value > 0x00FF;
        },
        .ADD_SP_CARRY => |loc| {
            const left = cpu.stack_pointer.bit8.msb;
            const value = cpu.register8Value(loc).*;
            const adj: u8 = if (bitSet(value, 7)) 0xFF else 0x00;
            const carry_bit = @as(u8, @intFromBool(cpu.af.bit8.carry_flag));
            const result = left +% adj +% carry_bit;
            cpu.stack_pointer.bit8.msb = result;
        },
        .ADD_A => |loc| {
            const value = cpu.register8Value(loc).*;
            cpu.adda(value);
        },
        .SUB => |loc| {
            const value = cpu.register8Value(loc).*;
            cpu.suba(value);
        },
        .RLCA => {
            const carry = (cpu.af.bit8.a & 0x80) >> 7;
            cpu.af.bit8.carry_flag = carry != 0;

            cpu.af.bit8.a = cpu.af.bit8.a << 1;
            cpu.af.bit8.a |= carry;

            cpu.af.bit8.zero_flag = false;
            cpu.af.bit8.subtraction_flag = false;
            cpu.af.bit8.half_carry_flag = false;
        },
        .RRCA => {
            const carry = cpu.af.bit8.a & 0x1;
            cpu.af.bit8.carry_flag = carry != 0;

            cpu.af.bit8.a = cpu.af.bit8.a >> 1;
            if (carry != 0) cpu.af.bit8.a |= 0x80;

            cpu.af.bit8.zero_flag = false;
            cpu.af.bit8.subtraction_flag = false;
            cpu.af.bit8.half_carry_flag = false;
        },
        .RLA => {
            const carry: u8 = if (cpu.af.bit8.carry_flag) 1 else 0;
            cpu.af.bit8.carry_flag = (cpu.af.bit8.a & 0x80) != 0;

            cpu.af.bit8.a = cpu.af.bit8.a << 1;
            cpu.af.bit8.a +%= carry;

            cpu.af.bit8.half_carry_flag = false;
            cpu.af.bit8.subtraction_flag = false;
            cpu.af.bit8.zero_flag = false;
        },
        .RRA => {
            const carry: u8 = if (cpu.af.bit8.carry_flag) 1 else 0;

            cpu.af.bit8.carry_flag = (cpu.af.bit8.a & 0x01) != 0;
            cpu.af.bit8.a = cpu.af.bit8.a >> 1;
            cpu.af.bit8.a +%= (carry << 7);

            cpu.af.bit8.half_carry_flag = false;
            cpu.af.bit8.subtraction_flag = false;
            cpu.af.bit8.zero_flag = false;
        },
        .DAA => {
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
        .CPL => {
            cpu.af.bit8.a = ~cpu.af.bit8.a;
            cpu.af.bit8.half_carry_flag = true;
            cpu.af.bit8.subtraction_flag = true;
        },
        .SCF => {
            cpu.af.bit8.half_carry_flag = false;
            cpu.af.bit8.subtraction_flag = false;
            cpu.af.bit8.carry_flag = true;
        },
        .CCF => {
            cpu.af.bit8.carry_flag = !cpu.af.bit8.carry_flag;
            cpu.af.bit8.half_carry_flag = false;
            cpu.af.bit8.subtraction_flag = false;
        },
        .ADC => |loc| {
            const value = cpu.register8Value(loc).*;
            const carry_bit: u8 = @as(u8, @intFromBool(cpu.af.bit8.carry_flag));
            const result = @as(u16, cpu.af.bit8.a) + @as(u16, value) + @as(u16, carry_bit);

            cpu.af.bit8.carry_flag = (result & 0xFF00) != 0;
            cpu.af.bit8.half_carry_flag = ((cpu.af.bit8.a & 0xF) + (value & 0xF) + carry_bit) > 0xF;

            cpu.af.bit8.a = @truncate(result & 0xFF);

            cpu.af.bit8.zero_flag = cpu.af.bit8.a == 0;
            cpu.af.bit8.subtraction_flag = false;
        },
        .SBC => |loc| {
            const value = cpu.register8Value(loc).*;
            cpu.sbca(value);
        },
        .OR => |loc| {
            const value = cpu.register8Value(loc).*;
            cpu.ora(value);
        },
        .AND => |loc| {
            const value = cpu.register8Value(loc).*;
            cpu.anda(value);
        },
        .XOR => |loc| {
            const value = cpu.register8Value(loc).*;
            cpu.xora(value);
        },
        .CP => |loc| {
            const value = cpu.register8Value(loc).*;
            cpu.cpa(value);
        },
        .CHECK_ZERO => {
            if (!cpu.af.bit8.zero_flag) {
                cpu.instruction_queue = &.{&.{}};
            }
        },
        .CHECK_NOT_ZERO => {
            if (cpu.af.bit8.zero_flag) {
                cpu.instruction_queue = &.{&.{}};
            }
        },
        .CHECK_CARRY => {
            if (!cpu.af.bit8.carry_flag) {
                cpu.instruction_queue = &.{&.{}};
            }
        },
        .CHECK_NOT_CARRY => {
            if (cpu.af.bit8.carry_flag) {
                cpu.instruction_queue = &.{&.{}};
            }
        },
        .STOP => {
            // cpu.running = false;
        },
        .HALT => {
            cpu.halted = true;
        },
        .DISABLE_INTERRUPTS => {
            cpu.interrupts_enabled = false;
        },
        .ENABLE_INTERRUPTS_IMMEDIATE => {
            cpu.interrupts_enabled = true;
        },
        .ENABLE_INTERRUPTS => {
            cpu.enable_interrupts = true;
        },
        .JUMP_RELATIVE => |loc| {
            const value: i8 = @bitCast(cpu.register8Value(loc).*);
            if (value < 0) {
                cpu.program_counter.bit16 -%= @abs(value);
            } else {
                cpu.program_counter.bit16 +%= @abs(value);
            }
        },

        .PREFIX => |loc| {
            const value = cpu.register8Value(loc).*;
            const instructions = prefixInstruction(value);
            cpu.instruction_queue = instructions;
        },

        // Prefix instructions
        .RLC => |loc| {
            const reg_value = cpu.register8Value(loc);
            const carry: u8 = (reg_value.* & 0x80) >> 7;

            cpu.af.bit8.carry_flag = (reg_value.* & 0x80) != 0;

            reg_value.* = reg_value.* << 1;
            reg_value.* +%= carry;

            cpu.af.bit8.zero_flag = reg_value.* == 0;
            cpu.af.bit8.half_carry_flag = false;
            cpu.af.bit8.subtraction_flag = false;
        },
        .RRC => |loc| {
            const reg_value = cpu.register8Value(loc);
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
        .RL => |loc| {
            const reg_value = cpu.register8Value(loc);
            const carry: u8 = if (cpu.af.bit8.carry_flag) 1 else 0;

            cpu.af.bit8.carry_flag = (reg_value.* & 0x80) != 0;

            reg_value.* = reg_value.* << 1;
            reg_value.* +%= carry;

            cpu.af.bit8.zero_flag = reg_value.* == 0;
            cpu.af.bit8.half_carry_flag = false;
            cpu.af.bit8.subtraction_flag = false;
        },
        .RR => |loc| {
            const reg_value = cpu.register8Value(loc);
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
        .SLA => |loc| {
            const reg_value = cpu.register8Value(loc);
            cpu.af.bit8.carry_flag = (reg_value.* & 0x80) != 0;
            reg_value.* = reg_value.* << 1;
            cpu.af.bit8.zero_flag = reg_value.* == 0;
            cpu.af.bit8.half_carry_flag = false;
            cpu.af.bit8.subtraction_flag = false;
        },
        .SRA => |loc| {
            const reg_value = cpu.register8Value(loc);
            cpu.af.bit8.carry_flag = (reg_value.* & 0x1) != 0;
            reg_value.* = (reg_value.* >> 1) | (reg_value.* & 0x80);
            cpu.af.bit8.zero_flag = reg_value.* == 0;
            cpu.af.bit8.half_carry_flag = false;
            cpu.af.bit8.subtraction_flag = false;
        },
        .SWAP => |loc| {
            const reg_value = cpu.register8Value(loc);
            reg_value.* = ((reg_value.* & 0xF) << 4) | ((reg_value.* & 0xF0) >> 4);
            cpu.af.bit8.zero_flag = reg_value.* == 0;
            cpu.af.bit8.carry_flag = false;
            cpu.af.bit8.half_carry_flag = false;
            cpu.af.bit8.subtraction_flag = false;
        },
        .SRL => |loc| {
            const reg_value = cpu.register8Value(loc);
            cpu.af.bit8.carry_flag = (reg_value.* & 0x1) != 0;
            reg_value.* = reg_value.* >> 1;
            cpu.af.bit8.zero_flag = reg_value.* == 0;
            cpu.af.bit8.half_carry_flag = false;
            cpu.af.bit8.subtraction_flag = false;
        },
        .BIT => |loc| {
            const reg_value = cpu.register8Value(loc.register);
            cpu.af.bit8.zero_flag = (reg_value.* & (@as(u8, 1) << loc.bit)) == 0;
            cpu.af.bit8.half_carry_flag = true;
            cpu.af.bit8.subtraction_flag = false;
        },
        .RES => |loc| {
            const reg_value = cpu.register8Value(loc.register);
            reg_value.* &= ~(@as(u8, 1) << loc.bit);
        },
        .SET => |loc| {
            const reg_value = cpu.register8Value(loc.register);
            reg_value.* |= (@as(u8, 1) << loc.bit);
        },
    }
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

fn getInstructions(bus: *Bus, opcode: u8) []const []const QueueItem {
    _ = bus; // autofix
    return switch (opcode) {
        0x00 => &.{
            &.{.NOP},
        },
        0x01 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .W } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .ASSIGN_16 = .{ .from = .WZ, .to = .BC } }},
        },
        0x02 => &.{
            &.{.{ .WRITE_8 = .{ .value = .A, .address = .BC } }},
            &.{},
        },
        0x03 => &.{
            &.{.{ .INC_REG_16 = .BC }},
            &.{},
        },
        0x04 => &.{
            &.{.{ .INC_REG_8 = .B }},
        },
        0x05 => &.{
            &.{.{ .DEC_REG_8 = .B }},
        },
        0x06 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .B } }},
        },
        0x07 => &.{
            &.{.RLCA},
        },

        0x08 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .W } }, .{ .INC_REG_16 = .PC } },
            &.{ .{ .WRITE_8 = .{ .value = .lsb_sp, .address = .WZ } }, .{ .INC_REG_16 = .WZ } },
            &.{.{ .WRITE_8 = .{ .value = .msb_sp, .address = .WZ } }},
            &.{},
        },
        0x09 => &.{
            &.{.{ .ADD = .{ .value = .C, .to = .L } }},
            &.{.{ .ADD_CARRY = .{ .value = .B, .to = .H } }},
        },
        0x0A => &.{
            &.{.{ .READ_8 = .{ .address = .BC, .to = .Z } }},
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .A } }},
        },
        0x0B => &.{
            &.{.{ .DEC_REG_16 = .BC }},
            &.{},
        },
        0x0C => &.{
            &.{.{ .INC_REG_8 = .C }},
        },
        0x0D => &.{
            &.{.{ .DEC_REG_8 = .C }},
        },
        0x0E => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .C } }},
        },
        0x0F => &.{
            &.{.RRCA},
        },

        0x10 => &.{
            &.{ .STOP, .DISABLE_INTERRUPTS },
        },
        0x11 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .W } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .ASSIGN_16 = .{ .from = .WZ, .to = .DE } }},
        },
        0x12 => &.{
            &.{.{ .WRITE_8 = .{ .value = .A, .address = .DE } }},
            &.{},
        },
        0x13 => &.{
            &.{.{ .INC_REG_16 = .DE }},
            &.{},
        },
        0x14 => &.{
            &.{.{ .INC_REG_8 = .D }},
        },
        0x15 => &.{
            &.{.{ .DEC_REG_8 = .D }},
        },
        0x16 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .D } }},
        },
        0x17 => &.{
            &.{.RLA},
        },

        0x18 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .JUMP_RELATIVE = .Z }},
            &.{},
        },
        0x19 => &.{
            &.{.{ .ADD = .{ .value = .E, .to = .L } }},
            &.{.{ .ADD_CARRY = .{ .value = .D, .to = .H } }},
        },
        0x1A => &.{
            &.{.{ .READ_8 = .{ .address = .DE, .to = .Z } }},
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .A } }},
        },
        0x1B => &.{
            &.{.{ .DEC_REG_16 = .DE }},
            &.{},
        },
        0x1C => &.{
            &.{.{ .INC_REG_8 = .E }},
        },
        0x1D => &.{
            &.{.{ .DEC_REG_8 = .E }},
        },
        0x1E => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .E } }},
        },
        0x1F => &.{
            &.{.RRA},
        },

        0x20 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC }, .CHECK_NOT_ZERO },
            &.{.{ .JUMP_RELATIVE = .Z }},
            &.{},
        },
        0x21 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .W } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .ASSIGN_16 = .{ .from = .WZ, .to = .HL } }},
        },
        0x22 => &.{
            &.{ .{ .WRITE_8 = .{ .value = .A, .address = .HL } }, .{ .INC_REG_16 = .HL } },
            &.{},
        },
        0x23 => &.{
            &.{.{ .INC_REG_16 = .HL }},
            &.{},
        },
        0x24 => &.{
            &.{.{ .INC_REG_8 = .H }},
        },
        0x25 => &.{
            &.{.{ .DEC_REG_8 = .H }},
        },
        0x26 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .H } }},
        },
        0x27 => &.{
            &.{.DAA},
        },

        0x28 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC }, .CHECK_ZERO },
            &.{.{ .JUMP_RELATIVE = .Z }},
            &.{},
        },
        0x29 => &.{
            &.{.{ .ADD = .{ .value = .L, .to = .L } }},
            &.{.{ .ADD_CARRY = .{ .value = .H, .to = .H } }},
        },
        0x2A => &.{
            &.{ .{ .READ_8 = .{ .address = .HL, .to = .Z } }, .{ .INC_REG_16 = .HL } },
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .A } }},
        },
        0x2B => &.{
            &.{.{ .DEC_REG_16 = .HL }},
            &.{},
        },
        0x2C => &.{
            &.{.{ .INC_REG_8 = .L }},
        },
        0x2D => &.{
            &.{.{ .DEC_REG_8 = .L }},
        },
        0x2E => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .L } }},
        },
        0x2F => &.{
            &.{.CPL},
        },

        0x30 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC }, .CHECK_NOT_CARRY },
            &.{.{ .JUMP_RELATIVE = .Z }},
            &.{},
        },
        0x31 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .W } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .ASSIGN_16 = .{ .from = .WZ, .to = .SP } }},
        },
        0x32 => &.{
            &.{ .{ .WRITE_8 = .{ .value = .A, .address = .HL } }, .{ .DEC_REG_16 = .HL } },
            &.{},
        },
        0x33 => &.{
            &.{.{ .INC_REG_16 = .SP }},
            &.{},
        },
        0x34 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .INC_REG_8 = .Z }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0x35 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .DEC_REG_8 = .Z }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0x36 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .WRITE_8 = .{ .address = .HL, .value = .Z } }},
            &.{},
        },
        0x37 => &.{
            &.{.SCF},
        },

        0x38 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC }, .CHECK_CARRY },
            &.{.{ .JUMP_RELATIVE = .Z }},
            &.{},
        },
        0x39 => &.{
            &.{.{ .ADD = .{ .value = .lsb_sp, .to = .L } }},
            &.{.{ .ADD_CARRY = .{ .value = .msb_sp, .to = .H } }},
        },
        0x3A => &.{
            &.{ .{ .READ_8 = .{ .address = .HL, .to = .Z } }, .{ .DEC_REG_16 = .HL } },
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .A } }},
        },
        0x3B => &.{
            &.{.{ .DEC_REG_16 = .SP }},
            &.{},
        },
        0x3C => &.{
            &.{.{ .INC_REG_8 = .A }},
        },
        0x3D => &.{
            &.{.{ .DEC_REG_8 = .A }},
        },
        0x3E => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .A } }},
        },
        0x3F => &.{
            &.{.CCF},
        },

        0x40 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .B, .to = .B } }},
        },
        0x41 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .C, .to = .B } }},
        },
        0x42 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .D, .to = .B } }},
        },
        0x43 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .E, .to = .B } }},
        },
        0x44 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .H, .to = .B } }},
        },
        0x45 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .L, .to = .B } }},
        },
        0x46 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .B } }},
        },
        0x47 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .A, .to = .B } }},
        },

        0x48 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .B, .to = .C } }},
        },
        0x49 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .C, .to = .C } }},
        },
        0x4A => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .D, .to = .C } }},
        },
        0x4B => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .E, .to = .C } }},
        },
        0x4C => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .H, .to = .C } }},
        },
        0x4D => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .L, .to = .C } }},
        },
        0x4E => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .C } }},
        },
        0x4F => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .A, .to = .C } }},
        },

        0x50 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .B, .to = .D } }},
        },
        0x51 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .C, .to = .D } }},
        },
        0x52 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .D, .to = .D } }},
        },
        0x53 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .E, .to = .D } }},
        },
        0x54 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .H, .to = .D } }},
        },
        0x55 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .L, .to = .D } }},
        },
        0x56 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .D } }},
        },
        0x57 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .A, .to = .D } }},
        },

        0x58 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .B, .to = .E } }},
        },
        0x59 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .C, .to = .E } }},
        },
        0x5A => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .D, .to = .E } }},
        },
        0x5B => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .E, .to = .E } }},
        },
        0x5C => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .H, .to = .E } }},
        },
        0x5D => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .L, .to = .E } }},
        },
        0x5E => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .E } }},
        },
        0x5F => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .A, .to = .E } }},
        },

        0x60 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .B, .to = .H } }},
        },
        0x61 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .C, .to = .H } }},
        },
        0x62 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .D, .to = .H } }},
        },
        0x63 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .E, .to = .H } }},
        },
        0x64 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .H, .to = .H } }},
        },
        0x65 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .L, .to = .H } }},
        },
        0x66 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .H } }},
        },
        0x67 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .A, .to = .H } }},
        },

        0x68 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .B, .to = .L } }},
        },
        0x69 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .C, .to = .L } }},
        },
        0x6A => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .D, .to = .L } }},
        },
        0x6B => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .E, .to = .L } }},
        },
        0x6C => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .H, .to = .L } }},
        },
        0x6D => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .L, .to = .L } }},
        },
        0x6E => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .L } }},
        },
        0x6F => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .A, .to = .L } }},
        },

        0x70 => &.{
            &.{.{ .WRITE_8 = .{ .address = .HL, .value = .B } }},
            &.{},
        },
        0x71 => &.{
            &.{.{ .WRITE_8 = .{ .address = .HL, .value = .C } }},
            &.{},
        },
        0x72 => &.{
            &.{.{ .WRITE_8 = .{ .address = .HL, .value = .D } }},
            &.{},
        },
        0x73 => &.{
            &.{.{ .WRITE_8 = .{ .address = .HL, .value = .E } }},
            &.{},
        },
        0x74 => &.{
            &.{.{ .WRITE_8 = .{ .address = .HL, .value = .H } }},
            &.{},
        },
        0x75 => &.{
            &.{.{ .WRITE_8 = .{ .address = .HL, .value = .L } }},
            &.{},
        },
        0x76 => &.{
            &.{.HALT},
        },
        0x77 => &.{
            &.{.{ .WRITE_8 = .{ .address = .HL, .value = .A } }},
            &.{},
        },

        0x78 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .B, .to = .A } }},
        },
        0x79 => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .C, .to = .A } }},
        },
        0x7A => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .D, .to = .A } }},
        },
        0x7B => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .E, .to = .A } }},
        },
        0x7C => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .H, .to = .A } }},
        },
        0x7D => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .L, .to = .A } }},
        },
        0x7E => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .A } }},
        },
        0x7F => &.{
            &.{.{ .ASSIGN_8 = .{ .from = .A, .to = .A } }},
        },

        0x80 => &.{
            &.{.{ .ADD_A = .B }},
        },
        0x81 => &.{
            &.{.{ .ADD_A = .C }},
        },
        0x82 => &.{
            &.{.{ .ADD_A = .D }},
        },
        0x83 => &.{
            &.{.{ .ADD_A = .E }},
        },
        0x84 => &.{
            &.{.{ .ADD_A = .H }},
        },
        0x85 => &.{
            &.{.{ .ADD_A = .L }},
        },
        0x86 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .ADD_A = .Z }},
        },
        0x87 => &.{
            &.{.{ .ADD_A = .A }},
        },

        0x88 => &.{
            &.{.{ .ADC = .B }},
        },
        0x89 => &.{
            &.{.{ .ADC = .C }},
        },
        0x8A => &.{
            &.{.{ .ADC = .D }},
        },
        0x8B => &.{
            &.{.{ .ADC = .E }},
        },
        0x8C => &.{
            &.{.{ .ADC = .H }},
        },
        0x8D => &.{
            &.{.{ .ADC = .L }},
        },
        0x8E => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .ADC = .Z }},
        },
        0x8F => &.{
            &.{.{ .ADC = .A }},
        },

        0x90 => &.{
            &.{.{ .SUB = .B }},
        },
        0x91 => &.{
            &.{.{ .SUB = .C }},
        },
        0x92 => &.{
            &.{.{ .SUB = .D }},
        },
        0x93 => &.{
            &.{.{ .SUB = .E }},
        },
        0x94 => &.{
            &.{.{ .SUB = .H }},
        },
        0x95 => &.{
            &.{.{ .SUB = .L }},
        },
        0x96 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .SUB = .Z }},
        },
        0x97 => &.{
            &.{.{ .SUB = .A }},
        },

        0x98 => &.{
            &.{.{ .SBC = .B }},
        },
        0x99 => &.{
            &.{.{ .SBC = .C }},
        },
        0x9A => &.{
            &.{.{ .SBC = .D }},
        },
        0x9B => &.{
            &.{.{ .SBC = .E }},
        },
        0x9C => &.{
            &.{.{ .SBC = .H }},
        },
        0x9D => &.{
            &.{.{ .SBC = .L }},
        },
        0x9E => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .SBC = .Z }},
        },
        0x9F => &.{
            &.{.{ .SBC = .A }},
        },

        0xA0 => &.{
            &.{.{ .AND = .B }},
        },
        0xA1 => &.{
            &.{.{ .AND = .C }},
        },
        0xA2 => &.{
            &.{.{ .AND = .D }},
        },
        0xA3 => &.{
            &.{.{ .AND = .E }},
        },
        0xA4 => &.{
            &.{.{ .AND = .H }},
        },
        0xA5 => &.{
            &.{.{ .AND = .L }},
        },
        0xA6 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .AND = .Z }},
        },
        0xA7 => &.{
            &.{.{ .AND = .A }},
        },

        0xA8 => &.{
            &.{.{ .XOR = .B }},
        },
        0xA9 => &.{
            &.{.{ .XOR = .C }},
        },
        0xAA => &.{
            &.{.{ .XOR = .D }},
        },
        0xAB => &.{
            &.{.{ .XOR = .E }},
        },
        0xAC => &.{
            &.{.{ .XOR = .H }},
        },
        0xAD => &.{
            &.{.{ .XOR = .L }},
        },
        0xAE => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .XOR = .Z }},
        },
        0xAF => &.{
            &.{.{ .XOR = .A }},
        },

        0xB0 => &.{
            &.{.{ .OR = .B }},
        },
        0xB1 => &.{
            &.{.{ .OR = .C }},
        },
        0xB2 => &.{
            &.{.{ .OR = .D }},
        },
        0xB3 => &.{
            &.{.{ .OR = .E }},
        },
        0xB4 => &.{
            &.{.{ .OR = .H }},
        },
        0xB5 => &.{
            &.{.{ .OR = .L }},
        },
        0xB6 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .OR = .Z }},
        },
        0xB7 => &.{
            &.{.{ .OR = .A }},
        },

        0xB8 => &.{
            &.{.{ .CP = .B }},
        },
        0xB9 => &.{
            &.{.{ .CP = .C }},
        },
        0xBA => &.{
            &.{.{ .CP = .D }},
        },
        0xBB => &.{
            &.{.{ .CP = .E }},
        },
        0xBC => &.{
            &.{.{ .CP = .H }},
        },
        0xBD => &.{
            &.{.{ .CP = .L }},
        },
        0xBE => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .CP = .Z }},
        },
        0xBF => &.{
            &.{.{ .CP = .A }},
        },

        0xC0 => &.{
            &.{.CHECK_NOT_ZERO},
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .Z } }, .{ .INC_REG_16 = .SP } },
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .W } }, .{ .INC_REG_16 = .SP } },
            &.{.{ .ASSIGN_16 = .{ .from = .WZ, .to = .PC } }},
            &.{},
        },
        0xC1 => &.{
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .Z } }, .{ .INC_REG_16 = .SP } },
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .W } }, .{ .INC_REG_16 = .SP } },
            &.{.{ .ASSIGN_16 = .{ .from = .WZ, .to = .BC } }},
        },
        0xC2 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .W } }, .{ .INC_REG_16 = .PC }, .CHECK_NOT_ZERO },
            &.{.{ .ASSIGN_16 = .{ .from = .WZ, .to = .PC } }},
            &.{},
        },
        0xC3 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .W } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .ASSIGN_16 = .{ .from = .WZ, .to = .PC } }},
            &.{},
        },
        0xC4 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .W } }, .{ .INC_REG_16 = .PC }, .CHECK_NOT_ZERO },
            &.{.{ .DEC_REG_16 = .SP }},
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .msb_pc } }, .{ .DEC_REG_16 = .SP } },
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .lsb_pc } }, .{ .ASSIGN_16 = .{ .from = .WZ, .to = .PC } } },
            &.{},
        },
        0xC5 => &.{
            &.{.{ .DEC_REG_16 = .SP }},
            &.{ .{ .WRITE_8 = .{ .value = .B, .address = .SP } }, .{ .DEC_REG_16 = .SP } },
            &.{.{ .WRITE_8 = .{ .value = .C, .address = .SP } }},
            &.{},
        },
        0xC6 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .ADD_A = .Z }},
        },
        0xC7 => &.{
            &.{.{ .DEC_REG_16 = .SP }},
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .msb_pc } }, .{ .DEC_REG_16 = .SP } },
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .lsb_pc } }, .{ .SET_PC = 0x0000 } },
            &.{},
        },

        0xC8 => &.{
            &.{.CHECK_ZERO},
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .Z } }, .{ .INC_REG_16 = .SP } },
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .W } }, .{ .INC_REG_16 = .SP } },
            &.{.{ .ASSIGN_16 = .{ .from = .WZ, .to = .PC } }},
            &.{},
        },
        0xC9 => &.{
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .Z } }, .{ .INC_REG_16 = .SP } },
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .W } }, .{ .INC_REG_16 = .SP } },
            &.{.{ .ASSIGN_16 = .{ .from = .WZ, .to = .PC } }},
            &.{},
        },
        0xCA => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .W } }, .{ .INC_REG_16 = .PC }, .CHECK_ZERO },
            &.{.{ .ASSIGN_16 = .{ .from = .WZ, .to = .PC } }},
            &.{},
        },
        0xCB => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC }, .{ .PREFIX = .Z } },
        },
        0xCC => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .W } }, .{ .INC_REG_16 = .PC }, .CHECK_ZERO },
            &.{.{ .DEC_REG_16 = .SP }},
            &.{ .{ .WRITE_8 = .{ .value = .msb_pc, .address = .SP } }, .{ .DEC_REG_16 = .SP } },
            &.{ .{ .WRITE_8 = .{ .value = .lsb_pc, .address = .SP } }, .{ .ASSIGN_16 = .{ .from = .WZ, .to = .PC } } },
            &.{},
        },
        0xCD => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .W } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .DEC_REG_16 = .SP }},
            &.{ .{ .WRITE_8 = .{ .value = .msb_pc, .address = .SP } }, .{ .DEC_REG_16 = .SP } },
            &.{ .{ .WRITE_8 = .{ .value = .lsb_pc, .address = .SP } }, .{ .ASSIGN_16 = .{ .from = .WZ, .to = .PC } } },
            &.{},
        },
        0xCE => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .ADC = .Z }},
        },
        0xCF => &.{
            &.{.{ .DEC_REG_16 = .SP }},
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .msb_pc } }, .{ .DEC_REG_16 = .SP } },
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .lsb_pc } }, .{ .SET_PC = 0x0008 } },
            &.{},
        },

        0xD0 => &.{
            &.{.CHECK_NOT_CARRY},
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .Z } }, .{ .INC_REG_16 = .SP } },
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .W } }, .{ .INC_REG_16 = .SP } },
            &.{.{ .ASSIGN_16 = .{ .from = .WZ, .to = .PC } }},
            &.{},
        },
        0xD1 => &.{
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .Z } }, .{ .INC_REG_16 = .SP } },
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .W } }, .{ .INC_REG_16 = .SP } },
            &.{.{ .ASSIGN_16 = .{ .from = .WZ, .to = .DE } }},
        },
        0xD2 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .W } }, .{ .INC_REG_16 = .PC }, .CHECK_NOT_CARRY },
            &.{.{ .ASSIGN_16 = .{ .from = .WZ, .to = .PC } }},
            &.{},
        },
        0xD4 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .W } }, .{ .INC_REG_16 = .PC }, .CHECK_NOT_CARRY },
            &.{.{ .DEC_REG_16 = .SP }},
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .msb_pc } }, .{ .DEC_REG_16 = .SP } },
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .lsb_pc } }, .{ .ASSIGN_16 = .{ .from = .WZ, .to = .PC } } },
            &.{},
        },
        0xD5 => &.{
            &.{.{ .DEC_REG_16 = .SP }},
            &.{ .{ .WRITE_8 = .{ .value = .D, .address = .SP } }, .{ .DEC_REG_16 = .SP } },
            &.{.{ .WRITE_8 = .{ .value = .E, .address = .SP } }},
            &.{},
        },
        0xD6 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .SUB = .Z }},
        },
        0xD7 => &.{
            &.{.{ .DEC_REG_16 = .SP }},
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .msb_pc } }, .{ .DEC_REG_16 = .SP } },
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .lsb_pc } }, .{ .SET_PC = 0x0010 } },
            &.{},
        },

        0xD8 => &.{
            &.{.CHECK_CARRY},
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .Z } }, .{ .INC_REG_16 = .SP } },
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .W } }, .{ .INC_REG_16 = .SP } },
            &.{.{ .ASSIGN_16 = .{ .from = .WZ, .to = .PC } }},
            &.{},
        },
        0xD9 => &.{
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .Z } }, .{ .INC_REG_16 = .SP } },
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .W } }, .{ .INC_REG_16 = .SP } },
            &.{.{ .ASSIGN_16 = .{ .from = .WZ, .to = .PC } }},
            &.{.ENABLE_INTERRUPTS_IMMEDIATE},
        },
        0xDA => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .W } }, .{ .INC_REG_16 = .PC }, .CHECK_CARRY },
            &.{.{ .ASSIGN_16 = .{ .from = .WZ, .to = .PC } }},
            &.{},
        },
        0xDC => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .W } }, .{ .INC_REG_16 = .PC }, .CHECK_CARRY },
            &.{.{ .DEC_REG_16 = .SP }},
            &.{ .{ .WRITE_8 = .{ .value = .msb_pc, .address = .SP } }, .{ .DEC_REG_16 = .SP } },
            &.{ .{ .WRITE_8 = .{ .value = .lsb_pc, .address = .SP } }, .{ .ASSIGN_16 = .{ .from = .WZ, .to = .PC } } },
            &.{},
        },
        0xDE => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .SBC = .Z }},
        },
        0xDF => &.{
            &.{.{ .DEC_REG_16 = .SP }},
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .msb_pc } }, .{ .DEC_REG_16 = .SP } },
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .lsb_pc } }, .{ .SET_PC = 0x0018 } },
            &.{},
        },

        0xE0 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .WRITE_8_HIGH = .{ .value = .A, .address = .Z } }},
            &.{},
        },
        0xE1 => &.{
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .Z } }, .{ .INC_REG_16 = .SP } },
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .W } }, .{ .INC_REG_16 = .SP } },
            &.{.{ .ASSIGN_16 = .{ .from = .WZ, .to = .HL } }},
        },
        0xE2 => &.{
            &.{.{ .WRITE_8_HIGH = .{ .address = .C, .value = .A } }},
            &.{},
        },
        0xE5 => &.{
            &.{.{ .DEC_REG_16 = .SP }},
            &.{ .{ .WRITE_8 = .{ .value = .H, .address = .SP } }, .{ .DEC_REG_16 = .SP } },
            &.{.{ .WRITE_8 = .{ .value = .L, .address = .SP } }},
            &.{},
        },
        0xE6 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .AND = .Z }},
        },
        0xE7 => &.{
            &.{.{ .DEC_REG_16 = .SP }},
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .msb_pc } }, .{ .DEC_REG_16 = .SP } },
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .lsb_pc } }, .{ .SET_PC = 0x0020 } },
            &.{},
        },

        0xE8 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .ADD_SP = .Z }},
            &.{.{ .ADD_SP_CARRY = .Z }},
            &.{},
        },
        0xE9 => &.{
            &.{.{ .ASSIGN_16 = .{ .from = .HL, .to = .PC } }},
        },
        0xEA => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .W } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .WRITE_8 = .{ .value = .A, .address = .WZ } }},
            &.{},
        },
        0xEE => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .XOR = .Z }},
        },
        0xEF => &.{
            &.{.{ .DEC_REG_16 = .SP }},
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .msb_pc } }, .{ .DEC_REG_16 = .SP } },
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .lsb_pc } }, .{ .SET_PC = 0x0028 } },
            &.{},
        },

        0xF0 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .READ_8_HIGH = .{ .address = .Z, .to = .W } }},
            &.{.{ .ASSIGN_8 = .{ .from = .W, .to = .A } }},
        },
        0xF1 => &.{
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .Z } }, .{ .INC_REG_16 = .SP } },
            &.{ .{ .READ_8 = .{ .address = .SP, .to = .W } }, .{ .INC_REG_16 = .SP } },
            &.{.{ .ASSIGN_16 = .{ .from = .WZ, .to = .AF } }},
        },
        0xF2 => &.{
            &.{.{ .READ_8_HIGH = .{ .address = .C, .to = .Z } }},
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .A } }},
        },
        0xF3 => &.{
            &.{.DISABLE_INTERRUPTS},
        },
        0xF5 => &.{
            &.{.{ .DEC_REG_16 = .SP }},
            &.{ .{ .WRITE_8 = .{ .value = .A, .address = .SP } }, .{ .DEC_REG_16 = .SP } },
            &.{.{ .WRITE_8 = .{ .value = .F, .address = .SP } }},
            &.{},
        },
        0xF6 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .OR = .Z }},
        },
        0xF7 => &.{
            &.{.{ .DEC_REG_16 = .SP }},
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .msb_pc } }, .{ .DEC_REG_16 = .SP } },
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .lsb_pc } }, .{ .SET_PC = 0x0030 } },
            &.{},
        },

        0xF8 => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .ADD_SP_HL = .Z }},
            &.{.{ .ADD_SP_HL_CARRY = .Z }},
        },
        0xF9 => &.{
            &.{.{ .ASSIGN_16 = .{ .from = .HL, .to = .SP } }},
            &.{},
        },
        0xFA => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .W } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .READ_8 = .{ .address = .WZ, .to = .Z } }},
            &.{.{ .ASSIGN_8 = .{ .from = .Z, .to = .A } }},
        },
        0xFB => &.{
            &.{.ENABLE_INTERRUPTS},
        },
        0xFE => &.{
            &.{ .{ .READ_8 = .{ .address = .PC, .to = .Z } }, .{ .INC_REG_16 = .PC } },
            &.{.{ .CP = .Z }},
        },
        0xFF => &.{
            &.{.{ .DEC_REG_16 = .SP }},
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .msb_pc } }, .{ .DEC_REG_16 = .SP } },
            &.{ .{ .WRITE_8 = .{ .address = .SP, .value = .lsb_pc } }, .{ .SET_PC = 0x0038 } },
            &.{},
        },

        else => {
            std.debug.panic("Unknown opcode 0x{X:0>2}\n", .{opcode});
        },
    };
}

fn prefixInstruction(opcode: u8) []const []const QueueItem {
    return switch (opcode) {
        0x00 => &.{
            &.{.{ .RLC = .B }},
        },
        0x01 => &.{
            &.{.{ .RLC = .C }},
        },
        0x02 => &.{
            &.{.{ .RLC = .D }},
        },
        0x03 => &.{
            &.{.{ .RLC = .E }},
        },
        0x04 => &.{
            &.{.{ .RLC = .H }},
        },
        0x05 => &.{
            &.{.{ .RLC = .L }},
        },
        0x06 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .RLC = .Z }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0x07 => &.{
            &.{.{ .RLC = .A }},
        },

        0x08 => &.{
            &.{.{ .RRC = .B }},
        },
        0x09 => &.{
            &.{.{ .RRC = .C }},
        },
        0x0A => &.{
            &.{.{ .RRC = .D }},
        },
        0x0B => &.{
            &.{.{ .RRC = .E }},
        },
        0x0C => &.{
            &.{.{ .RRC = .H }},
        },
        0x0D => &.{
            &.{.{ .RRC = .L }},
        },
        0x0E => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .RRC = .Z }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0x0F => &.{
            &.{.{ .RRC = .A }},
        },

        0x10 => &.{
            &.{.{ .RL = .B }},
        },
        0x11 => &.{
            &.{.{ .RL = .C }},
        },
        0x12 => &.{
            &.{.{ .RL = .D }},
        },
        0x13 => &.{
            &.{.{ .RL = .E }},
        },
        0x14 => &.{
            &.{.{ .RL = .H }},
        },
        0x15 => &.{
            &.{.{ .RL = .L }},
        },
        0x16 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .RL = .Z }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0x17 => &.{
            &.{.{ .RL = .A }},
        },

        0x18 => &.{
            &.{.{ .RR = .B }},
        },
        0x19 => &.{
            &.{.{ .RR = .C }},
        },
        0x1A => &.{
            &.{.{ .RR = .D }},
        },
        0x1B => &.{
            &.{.{ .RR = .E }},
        },
        0x1C => &.{
            &.{.{ .RR = .H }},
        },
        0x1D => &.{
            &.{.{ .RR = .L }},
        },
        0x1E => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .RR = .Z }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0x1F => &.{
            &.{.{ .RR = .A }},
        },

        0x20 => &.{
            &.{.{ .SLA = .B }},
        },
        0x21 => &.{
            &.{.{ .SLA = .C }},
        },
        0x22 => &.{
            &.{.{ .SLA = .D }},
        },
        0x23 => &.{
            &.{.{ .SLA = .E }},
        },
        0x24 => &.{
            &.{.{ .SLA = .H }},
        },
        0x25 => &.{
            &.{.{ .SLA = .L }},
        },
        0x26 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .SLA = .Z }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0x27 => &.{
            &.{.{ .SLA = .A }},
        },

        0x28 => &.{
            &.{.{ .SRA = .B }},
        },
        0x29 => &.{
            &.{.{ .SRA = .C }},
        },
        0x2A => &.{
            &.{.{ .SRA = .D }},
        },
        0x2B => &.{
            &.{.{ .SRA = .E }},
        },
        0x2C => &.{
            &.{.{ .SRA = .H }},
        },
        0x2D => &.{
            &.{.{ .SRA = .L }},
        },
        0x2E => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .SRA = .Z }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0x2F => &.{
            &.{.{ .SRA = .A }},
        },

        0x30 => &.{
            &.{.{ .SWAP = .B }},
        },
        0x31 => &.{
            &.{.{ .SWAP = .C }},
        },
        0x32 => &.{
            &.{.{ .SWAP = .D }},
        },
        0x33 => &.{
            &.{.{ .SWAP = .E }},
        },
        0x34 => &.{
            &.{.{ .SWAP = .H }},
        },
        0x35 => &.{
            &.{.{ .SWAP = .L }},
        },
        0x36 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .SWAP = .Z }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0x37 => &.{
            &.{.{ .SWAP = .A }},
        },

        0x38 => &.{
            &.{.{ .SRL = .B }},
        },
        0x39 => &.{
            &.{.{ .SRL = .C }},
        },
        0x3A => &.{
            &.{.{ .SRL = .D }},
        },
        0x3B => &.{
            &.{.{ .SRL = .E }},
        },
        0x3C => &.{
            &.{.{ .SRL = .H }},
        },
        0x3D => &.{
            &.{.{ .SRL = .L }},
        },
        0x3E => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .SRL = .Z }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0x3F => &.{
            &.{.{ .SRL = .A }},
        },

        0x40 => &.{
            &.{.{ .BIT = .{ .register = .B, .bit = 0 } }},
        },
        0x41 => &.{
            &.{.{ .BIT = .{ .register = .C, .bit = 0 } }},
        },
        0x42 => &.{
            &.{.{ .BIT = .{ .register = .D, .bit = 0 } }},
        },
        0x43 => &.{
            &.{.{ .BIT = .{ .register = .E, .bit = 0 } }},
        },
        0x44 => &.{
            &.{.{ .BIT = .{ .register = .H, .bit = 0 } }},
        },
        0x45 => &.{
            &.{.{ .BIT = .{ .register = .L, .bit = 0 } }},
        },
        0x46 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .BIT = .{ .register = .Z, .bit = 0 } }},
        },
        0x47 => &.{
            &.{.{ .BIT = .{ .register = .A, .bit = 0 } }},
        },

        0x48 => &.{
            &.{.{ .BIT = .{ .register = .B, .bit = 1 } }},
        },
        0x49 => &.{
            &.{.{ .BIT = .{ .register = .C, .bit = 1 } }},
        },
        0x4A => &.{
            &.{.{ .BIT = .{ .register = .D, .bit = 1 } }},
        },
        0x4B => &.{
            &.{.{ .BIT = .{ .register = .E, .bit = 1 } }},
        },
        0x4C => &.{
            &.{.{ .BIT = .{ .register = .H, .bit = 1 } }},
        },
        0x4D => &.{
            &.{.{ .BIT = .{ .register = .L, .bit = 1 } }},
        },
        0x4E => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .BIT = .{ .register = .Z, .bit = 1 } }},
        },
        0x4F => &.{
            &.{.{ .BIT = .{ .register = .A, .bit = 1 } }},
        },

        0x50 => &.{
            &.{.{ .BIT = .{ .register = .B, .bit = 2 } }},
        },
        0x51 => &.{
            &.{.{ .BIT = .{ .register = .C, .bit = 2 } }},
        },
        0x52 => &.{
            &.{.{ .BIT = .{ .register = .D, .bit = 2 } }},
        },
        0x53 => &.{
            &.{.{ .BIT = .{ .register = .E, .bit = 2 } }},
        },
        0x54 => &.{
            &.{.{ .BIT = .{ .register = .H, .bit = 2 } }},
        },
        0x55 => &.{
            &.{.{ .BIT = .{ .register = .L, .bit = 2 } }},
        },
        0x56 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .BIT = .{ .register = .Z, .bit = 2 } }},
        },
        0x57 => &.{
            &.{.{ .BIT = .{ .register = .A, .bit = 2 } }},
        },

        0x58 => &.{
            &.{.{ .BIT = .{ .register = .B, .bit = 3 } }},
        },
        0x59 => &.{
            &.{.{ .BIT = .{ .register = .C, .bit = 3 } }},
        },
        0x5A => &.{
            &.{.{ .BIT = .{ .register = .D, .bit = 3 } }},
        },
        0x5B => &.{
            &.{.{ .BIT = .{ .register = .E, .bit = 3 } }},
        },
        0x5C => &.{
            &.{.{ .BIT = .{ .register = .H, .bit = 3 } }},
        },
        0x5D => &.{
            &.{.{ .BIT = .{ .register = .L, .bit = 3 } }},
        },
        0x5E => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .BIT = .{ .register = .Z, .bit = 3 } }},
        },
        0x5F => &.{
            &.{.{ .BIT = .{ .register = .A, .bit = 3 } }},
        },

        0x60 => &.{
            &.{.{ .BIT = .{ .register = .B, .bit = 4 } }},
        },
        0x61 => &.{
            &.{.{ .BIT = .{ .register = .C, .bit = 4 } }},
        },
        0x62 => &.{
            &.{.{ .BIT = .{ .register = .D, .bit = 4 } }},
        },
        0x63 => &.{
            &.{.{ .BIT = .{ .register = .E, .bit = 4 } }},
        },
        0x64 => &.{
            &.{.{ .BIT = .{ .register = .H, .bit = 4 } }},
        },
        0x65 => &.{
            &.{.{ .BIT = .{ .register = .L, .bit = 4 } }},
        },
        0x66 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .BIT = .{ .register = .Z, .bit = 4 } }},
        },
        0x67 => &.{
            &.{.{ .BIT = .{ .register = .A, .bit = 4 } }},
        },

        0x68 => &.{
            &.{.{ .BIT = .{ .register = .B, .bit = 5 } }},
        },
        0x69 => &.{
            &.{.{ .BIT = .{ .register = .C, .bit = 5 } }},
        },
        0x6A => &.{
            &.{.{ .BIT = .{ .register = .D, .bit = 5 } }},
        },
        0x6B => &.{
            &.{.{ .BIT = .{ .register = .E, .bit = 5 } }},
        },
        0x6C => &.{
            &.{.{ .BIT = .{ .register = .H, .bit = 5 } }},
        },
        0x6D => &.{
            &.{.{ .BIT = .{ .register = .L, .bit = 5 } }},
        },
        0x6E => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .BIT = .{ .register = .Z, .bit = 5 } }},
        },
        0x6F => &.{
            &.{.{ .BIT = .{ .register = .A, .bit = 5 } }},
        },

        0x70 => &.{
            &.{.{ .BIT = .{ .register = .B, .bit = 6 } }},
        },
        0x71 => &.{
            &.{.{ .BIT = .{ .register = .C, .bit = 6 } }},
        },
        0x72 => &.{
            &.{.{ .BIT = .{ .register = .D, .bit = 6 } }},
        },
        0x73 => &.{
            &.{.{ .BIT = .{ .register = .E, .bit = 6 } }},
        },
        0x74 => &.{
            &.{.{ .BIT = .{ .register = .H, .bit = 6 } }},
        },
        0x75 => &.{
            &.{.{ .BIT = .{ .register = .L, .bit = 6 } }},
        },
        0x76 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .BIT = .{ .register = .Z, .bit = 6 } }},
        },
        0x77 => &.{
            &.{.{ .BIT = .{ .register = .A, .bit = 6 } }},
        },

        0x78 => &.{
            &.{.{ .BIT = .{ .register = .B, .bit = 7 } }},
        },
        0x79 => &.{
            &.{.{ .BIT = .{ .register = .C, .bit = 7 } }},
        },
        0x7A => &.{
            &.{.{ .BIT = .{ .register = .D, .bit = 7 } }},
        },
        0x7B => &.{
            &.{.{ .BIT = .{ .register = .E, .bit = 7 } }},
        },
        0x7C => &.{
            &.{.{ .BIT = .{ .register = .H, .bit = 7 } }},
        },
        0x7D => &.{
            &.{.{ .BIT = .{ .register = .L, .bit = 7 } }},
        },
        0x7E => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{.{ .BIT = .{ .register = .Z, .bit = 7 } }},
        },
        0x7F => &.{
            &.{.{ .BIT = .{ .register = .A, .bit = 7 } }},
        },

        0x80 => &.{
            &.{.{ .RES = .{ .register = .B, .bit = 0 } }},
        },
        0x81 => &.{
            &.{.{ .RES = .{ .register = .C, .bit = 0 } }},
        },
        0x82 => &.{
            &.{.{ .RES = .{ .register = .D, .bit = 0 } }},
        },
        0x83 => &.{
            &.{.{ .RES = .{ .register = .E, .bit = 0 } }},
        },
        0x84 => &.{
            &.{.{ .RES = .{ .register = .H, .bit = 0 } }},
        },
        0x85 => &.{
            &.{.{ .RES = .{ .register = .L, .bit = 0 } }},
        },
        0x86 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .RES = .{ .register = .Z, .bit = 0 } }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0x87 => &.{
            &.{.{ .RES = .{ .register = .A, .bit = 0 } }},
        },

        0x88 => &.{
            &.{.{ .RES = .{ .register = .B, .bit = 1 } }},
        },
        0x89 => &.{
            &.{.{ .RES = .{ .register = .C, .bit = 1 } }},
        },
        0x8A => &.{
            &.{.{ .RES = .{ .register = .D, .bit = 1 } }},
        },
        0x8B => &.{
            &.{.{ .RES = .{ .register = .E, .bit = 1 } }},
        },
        0x8C => &.{
            &.{.{ .RES = .{ .register = .H, .bit = 1 } }},
        },
        0x8D => &.{
            &.{.{ .RES = .{ .register = .L, .bit = 1 } }},
        },
        0x8E => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .RES = .{ .register = .Z, .bit = 1 } }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0x8F => &.{
            &.{.{ .RES = .{ .register = .A, .bit = 1 } }},
        },

        0x90 => &.{
            &.{.{ .RES = .{ .register = .B, .bit = 2 } }},
        },
        0x91 => &.{
            &.{.{ .RES = .{ .register = .C, .bit = 2 } }},
        },
        0x92 => &.{
            &.{.{ .RES = .{ .register = .D, .bit = 2 } }},
        },
        0x93 => &.{
            &.{.{ .RES = .{ .register = .E, .bit = 2 } }},
        },
        0x94 => &.{
            &.{.{ .RES = .{ .register = .H, .bit = 2 } }},
        },
        0x95 => &.{
            &.{.{ .RES = .{ .register = .L, .bit = 2 } }},
        },
        0x96 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .RES = .{ .register = .Z, .bit = 2 } }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0x97 => &.{
            &.{.{ .RES = .{ .register = .A, .bit = 2 } }},
        },

        0x98 => &.{
            &.{.{ .RES = .{ .register = .B, .bit = 3 } }},
        },
        0x99 => &.{
            &.{.{ .RES = .{ .register = .C, .bit = 3 } }},
        },
        0x9A => &.{
            &.{.{ .RES = .{ .register = .D, .bit = 3 } }},
        },
        0x9B => &.{
            &.{.{ .RES = .{ .register = .E, .bit = 3 } }},
        },
        0x9C => &.{
            &.{.{ .RES = .{ .register = .H, .bit = 3 } }},
        },
        0x9D => &.{
            &.{.{ .RES = .{ .register = .L, .bit = 3 } }},
        },
        0x9E => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .RES = .{ .register = .Z, .bit = 3 } }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0x9F => &.{
            &.{.{ .RES = .{ .register = .A, .bit = 3 } }},
        },

        0xA0 => &.{
            &.{.{ .RES = .{ .register = .B, .bit = 4 } }},
        },
        0xA1 => &.{
            &.{.{ .RES = .{ .register = .C, .bit = 4 } }},
        },
        0xA2 => &.{
            &.{.{ .RES = .{ .register = .D, .bit = 4 } }},
        },
        0xA3 => &.{
            &.{.{ .RES = .{ .register = .E, .bit = 4 } }},
        },
        0xA4 => &.{
            &.{.{ .RES = .{ .register = .H, .bit = 4 } }},
        },
        0xA5 => &.{
            &.{.{ .RES = .{ .register = .L, .bit = 4 } }},
        },
        0xA6 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .RES = .{ .register = .Z, .bit = 4 } }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0xA7 => &.{
            &.{.{ .RES = .{ .register = .A, .bit = 4 } }},
        },

        0xA8 => &.{
            &.{.{ .RES = .{ .register = .B, .bit = 5 } }},
        },
        0xA9 => &.{
            &.{.{ .RES = .{ .register = .C, .bit = 5 } }},
        },
        0xAA => &.{
            &.{.{ .RES = .{ .register = .D, .bit = 5 } }},
        },
        0xAB => &.{
            &.{.{ .RES = .{ .register = .E, .bit = 5 } }},
        },
        0xAC => &.{
            &.{.{ .RES = .{ .register = .H, .bit = 5 } }},
        },
        0xAD => &.{
            &.{.{ .RES = .{ .register = .L, .bit = 5 } }},
        },
        0xAE => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .RES = .{ .register = .Z, .bit = 5 } }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0xAF => &.{
            &.{.{ .RES = .{ .register = .A, .bit = 5 } }},
        },

        0xB0 => &.{
            &.{.{ .RES = .{ .register = .B, .bit = 6 } }},
        },
        0xB1 => &.{
            &.{.{ .RES = .{ .register = .C, .bit = 6 } }},
        },
        0xB2 => &.{
            &.{.{ .RES = .{ .register = .D, .bit = 6 } }},
        },
        0xB3 => &.{
            &.{.{ .RES = .{ .register = .E, .bit = 6 } }},
        },
        0xB4 => &.{
            &.{.{ .RES = .{ .register = .H, .bit = 6 } }},
        },
        0xB5 => &.{
            &.{.{ .RES = .{ .register = .L, .bit = 6 } }},
        },
        0xB6 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .RES = .{ .register = .Z, .bit = 6 } }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0xB7 => &.{
            &.{.{ .RES = .{ .register = .A, .bit = 6 } }},
        },

        0xB8 => &.{
            &.{.{ .RES = .{ .register = .B, .bit = 7 } }},
        },
        0xB9 => &.{
            &.{.{ .RES = .{ .register = .C, .bit = 7 } }},
        },
        0xBA => &.{
            &.{.{ .RES = .{ .register = .D, .bit = 7 } }},
        },
        0xBB => &.{
            &.{.{ .RES = .{ .register = .E, .bit = 7 } }},
        },
        0xBC => &.{
            &.{.{ .RES = .{ .register = .H, .bit = 7 } }},
        },
        0xBD => &.{
            &.{.{ .RES = .{ .register = .L, .bit = 7 } }},
        },
        0xBE => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .RES = .{ .register = .Z, .bit = 7 } }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0xBF => &.{
            &.{.{ .RES = .{ .register = .A, .bit = 7 } }},
        },

        0xC0 => &.{
            &.{.{ .SET = .{ .register = .B, .bit = 0 } }},
        },
        0xC1 => &.{
            &.{.{ .SET = .{ .register = .C, .bit = 0 } }},
        },
        0xC2 => &.{
            &.{.{ .SET = .{ .register = .D, .bit = 0 } }},
        },
        0xC3 => &.{
            &.{.{ .SET = .{ .register = .E, .bit = 0 } }},
        },
        0xC4 => &.{
            &.{.{ .SET = .{ .register = .H, .bit = 0 } }},
        },
        0xC5 => &.{
            &.{.{ .SET = .{ .register = .L, .bit = 0 } }},
        },
        0xC6 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .SET = .{ .register = .Z, .bit = 0 } }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0xC7 => &.{
            &.{.{ .SET = .{ .register = .A, .bit = 0 } }},
        },

        0xC8 => &.{
            &.{.{ .SET = .{ .register = .B, .bit = 1 } }},
        },
        0xC9 => &.{
            &.{.{ .SET = .{ .register = .C, .bit = 1 } }},
        },
        0xCA => &.{
            &.{.{ .SET = .{ .register = .D, .bit = 1 } }},
        },
        0xCB => &.{
            &.{.{ .SET = .{ .register = .E, .bit = 1 } }},
        },
        0xCC => &.{
            &.{.{ .SET = .{ .register = .H, .bit = 1 } }},
        },
        0xCD => &.{
            &.{.{ .SET = .{ .register = .L, .bit = 1 } }},
        },
        0xCE => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .SET = .{ .register = .Z, .bit = 1 } }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0xCF => &.{
            &.{.{ .SET = .{ .register = .A, .bit = 1 } }},
        },

        0xD0 => &.{
            &.{.{ .SET = .{ .register = .B, .bit = 2 } }},
        },
        0xD1 => &.{
            &.{.{ .SET = .{ .register = .C, .bit = 2 } }},
        },
        0xD2 => &.{
            &.{.{ .SET = .{ .register = .D, .bit = 2 } }},
        },
        0xD3 => &.{
            &.{.{ .SET = .{ .register = .E, .bit = 2 } }},
        },
        0xD4 => &.{
            &.{.{ .SET = .{ .register = .H, .bit = 2 } }},
        },
        0xD5 => &.{
            &.{.{ .SET = .{ .register = .L, .bit = 2 } }},
        },
        0xD6 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .SET = .{ .register = .Z, .bit = 2 } }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0xD7 => &.{
            &.{.{ .SET = .{ .register = .A, .bit = 2 } }},
        },

        0xD8 => &.{
            &.{.{ .SET = .{ .register = .B, .bit = 3 } }},
        },
        0xD9 => &.{
            &.{.{ .SET = .{ .register = .C, .bit = 3 } }},
        },
        0xDA => &.{
            &.{.{ .SET = .{ .register = .D, .bit = 3 } }},
        },
        0xDB => &.{
            &.{.{ .SET = .{ .register = .E, .bit = 3 } }},
        },
        0xDC => &.{
            &.{.{ .SET = .{ .register = .H, .bit = 3 } }},
        },
        0xDD => &.{
            &.{.{ .SET = .{ .register = .L, .bit = 3 } }},
        },
        0xDE => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .SET = .{ .register = .Z, .bit = 3 } }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0xDF => &.{
            &.{.{ .SET = .{ .register = .A, .bit = 3 } }},
        },

        0xE0 => &.{
            &.{.{ .SET = .{ .register = .B, .bit = 4 } }},
        },
        0xE1 => &.{
            &.{.{ .SET = .{ .register = .C, .bit = 4 } }},
        },
        0xE2 => &.{
            &.{.{ .SET = .{ .register = .D, .bit = 4 } }},
        },
        0xE3 => &.{
            &.{.{ .SET = .{ .register = .E, .bit = 4 } }},
        },
        0xE4 => &.{
            &.{.{ .SET = .{ .register = .H, .bit = 4 } }},
        },
        0xE5 => &.{
            &.{.{ .SET = .{ .register = .L, .bit = 4 } }},
        },
        0xE6 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .SET = .{ .register = .Z, .bit = 4 } }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0xE7 => &.{
            &.{.{ .SET = .{ .register = .A, .bit = 4 } }},
        },

        0xE8 => &.{
            &.{.{ .SET = .{ .register = .B, .bit = 5 } }},
        },
        0xE9 => &.{
            &.{.{ .SET = .{ .register = .C, .bit = 5 } }},
        },
        0xEA => &.{
            &.{.{ .SET = .{ .register = .D, .bit = 5 } }},
        },
        0xEB => &.{
            &.{.{ .SET = .{ .register = .E, .bit = 5 } }},
        },
        0xEC => &.{
            &.{.{ .SET = .{ .register = .H, .bit = 5 } }},
        },
        0xED => &.{
            &.{.{ .SET = .{ .register = .L, .bit = 5 } }},
        },
        0xEE => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .SET = .{ .register = .Z, .bit = 5 } }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0xEF => &.{
            &.{.{ .SET = .{ .register = .A, .bit = 5 } }},
        },

        0xF0 => &.{
            &.{.{ .SET = .{ .register = .B, .bit = 6 } }},
        },
        0xF1 => &.{
            &.{.{ .SET = .{ .register = .C, .bit = 6 } }},
        },
        0xF2 => &.{
            &.{.{ .SET = .{ .register = .D, .bit = 6 } }},
        },
        0xF3 => &.{
            &.{.{ .SET = .{ .register = .E, .bit = 6 } }},
        },
        0xF4 => &.{
            &.{.{ .SET = .{ .register = .H, .bit = 6 } }},
        },
        0xF5 => &.{
            &.{.{ .SET = .{ .register = .L, .bit = 6 } }},
        },
        0xF6 => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .SET = .{ .register = .Z, .bit = 6 } }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0xF7 => &.{
            &.{.{ .SET = .{ .register = .A, .bit = 6 } }},
        },

        0xF8 => &.{
            &.{.{ .SET = .{ .register = .B, .bit = 7 } }},
        },
        0xF9 => &.{
            &.{.{ .SET = .{ .register = .C, .bit = 7 } }},
        },
        0xFA => &.{
            &.{.{ .SET = .{ .register = .D, .bit = 7 } }},
        },
        0xFB => &.{
            &.{.{ .SET = .{ .register = .E, .bit = 7 } }},
        },
        0xFC => &.{
            &.{.{ .SET = .{ .register = .H, .bit = 7 } }},
        },
        0xFD => &.{
            &.{.{ .SET = .{ .register = .L, .bit = 7 } }},
        },
        0xFE => &.{
            &.{.{ .READ_8 = .{ .address = .HL, .to = .Z } }},
            &.{ .{ .SET = .{ .register = .Z, .bit = 7 } }, .{ .WRITE_8 = .{ .address = .HL, .value = .Z } } },
            &.{},
        },
        0xFF => &.{
            &.{.{ .SET = .{ .register = .A, .bit = 7 } }},
        },
    };
}

const instStrs: [256][]const u8 = [_][]const u8{
    "NOP",
    "LD BC, n16",
    "LD [BC], A",
    "INC BC",
    "INC B",
    "DEC B",
    "LD B, n8",
    "RLCA",
    "LD [a16], SP",
    "ADD HL, BC",
    "LD A, [BC]",
    "DEC BC",
    "INC C",
    "DEC C",
    "LD C, n8",
    "RRCA",
    "STOP",
    "LD DE, n16",
    "LD [DE], A",
    "INC DE",
    "INC D",
    "DEC D",
    "LD D, n8",
    "RLA",
    "JR e8",
    "ADD HL, DE",
    "LD A, [DE]",
    "DEC DE",
    "INC E",
    "DEC E",
    "LD E, n8",
    "RRA",
    "JR NZ, e8",
    "LD HL, n16",
    "LD [HL+], A",
    "INC HL",
    "INC H",
    "DEC H",
    "LD H, n8",
    "DAA",
    "JR Z, e8",
    "ADD HL, HL",
    "LD A, [HL+]",
    "DEC HL",
    "INC L",
    "DEC L",
    "LD L, n8",
    "CPL",
    "JR NC, e8",
    "LD SP, n16",
    "LD [HL-], A",
    "INC [SP]",
    "INC [HL]",
    "DEC [HL]",
    "LD [HL], n8",
    "SCF",
    "JR C, e8",
    "ADD HL, SP",
    "LD A, [HL-]",
    "DEC SP",
    "INC A",
    "DEC A",
    "LD A, n8",
    "CCF",
    "LD B, B",
    "LD B, C",
    "LD B, D",
    "LD B, E",
    "LD B, H",
    "LD B, L",
    "LD B, [HL]",
    "LD B, A",
    "LD C, B",
    "LD C, C",
    "LD C, D",
    "LD C, E",
    "LD C, H",
    "LD C, L",
    "LD C, [HL]",
    "LD C, A",
    "LD D, B",
    "LD D, C",
    "LD D, D",
    "LD D, E",
    "LD D, H",
    "LD D, L",
    "LD D, [HL]",
    "LD D, A",
    "LD E, B",
    "LD E, C",
    "LD E, D",
    "LD E, E",
    "LD E, H",
    "LD E, L",
    "LD E, [HL]",
    "LD E, A",
    "LD H, B",
    "LD H, C",
    "LD H, D",
    "LD H, E",
    "LD H, H",
    "LD H, L",
    "LD H, [HL]",
    "LD H, A",
    "LD L, B",
    "LD L, C",
    "LD L, D",
    "LD L, E",
    "LD L, H",
    "LD L, L",
    "LD L, [HL]",
    "LD L, A",
    "LD [HL], B",
    "LD [HL], C",
    "LD [HL], D",
    "LD [HL], E",
    "LD [HL], H",
    "LD [HL], L",
    "HALT",
    "LD [HL], A",
    "LD A, B",
    "LD A, C",
    "LD A, D",
    "LD A, E",
    "LD A, H",
    "LD A, L",
    "LD A, [HL]",
    "LD A, A",
    "ADD A, B",
    "ADD A, C",
    "ADD A, D",
    "ADD A, E",
    "ADD A, H",
    "ADD A, L",
    "ADD A, [HL]",
    "ADD A, A",
    "ADC A, B",
    "ADC A, C",
    "ADC A, D",
    "ADC A, E",
    "ADC A, H",
    "ADC A, L",
    "ADC A, [HL]",
    "ADC A, A",
    "SUB A, B",
    "SUB A, C",
    "SUB A, D",
    "SUB A, E",
    "SUB A, H",
    "SUB A, L",
    "SUB A, [HL]",
    "SUB A, A",
    "SBC A, B",
    "SBC A, C",
    "SBC A, D",
    "SBC A, E",
    "SBC A, H",
    "SBC A, L",
    "SBC A, [HL]",
    "SBC A, A",
    "AND A, B",
    "AND A, C",
    "AND A, D",
    "AND A, E",
    "AND A, H",
    "AND A, L",
    "AND A, [HL]",
    "AND A, A",
    "XOR A, B",
    "XOR A, C",
    "XOR A, D",
    "XOR A, E",
    "XOR A, H",
    "XOR A, L",
    "XOR A, [HL]",
    "XOR A, A",
    "OR A, B",
    "OR A, C",
    "OR A, D",
    "OR A, E",
    "OR A, H",
    "OR A, L",
    "OR A, [HL]",
    "OR A, A",
    "CP A, B",
    "CP A, C",
    "CP A, D",
    "CP A, E",
    "CP A, H",
    "CP A, L",
    "CP A, [HL]",
    "CP A, A",
    "RET NZ",
    "POP BC",
    "JP NZ, a16",
    "JP a16",
    "CALL NZ, a16",
    "PUSH BC",
    "ADD A, n8",
    "RST $00",
    "RET Z",
    "RET",
    "JP Z, a16",
    "PREFIX",
    "CALL Z, a16",
    "CALL a16",
    "ADC A, n8",
    "RST $08",
    "RET NC",
    "POP DE",
    "JP NC, a16",
    "ILLEGAL_D3",
    "CALL NC, a16",
    "PUSH DE",
    "SUB A, n8",
    "RST $10",
    "RET C",
    "RETI",
    "JP C, a16",
    "ILLEGAL_DB",
    "CALL C, a16",
    "ILLEGAL_DD",
    "SBC A, n8",
    "RST $18",
    "LDH [a8], A",
    "POP HL",
    "LDH [C], A",
    "ILLEGAL_E3",
    "ILLEGAL_E4",
    "PUSH HL",
    "AND A, n8",
    "RST $20",
    "ADD SP, e8",
    "JP HL",
    "LD [a16], A",
    "ILLEGAL_EB",
    "ILLEGAL_EC",
    "ILLEGAL_ED",
    "XOR A, n8",
    "RST $28",
    "LDH A, [a8]",
    "POP AF",
    "LDH A, [C]",
    "DI",
    "ILLEGAL_F4",
    "PUSH AF",
    "OR A, n8",
    "RST $30",
    "LD HL, SP + e8",
    "LD SP, HL",
    "LD A, [a16]",
    "EI",
    "ILLEGAL_FC",
    "ILLEGAL_FD",
    "CP A, n8",
    "RST $38",
};
