const std = @import("std");

const Cartridge = @import("Cartridge.zig");

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const cartridge = try Cartridge.open_cartridge(allocator, "cpu_instrs.gb");
    try cartridge.print(stdout);

    try bw.flush();
}
