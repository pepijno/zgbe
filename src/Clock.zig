const Clock = @This();

const std = @import("std");
const CPU = @import("CPU.zig");
const PPU = @import("PPU.zig");
const Dma = @import("Dma.zig");
const Bus = @import("Bus.zig");
const Timer = @import("Timer.zig");
const Writer = @import("writer.zig");

ticks: u64 = 0,
nano_last_cycle: i128 = 0,

pub fn run(clock: *Clock, bus: *Bus, cpu: *CPU, timer: *Timer, dma: *Dma, ppu: *PPU) void {
    clock.nano_last_cycle = std.time.nanoTimestamp();
    while (cpu.running) {
        clock.tick(bus, cpu, timer, dma, ppu);
        // if ((clock.ticks & 1023) == 0) {
        //     const nano_after = std.time.nanoTimestamp();
        //     const cycle_time: i128 = @max(0, 976562 - (nano_after - clock.nano_last_cycle));
        //     std.time.sleep(@intCast(cycle_time));
        //     clock.nano_last_cycle = nano_after;
        // }
    }
}

pub fn runSteps(clock: *Clock, bus: *Bus, cpu: *CPU, timer: *Timer, dma: *Dma, ppu: *PPU, steps: u64) void {
    for (0..steps) |_| {
        clock.tick(bus, cpu, timer, dma, ppu);
    }
}

fn tick(clock: *Clock, bus: *Bus, cpu: *CPU, timer: *Timer, dma: *Dma, ppu: *PPU) void {
    clock.ticks +%= 1;

    cpu.tick(bus);
    dma.tick(bus);
    for (0..4) |_| {
        ppu.tick(bus);
    }
    timer.tick(bus);

    if (bus.read(0xFF02) == 0x81) {
        std.debug.print("{c}", .{bus.read(0xFF01)});
        bus.write(0xFF02, 0x0);
    }

    if ((clock.ticks % 10000) == 0) {
        Writer.bw.flush() catch unreachable;
    }
}
