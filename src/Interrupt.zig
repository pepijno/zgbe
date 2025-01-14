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

pub fn tick(interrupt: *Interrupt, bus: *Bus) u8 {
    if ((interrupt.flags.bit8 & interrupt.enable.bit8) != 0) {
        var cpu = bus.cpu;
        cpu.halted = false;
        if (interrupt.master_enable) {
            const flags = InterruptFlags{ .bit8 = interrupt.flags.bit8 & interrupt.enable.bit8 };
            interrupt.master_enable = false;
            interrupt.master_enable_next_instruction = false;

            if (flags.as_flags.vblank) {
                cpu.writeToStack16(bus, cpu.program_counter);
                cpu.program_counter = 0x0040;
                interrupt.flags.as_flags.vblank = false;
                return 5;
            } else if (flags.as_flags.lcd) {
                cpu.writeToStack16(bus, cpu.program_counter);
                cpu.program_counter = 0x0048;
                interrupt.flags.as_flags.lcd = false;
                return 5;
            } else if (flags.as_flags.timer) {
                cpu.writeToStack16(bus, cpu.program_counter);
                cpu.program_counter = 0x0050;
                interrupt.flags.as_flags.timer = false;
                return 5;
            } else if (flags.as_flags.serial) {
                cpu.writeToStack16(bus, cpu.program_counter);
                cpu.program_counter = 0x0058;
                interrupt.flags.as_flags.serial = false;
                return 5;
            } else if (flags.as_flags.joypad) {
                cpu.writeToStack16(bus, cpu.program_counter);
                cpu.program_counter = 0x0060;
                interrupt.flags.as_flags.joypad = false;
                return 5;
            }
        }
    }

    if (interrupt.master_enable_next_instruction) {
        interrupt.master_enable = true;
        interrupt.master_enable_next_instruction = false;
    }

    return 0;
}
