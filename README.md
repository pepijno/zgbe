## ZGBE

### Blargg tests

|cpu_instrs||
|-|-|
|01-special.gb|✅|
|02-interrupts.gb|✅|
|03-op sp,hl.gb|✅|
|04-op r,imm.gb|✅|
|05-op rp.gb|✅|
|06-ld r,r.gb|✅|
|07-jr,jp,call,ret,rst.gb|✅|
|08-misc instrs.gb|✅|
|09-op r,r.gb|✅|
|10-bit ops.gb|✅|
|11-op a,(hl).gb|✅|

|instr_timing||
|-|-|
|instr_timing.gb|✅|

|interrupt_time||
|-|-|
|interrupt_time.gb|✅|

|mem_timing||
|-|-|
|01-read_timing.gb|✅|
|02-write_timing.gb|✅|
|03-modify_timing.gb|✅|


### Mooneye tests

|acceptance||
|-|-|
|add_sp_e_timing.gb|❌|
|bits/mem_oam.gb|✅|
|bits/reg_f.gb|✅|
|bits/unused_hwio-GS.gb|❌|
|boot_div-dmg0.gb|❌|
|boot_div-dmgABCmgb.gb|❌|
|boot_hwio-dmg0.gb|❌|
|boot_hwio-dmgABCmgb.gb|❌|
|boot_regs-dmg0.gb|❌|
|boot_regs-dmgABC.gb|✅|
|call_cc_timing2.gb|❌|
|call_cc_timing.gb|❌|
|call_timing2.gb|❌|
|call_timing.gb|❌|
|di_timing-GS.gb|✅|
|div_timing.gb|✅|
|ei_sequence.gb|✅|
|ei_timing.gb|✅|
|halt_ime0_ei.gb|✅|
|halt_ime0_nointr_timing.gb|❌|
|halt_ime1_timing2-GS.gb|✅|
|halt_ime1_timing.gb|✅|
|if_ie_registers.gb|❌|
|instr/daa.gb|✅|
|interrupts/ie_push.gb|❌|
|intr_timing.gb|✅|
|jp_cc_timing.gb|❌|
|jp_timing.gb|❌|
|ld_hl_sp_e_timing.gb|❌|
|oam_dma/basic.gb|✅|
|oam_dma/reg_read.gb|❌|
|oam_dma/sources-GS.gb|❌|
|oam_dma_restart.gb|❌|
|oam_dma_start.gb|❌|
|oam_dma_timing.gb|❌|
|pop_timing.gb|✅|
|ppu/hblank_ly_scx_timing-GS.gb|❌|
|ppu/intr_1_2_timing-GS.gb|❌|
|ppu/intr_2_0_timing.gb|❌|
|ppu/intr_2_mode0_timing.gb|❌|
|ppu/intr_2_mode0_timing_sprites.gb|❌|
|ppu/intr_2_mode3_timing.gb|❌|
|ppu/intr_2_oam_ok_timing.gb|❌|
|ppu/lcdon_timing-GS.gb|❌|
|ppu/lcdon_write_timing-GS.gb|❌|
|ppu/stat_irq_blocking.gb|❌|
|ppu/stat_lyc_onoff.gb|❌|
|ppu/vblank_stat_intr-GS.gb|❌|
|push_timing.gb|❌|
|rapid_di_ei.gb|❌|
|ret_cc_timing.gb|❌|
|reti_intr_timing.gb|✅|
|reti_timing.gb|❌|
|ret_timing.gb|❌|
|rst_timing.gb|❌|
|timer/div_write.gb|✅|
|timer/rapid_toggle.gb|✅|
|timer/tim00_div_trigger.gb|✅|
|timer/tim00.gb|✅|
|timer/tim01_div_trigger.gb|✅|
|timer/tim01.gb|✅|
|timer/tim10_div_trigger.gb|✅|
|timer/tim10.gb|✅|
|timer/tim11_div_trigger.gb|✅|
|timer/tim11.gb|✅|
|timer/tima_reload.gb|✅|
|timer/tima_write_reloading.gb|✅|
|timer/tma_write_reloading.gb|✅|
