const Clock = @This();

const std = @import("std");
const CPU = @import("CPU.zig");
const PPU = @import("PPU.zig");
const Dma = @import("Dma.zig");
const Bus = @import("Bus.zig");
const Timer = @import("Timer.zig");

ticks: u64 = 0,

pub fn run(clock: *Clock, bus: *Bus, cpu: *CPU, timer: *Timer, dma: *Dma, ppu: *PPU) void {
    while (cpu.running) {
        clock.tick(bus, cpu, timer, dma, ppu);
    }
}

fn tick(clock: *Clock, bus: *Bus, cpu: *CPU, timer: *Timer, dma: *Dma, ppu: *PPU) void {
    clock.ticks +%= 1;

    cpu.tick(bus);

    for (0..4) |_| {
        ppu.tick(bus);
    }
    timer.tick(bus);
    dma.tick(bus);

    if (bus.read8(0xFF02) == 0x81) {
        std.debug.print("{c}", .{bus.read8(0xFF01)});
        bus.write8(0xFF02, 0x0);
    }
}
