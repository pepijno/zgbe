const std = @import("std");

const Bus = @import("Bus.zig");
const Cartridge = @import("Cartridge.zig");
const Clock = @import("Clock.zig");
const CPU = @import("CPU.zig");
const Dma = @import("Dma.zig");
const Gamepad = @import("Gamepad.zig");
const Interrupt = @import("Interrupt.zig");
const LCD = @import("LCD.zig");
const PPU = @import("PPU.zig");
const Timer = @import("Timer.zig");
const Writer = @import("writer.zig");

pub fn main() !void {
    try runTest("roms/mooneye/acceptance/add_sp_e_timing.gb");
    try runTest("roms/mooneye/acceptance/bits/mem_oam.gb");
    try runTest("roms/mooneye/acceptance/bits/reg_f.gb");
    try runTest("roms/mooneye/acceptance/bits/unused_hwio-GS.gb");
    try runTest("roms/mooneye/acceptance/boot_div-dmg0.gb");
    try runTest("roms/mooneye/acceptance/boot_div-dmgABCmgb.gb");
    try runTest("roms/mooneye/acceptance/boot_hwio-dmg0.gb");
    try runTest("roms/mooneye/acceptance/boot_hwio-dmgABCmgb.gb");
    try runTest("roms/mooneye/acceptance/boot_regs-dmg0.gb");
    try runTest("roms/mooneye/acceptance/boot_regs-dmgABC.gb");
    try runTest("roms/mooneye/acceptance/call_cc_timing2.gb");
    try runTest("roms/mooneye/acceptance/call_cc_timing.gb");
    try runTest("roms/mooneye/acceptance/call_timing2.gb");
    try runTest("roms/mooneye/acceptance/call_timing.gb");
    try runTest("roms/mooneye/acceptance/di_timing-GS.gb");
    try runTest("roms/mooneye/acceptance/div_timing.gb");
    try runTest("roms/mooneye/acceptance/ei_sequence.gb");
    try runTest("roms/mooneye/acceptance/ei_timing.gb");
    try runTest("roms/mooneye/acceptance/halt_ime0_ei.gb");
    try runTest("roms/mooneye/acceptance/halt_ime0_nointr_timing.gb");
    try runTest("roms/mooneye/acceptance/halt_ime1_timing2-GS.gb");
    try runTest("roms/mooneye/acceptance/halt_ime1_timing.gb");
    try runTest("roms/mooneye/acceptance/if_ie_registers.gb");
    try runTest("roms/mooneye/acceptance/instr/daa.gb");
    try runTest("roms/mooneye/acceptance/interrupts/ie_push.gb");
    try runTest("roms/mooneye/acceptance/intr_timing.gb");
    try runTest("roms/mooneye/acceptance/jp_cc_timing.gb");
    try runTest("roms/mooneye/acceptance/jp_timing.gb");
    try runTest("roms/mooneye/acceptance/ld_hl_sp_e_timing.gb");
    try runTest("roms/mooneye/acceptance/oam_dma/basic.gb");
    try runTest("roms/mooneye/acceptance/oam_dma/reg_read.gb");
    try runTest("roms/mooneye/acceptance/oam_dma/sources-GS.gb");
    try runTest("roms/mooneye/acceptance/oam_dma_restart.gb");
    try runTest("roms/mooneye/acceptance/oam_dma_start.gb");
    try runTest("roms/mooneye/acceptance/oam_dma_timing.gb");
    try runTest("roms/mooneye/acceptance/pop_timing.gb");
    try runTest("roms/mooneye/acceptance/ppu/hblank_ly_scx_timing-GS.gb");
    try runTest("roms/mooneye/acceptance/ppu/intr_1_2_timing-GS.gb");
    try runTest("roms/mooneye/acceptance/ppu/intr_2_0_timing.gb");
    try runTest("roms/mooneye/acceptance/ppu/intr_2_mode0_timing.gb");
    try runTest("roms/mooneye/acceptance/ppu/intr_2_mode0_timing_sprites.gb");
    try runTest("roms/mooneye/acceptance/ppu/intr_2_mode3_timing.gb");
    try runTest("roms/mooneye/acceptance/ppu/intr_2_oam_ok_timing.gb");
    try runTest("roms/mooneye/acceptance/ppu/lcdon_timing-GS.gb");
    try runTest("roms/mooneye/acceptance/ppu/lcdon_write_timing-GS.gb");
    try runTest("roms/mooneye/acceptance/ppu/stat_irq_blocking.gb");
    try runTest("roms/mooneye/acceptance/ppu/stat_lyc_onoff.gb");
    try runTest("roms/mooneye/acceptance/ppu/vblank_stat_intr-GS.gb");
    try runTest("roms/mooneye/acceptance/push_timing.gb");
    try runTest("roms/mooneye/acceptance/rapid_di_ei.gb");
    try runTest("roms/mooneye/acceptance/ret_cc_timing.gb");
    try runTest("roms/mooneye/acceptance/reti_intr_timing.gb");
    try runTest("roms/mooneye/acceptance/reti_timing.gb");
    try runTest("roms/mooneye/acceptance/ret_timing.gb");
    try runTest("roms/mooneye/acceptance/rst_timing.gb");
    try runTest("roms/mooneye/acceptance/timer/div_write.gb");
    try runTest("roms/mooneye/acceptance/timer/rapid_toggle.gb");
    try runTest("roms/mooneye/acceptance/timer/tim00_div_trigger.gb");
    try runTest("roms/mooneye/acceptance/timer/tim00.gb");
    try runTest("roms/mooneye/acceptance/timer/tim01_div_trigger.gb");
    try runTest("roms/mooneye/acceptance/timer/tim01.gb");
    try runTest("roms/mooneye/acceptance/timer/tim10_div_trigger.gb");
    try runTest("roms/mooneye/acceptance/timer/tim10.gb");
    try runTest("roms/mooneye/acceptance/timer/tim11_div_trigger.gb");
    try runTest("roms/mooneye/acceptance/timer/tim11.gb");
    try runTest("roms/mooneye/acceptance/timer/tima_reload.gb");
    try runTest("roms/mooneye/acceptance/timer/tima_write_reloading.gb");
    try runTest("roms/mooneye/acceptance/timer/tma_write_reloading.gb");
}

pub fn runTest(rom_path: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var cartridge = try Cartridge.open_cartridge(allocator, rom_path);

    var clock = Clock{};
    var interrupt = Interrupt{};
    var cpu = CPU.initAfterBoot();
    cpu.halted = false;
    cpu.running = true;
    var timer = Timer.initAfterBoot();
    var dma = Dma{};
    var lcd = LCD{ .dma = &dma };
    var ppu = PPU.init(&lcd);
    var bus = Bus{
        .dmg_boot_rom = 1,
        .interrupt = &interrupt,
        .cartridge = &cartridge,
        .cpu = &cpu,
        .ppu = &ppu,
        .timer = &timer,
        .lcd = &lcd,
        .dma = &dma,
    };

    Clock.runSteps(&clock, &bus, &cpu, &timer, &dma, &ppu, 1_000_000);

    if (cpu.af.bit8.a != 0) {
        try Writer.stdout.print("[\u{001b}[31mFAIL\u{001b}[0m]    {s}: assertion failuers in hardware test\n", .{rom_path});
    } else if (cpu.bc.bit8.b != 3 or cpu.bc.bit8.c != 5 or cpu.de.bit8.d != 8 or cpu.de.bit8.e != 13 or cpu.hl.bit8.h != 21 or cpu.hl.bit8.l != 34) {
        try Writer.stdout.print("[\u{001b}[31mFAIL\u{001b}[0m]    {s}: hardware test failed\n", .{rom_path});
    } else {
        try Writer.stdout.print("[\u{001b}[32mSUCCESS\u{001b}[0m] {s}\n", .{rom_path});
    }

    try Writer.bw.flush();
}
