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
const CPU = @import("CPU.zig");
const Dma = @import("Dma.zig");
const Interrupt = @import("Interrupt.zig");
const LCD = @import("LCD.zig");
const PPU = @import("PPU.zig");
const Timer = @import("Timer.zig");

boot_rom: [0x100]u8 = std.mem.zeroes([0x100]u8),
rom: [0x8000]u8 = std.mem.zeroes([0x8000]u8),
ext_ram: [0x2000]u8 = std.mem.zeroes([0x2000]u8),
wram: [0x2000]u8 = std.mem.zeroes([0x2000]u8),
hram: [0x80]u8 = std.mem.zeroes([0x80]u8),
keys: u8 = 0xFF,
serial: [0x2]u8 = std.mem.zeroes([0x2]u8),
dmg_boot_rom: u8 = 0,
gbc_double: u8 = 0,

interrupt: *Interrupt,
cartridge: *Cartridge,
cpu: *CPU,
timer: *Timer,
ppu: *PPU,
lcd: *LCD,
dma: *Dma,

pub fn read(bus: *const Bus, address: u16) u8 {
    return switch (address) {
        0x0000...0x00FF => if (bus.dmg_boot_rom == 0) bus.boot_rom[address] else bus.cartridge.read(address),
        0x0100...0x7FFF => bus.cartridge.read(address),
        0x8000...0x9FFF => bus.ppu.vramRead(address),
        0xA000...0xBFFF => bus.ext_ram[address - 0xA000],
        0xC000...0xDFFF => bus.wram[address - 0xC000],
        0xE000...0xFDFF => bus.wram[address - 0xE000],
        0xFE00...0xFE9F => {
            if (bus.dma.running) {
                return 0xFF;
            }
            return bus.ppu.oamRead(address);
        },
        0xFEA0...0xFEFF => 0x00,
        0xFF00 => bus.keys,
        0xFF01...0xFF02 => bus.serial[address - 0xFF01],
        0xFF04...0xFF07 => bus.timer.read(address),
        0xFF10...0xFF26 => 0x00, // Ignore sound
        0xFF40...0xFF4B => bus.lcd.read(address),
        0xFF4D => bus.gbc_double,
        0xFF50 => bus.dmg_boot_rom,
        0xFF80...0xFFFE => bus.hram[address - 0xFF80],
        0xFF0F => bus.interrupt.flags.bit8,
        0xFFFF => bus.interrupt.enable.bit8,
        else => {
            // std.debug.print("cannot read from 0x{X:0>4}\n", .{address});
            return 0x00;
        },
    };
}

pub fn write(bus: *Bus, address: u16, value: u8) void {
    switch (address) {
        0x0000...0x7FFF => bus.cartridge.write(address, value),
        0x8000...0x9FFF => bus.ppu.vramWrite(address, value),
        0xA000...0xBFFF => bus.ext_ram[address - 0xA000] = value,
        0xC000...0xDFFF => bus.wram[address - 0xC000] = value,
        0xE000...0xFDFF => bus.wram[address - 0xE000] = value,
        0xFE00...0xFE9F => {
            if (!bus.dma.running) {
                bus.ppu.oamWrite(address, value);
            }
        },
        0xFEA0...0xFEFF => {},
        0xFF00 => bus.keys = value,
        0xFF01...0xFF02 => bus.serial[address - 0xFF01] = value,
        0xFF04...0xFF07 => bus.timer.write(address, value),
        0xFF0F => bus.interrupt.flags.bit8 = value,
        0xFF10...0xFF26 => {}, // Ignore sound
        0xFF40...0xFF45 => bus.lcd.write(address, value),
        0xFF46 => bus.dma.write(value),
        0xFF47...0xFF4B => bus.lcd.write(address, value),
        0xFF4D => bus.gbc_double = value,
        0xFF80...0xFFFE => bus.hram[address - 0xFF80] = value,
        0xFFFF => bus.interrupt.enable.bit8 = value,
        else => {
            // std.debug.print("cannot write to 0x{X:0>4}\n", .{address});
        },
    }
}
