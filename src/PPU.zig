const PPU = @This();

const std = @import("std");
const Bus = @import("Bus.zig");
const LCD = @import("LCD.zig");
const Writer = @import("writer.zig");

pub const default_colors = [_]u32{ 0xFFFFFFFF, 0xAAAAAAFF, 0x555555FF, 0x000000FF };

pub const PPUMode = enum(u2) {
    oam_search = 2,
    pixel_transfer = 3,
    h_blank = 0,
    v_blank = 1,
};

const OAMEntry = packed struct(u32) {
    y: u8,
    x: u8,
    tile_index: u8,
    flags: packed struct(u8) {
        cgb_palette: u3,
        bank: u1,
        dmg_palette: u1,
        x_flip: bool,
        y_flip: bool,
        priority: u1,
    },
};

const FIFOEntry = struct {
    color: u2 = 0,
    palette: u1 = 0,
    background_priority: bool = false,
};
const FIFO = struct {
    data: [24]FIFOEntry,
    head: u4,
    tail: u4,
    size: u8,

    const empty_fifo: FIFO = .{
        .data = std.mem.zeroes([24]FIFOEntry),
        .tail = 0,
        .head = 0,
        .size = 0,
    };

    fn push(fifo: *FIFO, entry: FIFOEntry) void {
        fifo.data[fifo.tail] = entry;
        fifo.tail +%= 1;
        fifo.size += 1;
    }

    fn pop(fifo: *FIFO) FIFOEntry {
        const value = fifo.data[fifo.head];
        fifo.head +%= 1;
        fifo.size -= 1;
        return value;
    }
};

const PixelFifo = struct {
    state: enum {
        get_tile,
        get_tile_data_low,
        get_tile_data_high,
        sleep,
        push,
    } = .get_tile,
    background_fifo: FIFO = FIFO.empty_fifo,
    ticks: u1 = 0,

    x: u8 = 0,
    fifo_x: u16 = 0,
    pushed_x: u8 = 0,
    line_x: u8 = 0,
    color_data: [2]u8 = [2]u8{ 0, 0 },
    entry_data: [6]u8 = [_]u8{0} ** 6,

    tile_id: u8 = 0,

    fn tick(self: *PixelFifo, ppu: *PPU, lcd: *const LCD, bus: *const Bus) void {
        self.ticks ^= 1;
        if (self.ticks == 0) {
            return;
        }

        switch (self.state) {
            .get_tile => {
                ppu.fetched_entry_count = 0;

                if (lcd.lcd_control.data.background_and_window_enable) {
                    const tile_map_address: u16 = switch (lcd.lcd_control.data.background_tile_map_area) {
                        .a_9800_9BFF => 0x9800,
                        .a_9C00_9FFF => 0x9C00,
                    };

                    const bg_x: u8 = @truncate((@as(u16, self.x) + @as(u16, lcd.scroll_x)) & 0xFF);
                    const bg_y: u8 = @truncate((@as(u16, lcd.scroll_y) + lcd.lcd_y) & 0xFF);

                    self.tile_id = bus.read(tile_map_address + bg_x / 8 + 32 * @as(u16, bg_y / 8));
                    if (lcd.lcd_control.data.background_and_window_tile_data_area == .a_8800_97FF) {
                        self.tile_id +%= 128;
                    }

                    self.loadWindowTile(ppu, lcd, bus);
                }

                if (lcd.lcd_control.data.obj_enable and ppu.line_sprites != null) {
                    ppu.loadSpriteTile();
                }

                self.state = .get_tile_data_low;
                self.x += 8;
            },
            .get_tile_data_low => {
                const line = ((@as(u16, lcd.lcd_y) + lcd.scroll_y) % 8) * 2;
                const background_address: u16 = switch (lcd.lcd_control.data.background_and_window_tile_data_area) {
                    .a_8800_97FF => 0x8800,
                    .a_8000_8FFF => 0x8000,
                };
                self.color_data[0] = bus.read(background_address + @as(u16, self.tile_id) * 16 + line);

                ppu.loadSpriteData(bus, 0);

                self.state = .get_tile_data_high;
            },
            .get_tile_data_high => {
                const line = ((@as(u16, lcd.lcd_y) + lcd.scroll_y) % 8) * 2;
                const background_address: u16 = switch (lcd.lcd_control.data.background_and_window_tile_data_area) {
                    .a_8800_97FF => 0x8800,
                    .a_8000_8FFF => 0x8000,
                };
                self.color_data[1] = bus.read(background_address + @as(u16, self.tile_id) * 16 + line + 1);

                ppu.loadSpriteData(bus, 1);

                self.state = .sleep;
            },
            .sleep => {
                self.state = .push;
            },
            .push => {
                if (self.background_fifo.size <= 8) {
                    const x: i16 = @as(i16, self.x) - (8 - (lcd.scroll_x % 8));

                    var bit: u8 = 0;
                    while (bit < 8) : (bit += 1) {
                        const b: u3 = @truncate(7 - bit);

                        const hi: u8 = @intFromBool((self.color_data[0] & (@as(u8, 1) << b)) != 0);
                        const lo: u8 = @as(u8, @intFromBool((self.color_data[1] & (@as(u8, 1) << b)) != 0)) << 1;
                        var color = lcd.background_palette.get(@truncate(hi | lo));

                        if (!lcd.lcd_control.data.background_and_window_enable) {
                            color = lcd.background_palette.get(0);
                        }

                        if (lcd.lcd_control.data.obj_enable) {
                            color = ppu.fetchSpritePixels(color, @truncate(hi | lo));
                        }

                        if (x >= 0) {
                            self.background_fifo.push(.{ .color = color });
                            self.fifo_x += 1;
                        }
                    }

                    self.state = .get_tile;
                }
            },
        }
    }

    fn loadWindowTile(self: *PixelFifo, ppu: *const PPU, lcd: *const LCD, bus: *const Bus) void {
        if (!windowVisible(lcd)) {
            return;
        }

        const window_y = lcd.window_y;

        if (self.x + 7 >= lcd.window_x and
            @as(u16, self.x + 7) < @as(u16, lcd.window_x) + 144 + 14)
        {
            if (lcd.lcd_y >= window_y and lcd.lcd_y < window_y + 160) {
                const tile_map_address: u16 = switch (lcd.lcd_control.data.window_tile_map_area) {
                    .a_9800_9BFF => 0x9800,
                    .a_9C00_9FFF => 0x9C00,
                };

                const w_tile_x: u16 = @as(u16, self.x) + 7 - lcd.window_x;

                self.tile_id = bus.read(tile_map_address + w_tile_x / 8 + 32 * @as(u16, ppu.window_line / 8));
                if (lcd.lcd_control.data.background_and_window_tile_data_area == .a_8800_97FF) {
                    self.tile_id +%= 128;
                }
            }
        }
    }
};

lcd: *LCD,

oam_ram: [40]OAMEntry = std.mem.zeroes([40]OAMEntry),
vram: [0x2000]u8 = std.mem.zeroes([0x2000]u8),

pixel_fifo: PixelFifo = .{},

dots: u16 = 0,

pixel_buffers: [2][160 * 144]u32 = std.mem.zeroes([2][160 * 144]u32),
buffer_read_index: u1 = 0,
buffer_write_index: u1 = 1,

line_sprite_count: u8 = 0,
line_sprites: ?*OAMLineEntry = null,
line_entry_array: [10]OAMLineEntry = std.mem.zeroes([10]OAMLineEntry),

fetched_entry_count: u8 = 0,
fetched_entries: [3]OAMEntry = std.mem.zeroes([3]OAMEntry),
window_line: u8 = 0,

total_ticks: u64 = 0,

const OAMLineEntry = struct {
    entry: OAMEntry,
    next: ?*OAMLineEntry,
};

pub fn init(lcd: *LCD) PPU {
    const ppu: PPU = .{ .lcd = lcd };
    lcd.lcd_status.data.ppu_mode = .oam_search;
    return ppu;
}

pub fn write(ppu: *PPU, address: u16, value: u8) void {
    switch (address) {
        0xFF40 => {
            if ((value & (@as(u8, 1) << 7)) != 0 and !ppu.lcd.lcd_control.data.lcd_and_ppu_enable) {
                ppu.dots = 456 - 84;
            }
            ppu.lcd.write(address, value);
        },
        else => {},
    }
}

pub fn tick(ppu: *PPU, bus: *Bus) void {
    if (!ppu.lcd.lcd_control.data.lcd_and_ppu_enable) {
        return;
    }

    ppu.dots += 1;
    ppu.total_ticks += 1;
    switch (ppu.lcd.lcd_status.data.ppu_mode) {
        .oam_search => {
            if (ppu.dots > 80) {
                ppu.pixel_fifo.state = .get_tile;
                ppu.pixel_fifo.pushed_x = 0;
                ppu.pixel_fifo.x = 0;
                ppu.pixel_fifo.line_x = 0;
                ppu.pixel_fifo.fifo_x = 0;

                ppu.lcd.lcd_status.data.ppu_mode = .pixel_transfer;
            }

            if (ppu.dots == 1) {
                ppu.line_sprites = null;
                ppu.line_sprite_count = 0;
                ppu.loadLineSprites();
            }
        },
        .pixel_transfer => {
            ppu.pixel_fifo.tick(ppu, ppu.lcd, bus);
            ppu.pushPixel();

            if (ppu.pixel_fifo.pushed_x >= 160) {
                ppu.pixel_fifo.background_fifo = FIFO.empty_fifo;

                ppu.lcd.lcd_status.data.ppu_mode = .h_blank;
            }
        },
        .h_blank => {
            if (ppu.dots >= 456) {
                ppu.incrementLCDY(bus);

                if (ppu.lcd.lcd_y >= 144) {
                    ppu.lcd.lcd_status.data.ppu_mode = .v_blank;

                    bus.interrupt.flags.as_flags.vblank = true;

                    if (ppu.lcd.lcd_status.data.interrupt_enable.mode_1) {
                        bus.interrupt.flags.as_flags.lcd = true;
                    }
                } else {
                    ppu.lcd.lcd_status.data.ppu_mode = .oam_search;
                }

                ppu.dots = 0;
            }
        },
        .v_blank => {
            if (ppu.dots >= 456) {
                ppu.incrementLCDY(bus);

                if (ppu.lcd.lcd_y >= 154) {
                    ppu.lcd.lcd_status.data.ppu_mode = .oam_search;
                    ppu.lcd.lcd_y = 0;
                    ppu.window_line = 0;

                    ppu.buffer_write_index ^= 1;
                    ppu.buffer_read_index ^= 1;
                }

                ppu.dots = 0;
            }
        },
    }
}

pub fn oamRead(ppu: *const PPU, address: u16) u8 {
    const array = &ppu.oam_ram;
    const bytes = std.mem.asBytes(array);
    return bytes[address - 0xFE00];
}

pub fn oamWrite(ppu: *PPU, address: u16, value: u8) void {
    const array = &ppu.oam_ram;
    var bytes = std.mem.asBytes(array);
    bytes[address - 0xFE00] = value;
}

pub fn vramRead(ppu: *const PPU, address: u16) u8 {
    return ppu.vram[address - 0x8000];
}

pub fn vramWrite(ppu: *PPU, address: u16, value: u8) void {
    ppu.vram[address - 0x8000] = value;
}

fn windowVisible(lcd: *const LCD) bool {
    return lcd.lcd_control.data.window_enable and
        lcd.window_x >= 0 and lcd.window_x <= 166 and
        lcd.window_y >= 0 and lcd.window_y <= 144;
}

fn incrementLCDY(ppu: *PPU, bus: *Bus) void {
    if (windowVisible(ppu.lcd) and
        ppu.lcd.lcd_y >= ppu.lcd.window_y and
        ppu.lcd.lcd_y < ppu.lcd.window_y + 144)
    {
        ppu.window_line += 1;
    }

    ppu.lcd.lcd_y += 1;

    if (ppu.lcd.lcd_y == ppu.lcd.lcd_y_compare) {
        ppu.lcd.lcd_status.data.lcd_y_is_lcd_y_compare = true;

        if (ppu.lcd.lcd_status.data.interrupt_enable.lcd_y_compare) {
            bus.interrupt.flags.as_flags.lcd = true;
        }
    } else {
        ppu.lcd.lcd_status.data.lcd_y_is_lcd_y_compare = false;
    }
}

fn pushPixel(ppu: *PPU) void {
    if (ppu.pixel_fifo.background_fifo.size > 8) {
        const entry = ppu.pixel_fifo.background_fifo.pop();

        if (ppu.pixel_fifo.line_x >= (ppu.lcd.scroll_x % 8)) {
            ppu.pixel_buffers[ppu.buffer_write_index][@as(u16, ppu.pixel_fifo.pushed_x) + 160 * @as(u16, ppu.lcd.lcd_y)] = default_colors[entry.color];

            ppu.pixel_fifo.pushed_x += 1;
        }

        ppu.pixel_fifo.line_x += 1;
    }
}

fn loadLineSprites(ppu: *PPU) void {
    const sprite_height: u8 = switch (ppu.lcd.lcd_control.data.obj_size) {
        .s_8 => 8,
        .s_16 => 16,
    };

    ppu.line_entry_array = std.mem.zeroes([10]OAMLineEntry);

    for (&ppu.oam_ram) |entry| {
        if (entry.x == 0) {
            continue;
        }

        if (ppu.line_sprite_count >= 10) {
            continue;
        }

        if (entry.y <= ppu.lcd.lcd_y + 16 and entry.y + sprite_height > ppu.lcd.lcd_y + 16) {
            var e = &ppu.line_entry_array[ppu.line_sprite_count];
            ppu.line_sprite_count += 1;

            e.entry = entry;
            e.next = null;

            if (ppu.line_sprites == null or ppu.line_sprites.?.entry.x > entry.x) {
                e.next = ppu.line_sprites;
                ppu.line_sprites = e;
                continue;
            }

            var le = ppu.line_sprites;
            var prev = le;

            while (le) |l| {
                if (l.entry.x > entry.x) {
                    prev.?.next = e;
                    e.next = l;
                    break;
                }

                if (l.next == null) {
                    l.next = e;
                    break;
                }

                prev = l;
                le = l.next;
            }
        }
    }
}

fn loadSpriteTile(ppu: *PPU) void {
    var le = ppu.line_sprites;
    while (le) |l| {
        const sp_x = (l.entry.x - 8) + (ppu.lcd.scroll_x % 8);

        if ((sp_x >= ppu.pixel_fifo.x and sp_x < ppu.pixel_fifo.x + 8) or
            ((sp_x + 8) >= ppu.pixel_fifo.x and (sp_x + 8) < (ppu.pixel_fifo.x + 8)))
        {
            ppu.fetched_entries[ppu.fetched_entry_count] = l.entry;
            ppu.fetched_entry_count += 1;
        }

        le = l.next;

        if (le == null or ppu.fetched_entry_count >= 3) {
            break;
        }
    }
}

fn loadSpriteData(ppu: *PPU, bus: *const Bus, offset: u8) void {
    const sprite_height: u8 = switch (ppu.lcd.lcd_control.data.obj_size) {
        .s_8 => 8,
        .s_16 => 16,
    };

    for (ppu.fetched_entries[0..ppu.fetched_entry_count], 0..) |entry, i| {
        var ty = ((ppu.lcd.lcd_y + 16) - entry.y) * 2;

        if (entry.flags.y_flip) {
            ty = ((sprite_height * 2) - 2) - ty;
        }

        var tile_index = entry.tile_index;

        if (sprite_height == 16) {
            tile_index &= 0xFE;
        }

        ppu.pixel_fifo.entry_data[(i * 2) + offset] = bus.read(0x8000 + (@as(u16, tile_index) * 16) + ty + offset);
    }
}

fn fetchSpritePixels(ppu: *PPU, color: u2, bg_color: u2) u2 {
    var c = color;
    for (ppu.fetched_entries[0..ppu.fetched_entry_count], 0..) |entry, i| {
        const sp_x = (entry.x - 8) + (ppu.lcd.scroll_x % 8);

        if (sp_x + 8 <= ppu.pixel_fifo.fifo_x or ppu.pixel_fifo.fifo_x < sp_x) {
            continue;
        }

        const offset = ppu.pixel_fifo.fifo_x - sp_x;
        if (offset > 7) {
            continue;
        }

        var bit: u3 = @truncate(7 - offset);
        if (entry.flags.x_flip) {
            bit = @truncate(offset);
        }

        const hi: u8 = @intFromBool((ppu.pixel_fifo.entry_data[i * 2] & (@as(u8, 1) << bit)) != 0);
        const lo: u8 = @as(u8, @intFromBool((ppu.pixel_fifo.entry_data[i * 2 + 1] & (@as(u8, 1) << bit)) != 0)) << 1;

        const bg_priority = entry.flags.priority == 1;

        if ((hi | lo) == 0) {
            continue;
        }

        if (!bg_priority or bg_color == 0) {
            c = if (entry.flags.dmg_palette == 1) ppu.lcd.obj_palette_1.get(@truncate(hi | lo)) else ppu.lcd.obj_palette_0.get(@truncate(hi | lo));

            if ((hi | lo) != 0) {
                break;
            }
        }
    }

    return c;
}
