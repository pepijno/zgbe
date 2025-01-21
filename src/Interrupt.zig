const Interrupt = @This();

const std = @import("std");
const Bus = @import("Bus.zig");

master_enable: bool = false,
master_enable_next_instruction: bool = false,
flags: InterruptFlags = .{ .bit8 = 0 },
enable: InterruptFlags = .{ .bit8 = 0 },

pub const InterruptFlags = extern union {
    as_flags: packed struct(u8) {
        vblank: bool,
        lcd: bool,
        timer: bool,
        serial: bool,
        joypad: bool,
        _padding: u3,
    },
    bit8: u8,
};

pub fn tick(interrupt: *Interrupt, bus: *Bus) void {
    if ((interrupt.flags.bit8 & interrupt.enable.bit8) != 0) {
        var cpu = bus.cpu;
        cpu.halted = false;
        if (interrupt.master_enable) {
            bus.tick(2);
            const flags = InterruptFlags{ .bit8 = interrupt.flags.bit8 & interrupt.enable.bit8 };
            interrupt.master_enable = false;
            interrupt.master_enable_next_instruction = false;

            if (flags.as_flags.vblank) {
                cpu.writeToStack16(bus, cpu.program_counter);
                bus.tick(2);
                cpu.program_counter = 0x0040;
                bus.tick(1);
                interrupt.flags.as_flags.vblank = false;
            } else if (flags.as_flags.lcd) {
                cpu.writeToStack16(bus, cpu.program_counter);
                bus.tick(2);
                cpu.program_counter = 0x0048;
                bus.tick(1);
                interrupt.flags.as_flags.lcd = false;
            } else if (flags.as_flags.timer) {
                cpu.writeToStack16(bus, cpu.program_counter);
                bus.tick(2);
                cpu.program_counter = 0x0050;
                bus.tick(1);
                interrupt.flags.as_flags.timer = false;
            } else if (flags.as_flags.serial) {
                cpu.writeToStack16(bus, cpu.program_counter);
                bus.tick(2);
                cpu.program_counter = 0x0058;
                bus.tick(1);
                interrupt.flags.as_flags.serial = false;
            } else if (flags.as_flags.joypad) {
                cpu.writeToStack16(bus, cpu.program_counter);
                bus.tick(2);
                cpu.program_counter = 0x0060;
                bus.tick(1);
                interrupt.flags.as_flags.joypad = false;
            }
        }
    }

    if (interrupt.master_enable_next_instruction) {
        interrupt.master_enable = true;
        interrupt.master_enable_next_instruction = false;
    }
}
