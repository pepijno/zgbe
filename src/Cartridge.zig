const Cartridge = @This();

const std = @import("std");

rom_data: []const u8,
header: RomHeader,

pub const RomHeader = extern struct {
    entry: [4]u8,
    logo: [0x30]u8,

    title: [15]u8,
    cgb_flag: u8,
    new_licensee_code: u16,
    sgb_flag: u8,
    type: u8,
    rom_size: u8,
    ram_size: u8,
    destination_code: u8,
    licensee_code: u8,
    version: u8,
    checksum: u8,
    global_checksum: u16,
};

pub fn open_cartridge(allocator: std.mem.Allocator, filename: []const u8) !Cartridge {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    const header = std.mem.bytesAsValue(RomHeader, content[0x100..]);

    return .{
        .rom_data = content,
        .header = header.*,
    };
}

pub fn read(cartridge: Cartridge, address: u16) u8 {
    return cartridge.rom_data[address];
}

pub fn write(cartridge: Cartridge, address: u16, value: u8) void {
    cartridge.rom_data[address] = value;
}

pub fn verifyChecksum(cartridge: Cartridge) bool {
    var x: u16 = 0;
    var i: u16 = 0x0134;
    while (i <= 0x014C) : (i += 1) {
        x = x -% cartridge.rom_data[i] -% 1;
    }
    return (x & 0xFF) == (cartridge.header.checksum);
}

pub fn printData(cartridge: Cartridge, writer: anytype) !void {
    var i: u32 = 0;
    while (i < cartridge.rom_data.len) : (i += 16) {
        try writer.print("0x{X:0>4}\t", .{i});
        var j: u32 = i;
        while (j < i + 8) : (j += 1) {
            const data = cartridge.rom_data[j];
            if (data == 0) {
                try writer.print(".. ", .{});
            } else {
                try writer.print("{X:0>2} ", .{data});
            }
        }
        try writer.print("  ", .{});
        while (j < i + 16) : (j += 1) {
            const data = cartridge.rom_data[j];
            if (data == 0) {
                try writer.print(".. ", .{});
            } else {
                try writer.print("{X:0>2} ", .{data});
            }
        }

        try writer.print("\n", .{});
    }
}

pub fn print(cartridge: Cartridge, writer: anytype) !void {
    const header = cartridge.header;
    try writer.print("Cartridge info:\n", .{});
    try writer.print("        Title:         {s}\n", .{header.title});
    try writer.print("        CGB Flag:      0x{X:0>2} ({s})\n", .{ header.cgb_flag, cgbFlagToString(header.cgb_flag) });
    try writer.print("        Type:          0x{X:0>2} ({s})\n", .{ header.type, romTypeAsString(header.type) });
    try writer.print("        ROM Size:      {} kB\n", .{@as(u64, 32) << @intCast(header.rom_size)});
    try writer.print("        RAM Size:      0x{X:0>2}\n", .{header.ram_size});
    try writer.print("        Destination:   0x{X:0>2}\n", .{header.destination_code});
    try writer.print("        Licensee Code: 0x{X:0>2} 0x{X:0>4} ({s})\n", .{ header.licensee_code, header.new_licensee_code, licenseeCodeAsString(header.licensee_code, header.new_licensee_code) });
    try writer.print("        ROM Version:   0x{X:0>2}\n", .{header.version});
    try writer.print("        Checksum:      0x{X:0>2} ({s})\n", .{ header.checksum, if (cartridge.verifyChecksum()) "PASSED" else "FAILED" });
    try writer.print("\n", .{});
}

fn cgbFlagToString(cgb_flag: u8) []const u8 {
    return switch (cgb_flag) {
        0x80 => "CGB and GB",
        0xC0 => "CGB Only",
        else => "UNKNOWN",
    };
}

fn romTypeAsString(rom_type: u8) []const u8 {
    return switch (rom_type) {
        0 => "ROM ONLY",
        1 => "MBC1",
        2 => "MBC1+RAM",
        3 => "MBC1+RAM+BATTERY",
        5 => "MBC2",
        6 => "MBC2+BATTERY",
        8 => "ROM+RAM 1",
        9 => "ROM+RAM+BATTERY 1",
        11 => "MMM01",
        12 => "MMM01+RAM",
        13 => "MMM01+RAM+BATTERY",
        15 => "MBC3+TIMER+BATTERY",
        16 => "MBC3+TIMER+RAM+BATTERY 2",
        17 => "MBC3",
        18 => "MBC3+RAM 2",
        19 => "MBC3+RAM+BATTERY 2",
        25 => "MBC5",
        26 => "MBC5+RAM",
        27 => "MBC5+RAM+BATTERY",
        28 => "MBC5+RUMBLE",
        29 => "MBC5+RUMBLE+RAM",
        30 => "MBC5+RUMBLE+RAM+BATTERY",
        32 => "MBC6",
        34 => "MBC7+SENSOR+RUMBLE+RAM+BATTERY",
        else => "UNKNOWN",
    };
}

fn newLicenseeCodeAsString(new_licensee_code: u16) []const u8 {
    return switch (new_licensee_code) {
        0x00 => "None",
        0x01 => "Nintendo Research & Development 1",
        0x08 => "Capcom",
        0x13 => "EA (Electronic Arts)",
        0x18 => "Hudson Soft",
        0x19 => "B-AI",
        0x20 => "KSS",
        0x22 => "Planning Office WADA",
        0x24 => "PCM Complete",
        0x25 => "San-X",
        0x28 => "Kemco",
        0x29 => "SETA Corporation",
        0x30 => "Viacom",
        0x31 => "Nintendo",
        0x32 => "Bandai",
        0x33 => "Ocean Software/Acclaim Entertainment",
        0x34 => "Konami",
        0x35 => "HectorSoft",
        0x37 => "Taito",
        0x38 => "Hudson Soft",
        0x39 => "Banpresto",
        0x41 => "Ubi Soft1",
        0x42 => "Atlus",
        0x44 => "Malibu Interactive",
        0x46 => "Angel",
        0x47 => "Bullet-Proof Software2",
        0x49 => "Irem",
        0x50 => "Absolute",
        0x51 => "Acclaim Entertainment",
        0x52 => "Activision",
        0x53 => "Sammy USA Corporation",
        0x54 => "Konami",
        0x55 => "Hi Tech Expressions",
        0x56 => "LJN",
        0x57 => "Matchbox",
        0x58 => "Mattel",
        0x59 => "Milton Bradley Company",
        0x60 => "Titus Interactive",
        0x61 => "Virgin Games Ltd.3",
        0x64 => "Lucasfilm Games4",
        0x67 => "Ocean Software",
        0x69 => "EA (Electronic Arts)",
        0x70 => "Infogrames5",
        0x71 => "Interplay Entertainment",
        0x72 => "Broderbund",
        0x73 => "Sculptured Software6",
        0x75 => "The Sales Curve Limited7",
        0x78 => "THQ",
        0x79 => "Accolade",
        0x80 => "Misawa Entertainment",
        0x83 => "lozc",
        0x86 => "Tokuma Shoten",
        0x87 => "Tsukuda Original",
        0x91 => "Chunsoft Co.8",
        0x92 => "Video System",
        0x93 => "Ocean Software/Acclaim Entertainment",
        0x95 => "Varie",
        0x96 => "Yonezawa/s’pal",
        0x97 => "Kaneko",
        0x99 => "Pack-In-Video",
        0xA4 => "Konami (Yu-Gi-Oh!)",
        else => "UNKNOWN",
    };
}

fn licenseeCodeAsString(licensee_code: u8, new_licensee_code: u16) []const u8 {
    return switch (licensee_code) {
        0x00 => "None",
        0x01 => "Nintendo",
        0x08 => "Capcom",
        0x09 => "HOT-B",
        0x0A => "Jaleco",
        0x0B => "Coconuts Japan",
        0x0C => "Elite Systems",
        0x13 => "EA (Electronic Arts)",
        0x18 => "Hudson Soft",
        0x19 => "ITC Entertainment",
        0x1A => "Yanoman",
        0x1D => "Japan Clary",
        0x1F => "Virgin Games Ltd.3",
        0x24 => "PCM Complete",
        0x25 => "San-X",
        0x28 => "Kemco",
        0x29 => "SETA Corporation",
        0x30 => "Infogrames5",
        0x31 => "Nintendo",
        0x32 => "Bandai",
        0x33 => newLicenseeCodeAsString(new_licensee_code),
        0x34 => "Konami",
        0x35 => "HectorSoft",
        0x38 => "Capcom",
        0x39 => "Banpresto",
        0x3C => "Entertainment Interactive (stub)",
        0x3E => "Gremlin",
        0x41 => "Ubi Soft1",
        0x42 => "Atlus",
        0x44 => "Malibu Interactive",
        0x46 => "Angel",
        0x47 => "Spectrum HoloByte",
        0x49 => "Irem",
        0x4A => "Virgin Games Ltd.3",
        0x4D => "Malibu Interactive",
        0x4F => "U.S. Gold",
        0x50 => "Absolute",
        0x51 => "Acclaim Entertainment",
        0x52 => "Activision",
        0x53 => "Sammy USA Corporation",
        0x54 => "GameTek",
        0x55 => "Park Place13",
        0x56 => "LJN",
        0x57 => "Matchbox",
        0x59 => "Milton Bradley Company",
        0x5A => "Mindscape",
        0x5B => "Romstar",
        0x5C => "Naxat Soft14",
        0x5D => "Tradewest",
        0x60 => "Titus Interactive",
        0x61 => "Virgin Games Ltd.3",
        0x67 => "Ocean Software",
        0x69 => "EA (Electronic Arts)",
        0x6E => "Elite Systems",
        0x6F => "Electro Brain",
        0x70 => "Infogrames5",
        0x71 => "Interplay Entertainment",
        0x72 => "Broderbund",
        0x73 => "Sculptured Software6",
        0x75 => "The Sales Curve Limited7",
        0x78 => "THQ",
        0x79 => "Accolade15",
        0x7A => "Triffix Entertainment",
        0x7C => "MicroProse",
        0x7F => "Kemco",
        0x80 => "Misawa Entertainment",
        0x83 => "LOZC G.",
        0x86 => "Tokuma Shoten",
        0x8B => "Bullet-Proof Software2",
        0x8C => "Vic Tokai Corp.16",
        0x8E => "Ape Inc.17",
        0x8F => "I’Max18",
        0x91 => "Chunsoft Co.8",
        0x92 => "Video System",
        0x93 => "Tsubaraya Productions",
        0x95 => "Varie",
        0x96 => "Yonezawa19/S’Pal",
        0x97 => "Kemco",
        0x99 => "Arc",
        0x9A => "Nihon Bussan",
        0x9B => "Tecmo",
        0x9C => "Imagineer",
        0x9D => "Banpresto",
        0x9F => "Nova",
        0xA1 => "Hori Electric",
        0xA2 => "Bandai",
        0xA4 => "Konami",
        0xA6 => "Kawada",
        0xA7 => "Takara",
        0xA9 => "Technos Japan",
        0xAA => "Broderbund",
        0xAC => "Toei Animation",
        0xAD => "Toho",
        0xAF => "Namco",
        0xB0 => "Acclaim Entertainment",
        0xB1 => "ASCII Corporation or Nexsoft",
        0xB2 => "Bandai",
        0xB4 => "Square Enix",
        0xB6 => "HAL Laboratory",
        0xB7 => "SNK",
        0xB9 => "Pony Canyon",
        0xBA => "Culture Brain",
        0xBB => "Sunsoft",
        0xBD => "Sony Imagesoft",
        0xBF => "Sammy Corporation",
        0xC0 => "Taito",
        0xC2 => "Kemco",
        0xC3 => "Square",
        0xC4 => "Tokuma Shoten",
        0xC5 => "Data East",
        0xC6 => "Tonkin House",
        0xC8 => "Koei",
        0xC9 => "UFL",
        0xCA => "Ultra Games",
        0xCB => "VAP, Inc.",
        0xCC => "Use Corporation",
        0xCD => "Meldac",
        0xCE => "Pony Canyon",
        0xCF => "Angel",
        0xD0 => "Taito",
        0xD1 => "SOFEL (Software Engineering Lab)",
        0xD2 => "Quest",
        0xD3 => "Sigma Enterprises",
        0xD4 => "ASK Kodansha Co.",
        0xD6 => "Naxat Soft14",
        0xD7 => "Copya System",
        0xD9 => "Banpresto",
        0xDA => "Tomy",
        0xDB => "LJN",
        0xDD => "Nippon Computer Systems",
        0xDE => "Human Ent.",
        0xDF => "Altron",
        0xE0 => "Jaleco",
        0xE1 => "Towa Chiki",
        0xE2 => "Yutaka # Needs more info",
        0xE3 => "Varie",
        0xE5 => "Epoch",
        0xE7 => "Athena",
        0xE8 => "Asmik Ace Entertainment",
        0xE9 => "Natsume",
        0xEA => "King Records",
        0xEB => "Atlus",
        0xEC => "Epic/Sony Records",
        0xEE => "IGS",
        0xF0 => "A Wave",
        0xF3 => "Extreme Entertainment",
        0xFF => "LJN",
        else => "UNKNOWN",
    };
}
