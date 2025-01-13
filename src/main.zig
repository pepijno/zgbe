const std = @import("std");

const Memory = @import("Memory.zig");
const Cartridge = @import("Cartridge.zig");
const Cpu = @import("Cpu.zig");

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const cartridge = try Cartridge.open_cartridge(allocator, "cpu_instrs.gb");
    try cartridge.print(stdout);

    var cpu = Cpu.init();
    var memory = Memory{};
    memory.loadCartridge(cartridge);

    cpu.cpuRun(&memory);

    try bw.flush();
}
