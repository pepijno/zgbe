const Dma = @This();

const std = @import("std");
const Bus = @import("Bus.zig");
const Writer = @import("writer.zig");

running: bool = false,
start_delay: u2 = 0,
byte: u8 = 0,
value: u8 = 0,

pub fn write(dma: *Dma, start_value: u8) void {
    dma.running = true;
    dma.byte = 0;
    dma.start_delay = 2;
    dma.value = start_value;
}

pub fn tick(dma: *Dma, bus: *Bus) void {
    if (!dma.running) {
        return;
    }

    if (dma.start_delay != 0) {
        dma.start_delay -= 1;
        return;
    }

    const value = getValue(bus, @as(u16, dma.value) * 0x100 + @as(u16, dma.byte));
    bus.write(0xFE00 + @as(u16, dma.byte), value);

    dma.byte += 1;
    dma.running = dma.byte < 0xA0;

    if (!dma.running) {
        // std.debug.print("DMA done\n", .{});
    }
}

fn getValue(bus: *Bus, address: u16) u8 {
    return switch (@as(u8, @truncate(address >> 8))) {
        0x00...0xDF => bus.read(address),
        0xE0...0xFF => bus.read(address - 0x2000),
    };
}
