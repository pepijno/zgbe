const Timer = @This();

const std = @import("std");
const Bus = @import("Bus.zig");

div: u16 = 0x0,
tima: u8 = 0,
tma: u8 = 0,
tac: u8 = 0,

pub fn initBeforeBoot() Timer {
    return .{
        .div = 0x0000,
        .tima = 0x00,
        .tma = 0x00,
        .tac = 0x00,
    };
}

pub fn initAfterBoot() Timer {
    return .{
        .div = 0xABCC,
        .tima = 0x00,
        .tma = 0x00,
        .tac = 0x00,
    };
}

pub fn tick(timer: *Timer, bus: *Bus) void {
    const previous_div = timer.div;
    timer.div +%= 1;

    var update_timer = false;

    switch (@as(u2, @truncate(timer.tac & 0x3))) {
        0x0 => update_timer = (previous_div & (1 << 9)) != 0 and (timer.div & (1 << 9)) == 0,
        0x1 => update_timer = (previous_div & (1 << 3)) != 0 and (timer.div & (1 << 3)) == 0,
        0x2 => update_timer = (previous_div & (1 << 5)) != 0 and (timer.div & (1 << 5)) == 0,
        0x3 => update_timer = (previous_div & (1 << 7)) != 0 and (timer.div & (1 << 7)) == 0,
    }

    if (update_timer and (timer.tac & (1 << 2)) != 0) {
        timer.tima +%= 1;

        if (timer.tima == 0xFF) {
            timer.tima = timer.tma;

            var flags = bus.read8(0xFF0F);
            flags |= (1 << 2);
            bus.write8(0xFF0F, flags);
        }
    }
}

pub fn read(timer: *Timer, address: u16) u8 {
    return switch (address) {
        0xFF04 => @truncate((timer.div >> 8) & 0xFF),
        0xFF05 => timer.tima,
        0xFF06 => timer.tma,
        0xFF07 => timer.tac,
        else => unreachable,
    };
}

pub fn write(timer: *Timer, address: u16, value: u8) void {
    switch (address) {
        0xFF04 => timer.div = 0x0000,
        0xFF05 => timer.tima = value,
        0xFF06 => timer.tma = value,
        0xFF07 => timer.tac = value,
        else => unreachable,
    }
}

pub fn printState(timer: *Timer, writer: anytype) !void {
    try writer.print("DIV:{X:0>4} TIMA:{X:0>2} TMA:{X:0>2} TAC:{X:0>2}\n", .{
        timer.div,
        timer.tima,
        timer.tma,
        timer.tac,
    });
}
