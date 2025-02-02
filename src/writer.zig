const std = @import("std");

pub var bw = std.io.bufferedWriter(std.io.getStdOut().writer());
pub var stdout = bw.writer();

pub fn writeDebug(comptime format: []const u8, args: anytype) void {
    if (comptime false) {
        stdout.print(format, args) catch unreachable;
    }
}
