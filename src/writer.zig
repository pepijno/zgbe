const std = @import("std");

pub var bw = std.io.bufferedWriter(std.io.getStdOut().writer());
pub var stdout = bw.writer();
