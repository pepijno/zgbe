const Bus = @This();

//0000h – 3FFFh ROM0 Non-switchable ROM Bank.
//4000h – 7FFFh ROMX Switchable ROM bank.
//8000h – 9FFFh VRAM Video RAM, switchable (0-1) in GBC mode.
//A000h – BFFFh SRAM External RAM in cartridge, often battery buffered.
//C000h – CFFFh WRAM0 Work RAM.
//D000h – DFFFh WRAMX Work RAM, switchable (1-7) in GBC mode
//E000h – FDFFh ECHO Description of the behaviour below.
//FE00h – FE9Fh OAM (Object Attribute Table) Sprite information table.
//FEA0h – FEFFh UNUSED Description of the behaviour below.
//FF00h – FF7Fh I/O Registers I/O registers are mapped here.
//FF80h – FFFEh HRAM Internal CPU RAM
//FFFFh IE Register Interrupt enable flags.

const std = @import("std");
const Cartridge = @import("Cartridge.zig");
const Cpu = @import("Cpu.zig");
const Interrupt = @import("Interrupt.zig");
const Timer = @import("Timer.zig");

boot_rom: [0x100]u8 = std.mem.zeroes([0x100]u8),
rom: [0x8000]u8 = std.mem.zeroes([0x8000]u8),
vram: [0x2000]u8 = std.mem.zeroes([0x2000]u8),
ext_ram: [0x2000]u8 = std.mem.zeroes([0x2000]u8),
wram: [0x2000]u8 = std.mem.zeroes([0x2000]u8),
oam_ram: [0xA0]u8 = std.mem.zeroes([0xA0]u8),
hram: [0x80]u8 = std.mem.zeroes([0x80]u8),
keys: u8 = 0xFF,
serial: [0x2]u8 = std.mem.zeroes([0x2]u8),
dmg_boot_rom: u8 = 0,

interrupt: *Interrupt,
cartridge: *Cartridge,
cpu: *Cpu,
timer: *Timer,

pub fn read8(bus: Bus, address: u16) u8 {
    return switch (address) {
        0x0000...0x00FF => if (bus.dmg_boot_rom == 0) bus.boot_rom[address] else bus.cartridge.read(address),
        0x0100...0x7FFF => bus.cartridge.read(address),
        0x8000...0x9FFF => bus.vram[address - 0x8000],
        0xA000...0xBFFF => bus.ext_ram[address - 0xA000],
        0xC000...0xDFFF => bus.wram[address - 0xC000],
        0xE000...0xFDFF => bus.wram[address - 0xE000],
        0xFE00...0xFE9F => bus.oam_ram[address - 0xFE00],
        0xFF00 => bus.keys,
        0xFF01...0xFF02 => bus.serial[address - 0xFF01],
        0xFF04...0xFF07 => bus.timer.read(address),
        0xFF44 => 0x90,
        0xFF50 => bus.dmg_boot_rom,
        0xFF80...0xFFFE => bus.hram[address - 0xFF80],
        0xFF0F => bus.interrupt.flags.bit8,
        0xFFFF => bus.interrupt.enable.bit8,
        else => 0,
    };
}

pub fn read16(bus: Bus, address: u16) u16 {
    return @as(u16, bus.read8(address)) | (@as(u16, bus.read8(address + 1)) << 8);
}

pub fn write8(bus: *Bus, address: u16, value: u8) void {
    switch (address) {
        0x8000...0x9FFF => bus.vram[address - 0x8000] = value,
        0xA000...0xBFFF => bus.ext_ram[address - 0x000] = value,
        0xC000...0xDFFF => bus.wram[address - 0xC000] = value,
        0xE000...0xFDFF => bus.wram[address - 0xE000] = value,
        0xFE00...0xFE9F => bus.oam_ram[address - 0xFE00] = value,
        0xFF00 => bus.keys = value,
        0xFF01...0xFF02 => bus.serial[address - 0xFF01] = value,
        0xFF04...0xFF07 => bus.timer.write(address, value),
        0xFF80...0xFFFE => bus.hram[address - 0xFF80] = value,
        0xFF0F => bus.interrupt.flags.bit8 = value,
        0xFFFF => bus.interrupt.enable.bit8 = value,
        else => {
            // std.debug.print("cannot write to 0x{X:0>4}\n", .{address});
        },
    }
}

pub fn write16(bus: *Bus, address: u16, value: u16) void {
    bus.write8(address, @truncate(value & 0xFF));
    bus.write8(address + 1, @truncate((value & 0xFF00) >> 8));
}
