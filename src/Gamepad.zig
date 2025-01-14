const Gamepad = @This();

const std = @import("std");

data: extern union {
    keys: packed struct(u8) {
        up: bool,
        down: bool,
        left: bool,
        right: bool,
        a: bool,
        b: bool,
        select: bool,
        start: bool,
    },
    bit8: u8,
} = .{ .bit8 = 0x00 },
