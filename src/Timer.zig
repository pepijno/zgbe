const Timer = @This();

const std = @import("std");
const Bus = @import("Bus.zig");

cpu_clock: u16 = 0x00,
falling_edge_detector_delay: u8 = 0,
tima_overflowing: bool = false,
tma_to_tima_transferring: bool = false,
div: u8 = 0x0,
tima: u8 = 0,
tma: u8 = 0,
tac: u8 = 0,

pub fn initBeforeBoot() Timer {
    return .{
        .div = 0x00,
        .tima = 0x00,
        .tma = 0x00,
        .tac = 0x00,
    };
}

pub fn initAfterBoot() Timer {
    return .{
        .div = 0xAB,
        .tima = 0x00,
        .tma = 0x00,
        .tac = 0x00,
    };
}

pub fn divider(timer: Timer) u8 {
    return @truncate(timer.div >> 8);
}

const freq_dividers = [_]u16{ 1024, 16, 64, 256 };

fn timaBit(timer: *const Timer) u8 {
    return switch (@as(u2, @truncate(timer.tac & 0b11))) {
        0b00 => @truncate((timer.cpu_clock >> 7) & 0x1),
        0b01 => @truncate((timer.cpu_clock >> 1) & 0x1),
        0b10 => @truncate((timer.cpu_clock >> 3) & 0x1),
        0b11 => @truncate((timer.cpu_clock >> 5) & 0x1),
    };
}

fn incrementTima(timer: *Timer) void {
    timer.tima +%= 1;

    if (timer.tima == 0) {
        timer.tima_overflowing = true;
    }
}

pub fn tick(timer: *Timer, bus: *Bus) void {
    const tima_running = (timer.tac & 0x04) != 0;

    timer.cpu_clock +%= 1;
    timer.div = @truncate(timer.cpu_clock >> 6);

    if (timer.tma_to_tima_transferring) {
        timer.tma_to_tima_transferring = false;
    }

    var interrupt = false;

    if (timer.tima_overflowing) {
        timer.tima = timer.tma;
        timer.tima_overflowing = false;
        timer.tma_to_tima_transferring = true;
        interrupt = true;
    }

    const tima_bit = timer.timaBit();

    var falling_edge_detector_input: u8 = 0;
    if (tima_running and tima_bit == 1) {
        falling_edge_detector_input = 1;
    }

    if (falling_edge_detector_input == 0 and timer.falling_edge_detector_delay == 1) {
        timer.incrementTima();
    }

    timer.falling_edge_detector_delay = falling_edge_detector_input;

    if (interrupt) {
        var flags = bus.read8(0xFF0F);
        // std.debug.print("{X:0>2}\n", .{flags});
        flags |= (1 << 2);
        bus.write8(0xFF0F, flags);
    }
}

pub fn read(timer: *Timer, address: u16) u8 {
    return switch (address) {
        0xFF04 => timer.div,
        0xFF05 => timer.tima,
        0xFF06 => timer.tma,
        0xFF07 => timer.tac & 0b111,
        else => unreachable,
    };
}

pub fn write(timer: *Timer, address: u16, value: u8) void {
    switch (address) {
        0xFF04 => {
            timer.div = 0x0000;
        },
        0xFF05 => {
            if (timer.tima_overflowing) {
                timer.tima_overflowing = false;
                timer.tima = value;
            } else if (timer.tma_to_tima_transferring) {} else {
                timer.tima = value;
            }
        },
        0xFF06 => {
            timer.tma = value;
            if (timer.tma_to_tima_transferring) {
                timer.tima = value;
            }
        },
        0xFF07 => {
            timer.tac = (value & 0b111) | (timer.tac & 0b11111000);

            const tima_running = (timer.tac & 0x4) != 0;
            const new_tima_bit = timer.timaBit();

            if (timer.falling_edge_detector_delay == 1 and (!tima_running or new_tima_bit == 0)) {
                timer.incrementTima();
            }
        },
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

// test "div" {
//     var timer = Timer.initBeforeBoot();
//
//     for (0..256) |_| {
//         _ = timer.tick();
//     }
//
//     try std.testing.expectEqual(1, timer.divider());
//
//     for (0..512) |_| {
//         _ = timer.tick();
//     }
//
//     try std.testing.expectEqual(3, timer.divider());
// }
//
// test "tima" {
//     var timer = Timer.initBeforeBoot();
//     timer.tac = 0x07;
//
//     for (0..255) |_| {
//         _ = timer.tick();
//     }
//
//     try std.testing.expectEqual(0, timer.tima);
//     _ = timer.tick();
//     try std.testing.expectEqual(1, timer.tima);
//
//     timer = Timer.initBeforeBoot();
//     timer.tac = 0x05;
//
//     for (0..64) |_| {
//         _ = timer.tick();
//     }
//     try std.testing.expectEqual(4, timer.tima);
// }
//
// test "tima overflow" {
//     var timer = Timer.initBeforeBoot();
//     timer.tac = 0x05;
//
//     for (0..(16 * 0xFF + 15)) |_| {
//         const int = timer.tick();
//         try std.testing.expectEqual(false, int);
//     }
//     const int = timer.tick();
//     try std.testing.expect(int);
// }
