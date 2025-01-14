const std = @import("std");
const raylib = @import("raylib.zig");

const Bus = @import("Bus.zig");
const Cartridge = @import("Cartridge.zig");
const Cpu = @import("Cpu.zig");
const Gamepad = @import("Gamepad.zig");
const Interrupt = @import("Interrupt.zig");
const Timer = @import("Timer.zig");

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

    var cartridge = try Cartridge.open_cartridge(allocator, "02-interrupts.gb");
    // try cartridge.print(stdout);

    var interrupt = Interrupt{};
    var cpu = Cpu.initAfterBoot();
    // cvar gamepad = Gamepad{};
    var timer = Timer.initAfterBoot();
    var bus = Bus{
        .boot_rom = boot_rom,
        .dmg_boot_rom = 1,
        .interrupt = &interrupt,
        .cartridge = &cartridge,
        .cpu = &cpu,
        .timer = &timer,
    };

    // const screen_width = 800;
    // const screen_height = 450;

    // raylib.InitWindow(screen_width, screen_height, "raylib [core] example - basic window");
    // defer raylib.CloseWindow(); // Close window and OpenGL context

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    var i: u8 = 0;
    cpu.running = true;
    try cpu.printState(bus, stdout);
    while (true) : (i += 1)
    // while (!raylib.WindowShouldClose()) // Detect window close button or ESC key
    {
        // Update
        //----------------------------------------------------------------------------------
        //----------------------------------------------------------------------------------
        // if (raylib.IsKeyDown(raylib.KEY_RIGHT)) {
        //     gamepad.data.keys.right = true;
        // }

        const m_cycles_interrupt = interrupt.tick(&bus);
        const m_cycles_cpu = cpu.tick(&bus);
        for (0..(m_cycles_interrupt + m_cycles_cpu)) |_| {
            for (0..4) |_| {
                timer.tick(&bus);
            }
        }

        // if (!cpu.halted) {
        //     try cpu.printState(bus, stdout);
        // }

        if (bus.read8(0xFF02) == 0x81) {
            try stdout.print("{c}", .{bus.read8(0xFF01)});
            try buffer.append(bus.read8(0xFF01));
            bus.write8(0xFF02, 0x0);
        }

        // Draw
        //----------------------------------------------------------------------------------
        // raylib.BeginDrawing();
        // defer raylib.EndDrawing();
        //
        // raylib.ClearBackground(raylib.RAYWHITE);
        // raylib.DrawText("Congrats! You created your first window!", 190, 200, 20, raylib.LIGHTGRAY);
        //----------------------------------------------------------------------------------

        if (i == 100) {
            i = 0;
            try bw.flush();
        }
        //
        // if (cpu.program_counter == 0x100) {
        //     break;
        // }
    }

    try stdout.print("{s}\n", .{buffer.items});

    try bw.flush();
}
