const Memory = @This();

const std = @import("std");
const Cartridge = @import("Cartridge.zig");

data: [0x10000]u8 = std.mem.zeroes([0x10000]u8),

pub fn loadCartridge(memory: *Memory, cartridge: Cartridge) void {
    std.debug.print("0x{X}\n", .{cartridge.rom_data.len});
    std.mem.copyForwards(u8, memory.data[0..], cartridge.rom_data[0..0x7FFF]);
}

pub fn read8(memory: Memory, address: u16) u8 {
    return memory.data[address];
}

pub fn read16(memory: Memory, address: u16) u16 {
    return @as(u16, memory.data[address]) | (@as(u16, memory.data[address + 1]) << 8);
}

pub fn write8(memory: *Memory, address: u16, value: u8) void {
    memory.data[address] = value;
}

pub fn write16(memory: *Memory, address: u16, value: u16) void {
    memory.data[address] = @truncate(value & 0xFF);
    memory.data[address + 1] = @truncate((value & 0xFF00) >> 8);
}
