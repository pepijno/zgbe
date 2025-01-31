const std = @import("std");
const raylib = @import("raylib.zig");

const Clock = @import("Clock.zig");
const Bus = @import("Bus.zig");
const Cartridge = @import("Cartridge.zig");
const CPU = @import("CPU.zig");
const Dma = @import("Dma.zig");
const Gamepad = @import("Gamepad.zig");
const Interrupt = @import("Interrupt.zig");
const LCD = @import("LCD.zig");
const PPU = @import("PPU.zig");
const Timer = @import("Timer.zig");

fn drawTile(bus: *Bus, scale: u32, address: u16, tile_num: u16, x: u32, y: u32) void {
    var tile_y: u16 = 0;
    while (tile_y < 16) : (tile_y += 2) {
        const b1: u8 = bus.read(address + tile_num * 16 + tile_y);
        const b2: u8 = bus.read(address + tile_num * 16 + tile_y + 1);

        for (0..8) |bit| {
            const bit_: u3 = @truncate(bit);
            const hi_set: u1 = @bitCast((b1 & (@as(u8, 1) << bit_)) != 0);
            const lo_set: u1 = @bitCast((b2 & (@as(u8, 1) << bit_)) != 0);
            const hi = @as(u2, hi_set) << 1;
            const lo = @as(u2, lo_set);

            const color_idx = hi | lo;
            const color = PPU.default_colors[color_idx];

            const pos_x = x + (7 - bit_) * scale;
            const pos_y = y + (tile_y / 2) * scale;
            raylib.DrawRectangle(@intCast(pos_x), @intCast(pos_y), @intCast(scale), @intCast(scale), raylib.GetColor(color));
        }
    }
}

fn updateDebugWindow(bus: *Bus, start_x: u32, scale: u32) void {
    const address: u16 = 0x8000;
    var x_draw: u32 = start_x;
    var y_draw: u32 = 0;
    var tile_num: u16 = 0;

    for (0..24) |_| {
        for (0..16) |_| {
            drawTile(bus, scale, address, tile_num, x_draw, y_draw);
            x_draw += (8 * scale + 1);
            tile_num += 1;
        }
        y_draw += 8 * scale + 1;
        x_draw = start_x;
    }
}

fn updateWindow(ppu: *const PPU, scale: u32) void {
    for (0..144) |y| {
        for (0..160) |x| {
            const x_draw = scale * x;
            const y_draw = scale * y;
            const color = ppu.pixel_buffers[ppu.buffer_read_index][160 * y + x];
            raylib.DrawRectangle(@intCast(x_draw), @intCast(y_draw), @intCast(scale), @intCast(scale), raylib.GetColor(color));
        }
    }
}

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const file = try std.fs.cwd().openFile("dmg_boot.bin", .{});
    defer file.close();

    var boot_rom: [0x100]u8 = std.mem.zeroes([0x100]u8);
    _ = try file.read(&boot_rom);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const file_name = if (args.len < 2) "roms/cpu_instrs.gb" else args[1];

    var cartridge = try Cartridge.open_cartridge(allocator, file_name);
    // try cartridge.print(stdout);
    // try cartridge.printData(stdout);
    // try bw.flush();

    var clock = Clock{};
    var interrupt = Interrupt{};
    var cpu = CPU.initAfterBoot();
    cpu.halted = false;
    cpu.running = true;
    // cvar gamepad = Gamepad{};
    var timer = Timer.initAfterBoot();
    var dma = Dma{};
    var lcd = LCD{ .dma = &dma };
    var ppu = PPU.init(&lcd);
    var bus = Bus{
        .boot_rom = boot_rom,
        .dmg_boot_rom = 1,
        .interrupt = &interrupt,
        .cartridge = &cartridge,
        .cpu = &cpu,
        .ppu = &ppu,
        .timer = &timer,
        .lcd = &lcd,
        .dma = &dma,
    };

    const scale = 4;
    const debug_scale = 2;
    const screen_width = 20 * 8 * scale + 20 + 16 * (8 + 1) * debug_scale;
    const screen_height = 18 * 8 * scale;

    raylib.InitWindow(screen_width, screen_height, "raylib [core] example - basic window");
    defer raylib.CloseWindow(); // Close window and OpenGL context
    raylib.SetTargetFPS(60);

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    _ = try std.Thread.spawn(.{}, Clock.run, .{ &clock, &bus, &cpu, &timer, &dma, &ppu });

    // while (true)
    while (!raylib.WindowShouldClose()) // Detect window close button or ESC key
    {
        // Update
        //----------------------------------------------------------------------------------
        //----------------------------------------------------------------------------------
        // if (raylib.IsKeyDown(raylib.KEY_RIGHT)) {
        //     gamepad.data.keys.right = true;
        // }

        // Draw
        //----------------------------------------------------------------------------------
        raylib.BeginDrawing();
        defer raylib.EndDrawing();

        raylib.ClearBackground(raylib.RAYWHITE);
        updateWindow(&ppu, scale);
        updateDebugWindow(&bus, 20 * 8 * scale + 20, debug_scale);
        raylib.DrawFPS(10, 10);
        //----------------------------------------------------------------------------------
    }

    try stdout.print("{s}\n", .{buffer.items});

    try bw.flush();
}

test {
    _ = @import("Timer.zig");
}
