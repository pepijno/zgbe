const LCD = @This();

const std = @import("std");
const Dma = @import("Dma.zig");
const Bus = @import("Bus.zig");
const PPUMode = @import("PPU.zig").PPUMode;

pub const ColorPalette = packed union {
    data: packed struct {
        id0: u2,
        id1: u2,
        id2: u2,
        id3: u2,
    },
    bit8: u8,

    pub fn get(p: ColorPalette, index: u2) u2 {
        return switch (index) {
            0b00 => p.data.id0,
            0b01 => p.data.id1,
            0b10 => p.data.id2,
            0b11 => p.data.id3,
        };
    }
};

dma: *Dma,

lcd_control: packed union {
    data: packed struct {
        background_and_window_enable: bool,
        obj_enable: bool,
        obj_size: enum(u1) { s_8 = 0, s_16 = 1 },
        background_tile_map_area: enum(u1) { a_9800_9BFF = 0, a_9C00_9FFF = 1 },
        background_and_window_tile_data_area: enum(u1) { a_8800_97FF = 0, a_8000_8FFF = 1 },
        window_enable: bool,
        window_tile_map_area: enum(u1) { a_9800_9BFF = 0, a_9C00_9FFF = 1 },
        lcd_and_ppu_enable: bool,
    },
    bit8: u8,
} = .{ .bit8 = 0x91 },
lcd_status: packed union {
    data: packed struct {
        ppu_mode: PPUMode,
        lcd_y_is_lcd_y_compare: bool,
        interrupt_enable: packed struct {
            mode_0: bool,
            mode_1: bool,
            mode_2: bool,
            lcd_y_compare: bool,
        },
        _padding: u1,
    },
    bit8: u8,
} = .{ .bit8 = 0 },
scroll_y: u8 = 0,
scroll_x: u8 = 0,
lcd_y: u8 = 0,
lcd_y_compare: u8 = 0,
dma_reg: u8 = 0,
background_palette: ColorPalette = .{ .bit8 = 0xFC },
obj_palette_0: ColorPalette = .{ .bit8 = 0xFF },
obj_palette_1: ColorPalette = .{ .bit8 = 0xFF },
window_y: u8 = 0,
window_x: u8 = 0,

pub fn read(lcd: *const LCD, address: u16) u8 {
    return switch (address) {
        0xFF40 => lcd.lcd_control.bit8,
        0xFF41 => lcd.lcd_status.bit8,
        0xFF42 => lcd.scroll_y,
        0xFF43 => lcd.scroll_x,
        0xFF44 => lcd.lcd_y,
        0xFF45 => lcd.lcd_y_compare,
        0xFF46 => lcd.dma_reg,
        0xFF47 => lcd.background_palette.bit8,
        0xFF48 => lcd.obj_palette_0.bit8,
        0xFF49 => lcd.obj_palette_1.bit8,
        0xFF4A => lcd.window_y,
        0xFF4B => lcd.window_x,
        else => unreachable,
    };
}

pub fn write(lcd: *LCD, address: u16, value: u8) void {
    switch (address) {
        0xFF40 => lcd.lcd_control.bit8 = value,
        0xFF41 => lcd.lcd_status.bit8 = (value & 0xF8) | (lcd.lcd_status.bit8 & 0x07),
        0xFF42 => lcd.scroll_y = value,
        0xFF43 => lcd.scroll_x = value,
        0xFF44 => {},
        0xFF45 => lcd.lcd_y_compare = value,
        0xFF46 => {
            lcd.dma.write(value);
            lcd.dma_reg = value;
        },
        0xFF47 => lcd.background_palette.bit8 = value,
        0xFF48 => lcd.obj_palette_0.bit8 = value,
        0xFF49 => lcd.obj_palette_1.bit8 = value,
        0xFF4A => lcd.window_y = value,
        0xFF4B => lcd.window_x = value,
        else => unreachable,
    }
}
