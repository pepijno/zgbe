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
