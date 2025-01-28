const Clock = @This();

const std = @import("std");
const CPU = @import("CPU.zig");
const PPU = @import("PPU.zig");
const Dma = @import("Dma.zig");
const Bus = @import("Bus.zig");
const Timer = @import("Timer.zig");

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

var manual = false;

fn tick(clock: *Clock, bus: *Bus, cpu: *CPU, timer: *Timer, dma: *Dma, ppu: *PPU) void {
    clock.ticks +%= 1;

    if (cpu.instruction_queue.len == 0 and !cpu.halted) {
        if (bus.read(cpu.program_counter.bit16) == 0xCB and bus.read(cpu.program_counter.bit16 + 1) == 0x4E) {
            manual = true;
        }
    }

    cpu.tick(bus);

    for (0..4) |_| {
        ppu.tick(bus);
    }
    timer.tick(bus);
    dma.tick(bus);

    if (bus.read(0xFF02) == 0x81) {
        std.debug.print("{c}", .{bus.read(0xFF01)});
        bus.write(0xFF02, 0x0);
    }
}
