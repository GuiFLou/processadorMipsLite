# =====================================================================
#  Processador_GUI_MIPS.sdc — Restrições de timing (TimeQuest)
# =====================================================================
#  O design tem DOIS domínios de clock:
#
#    • CLOCK_50 (50 MHz, 20 ns)  — divisor, debounce, lcd_controller
#    • clk_cpu  (~60 Hz, gerado por divisor_Freq) — núcleo do CPU
#
#  O divisor_Freq toggla a saída a cada DIV ciclos do CLOCK_50.
#  Default CPU_DIV=416_667 → período = 2·DIV = 833_334 ciclos
#  de 50 MHz ≈ 16.67 ms (≈ 60 Hz). Se mudar CPU_DIV, atualize
#  o -divide_by abaixo para 2·DIV.
# =====================================================================

# ---------- clock principal (50 MHz do oscilador da DE2-115) ---------
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

# ---------- clock derivado (clk_cpu) ---------------------------------
# É o registrador `clk_out` dentro da instância u_div do divisor_Freq.
# Divide_by usa o número total de ciclos de CLOCK_50 entre duas bordas
# de subida do clk_cpu (= 2 * parâmetro DIV).
create_generated_clock -name clk_cpu \
    -source [get_ports {CLOCK_50}] \
    -divide_by 833334 \
    [get_registers {*u_div|clk_out}]

# Inclui qualquer outro clock gerado por PLL (caso seja adicionado depois)
derive_pll_clocks
derive_clock_uncertainty

# ---------- CDC: CLOCK_50 ↔ clk_cpu ----------------------------------
# O sincronizador de reset (rst_sync_0/1) cruza propositalmente os
# dois domínios. False path nesse caminho — a sincronização já foi
# tratada em RTL com 2 flip-flops em série.
set_false_path -from [get_clocks CLOCK_50] -to [get_clocks clk_cpu]
set_false_path -from [get_clocks clk_cpu]  -to [get_clocks CLOCK_50]

# ---------- entradas e saídas assíncronas ----------------------------
# Botões e switches são assíncronos. Sinais de entrada passam pelo
# Debounce antes de entrar no datapath.
set_false_path -from [get_ports {KEY[*]}] -to *
set_false_path -from [get_ports {SW[*]}]  -to *

# Saídas vão direto para pinos; sem requisito crítico de atraso externo.
set_false_path -from * -to [get_ports {HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*] HEX6[*]}]
set_false_path -from * -to [get_ports {LEDR[*]}]
set_false_path -from * -to [get_ports {LCD_DATA[*] LCD_EN LCD_RS LCD_RW LCD_ON LCD_BLON}]
