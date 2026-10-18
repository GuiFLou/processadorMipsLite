// Processador_GUI_MIPS.v – TOP-LEVEL com suporte a JAL, JR e HLT
//  • JAL grava PC+1 no registrador-link ($ra = 31)
//  • JR salta para endereço contido em RS
//  • HLT congela o PC (processador "entra em loop")
//
// ===================================================================
//  Estratégia de clock (dois clocks reais)
// ===================================================================
//  Há DOIS domínios de clock no projeto:
//
//    • CLOCK_50  (50 MHz, vindo do oscilador da DE2-115):
//        Divisor, debounce dos KEY e o lcd_controller (tempos do
//        HD44780 em µs/ms; não cabem no clk_cpu).
//
//    • clk_cpu  (~5 kHz com CPU_DIV=5_000):
//        Núcleo — PC, RegFile, RAM, porta B da IMEM e o CSR display_ctx.
//        clk_cpu ≈ 50 MHz / (2·DIV). DIV maior → mais lento.
//
//  CDC (Clock Domain Crossing):
//    CLOCK_50 → clk_cpu: rst_db e os KEY[1..3] debounced entram
//    por 2–3 FFs no clk_cpu; KEY vira pulso de 1 ciclo.
//    clk_cpu → CLOCK_50: mode/id/pid/sel do display_ctx; o LCD
//    sincroniza com 2 FFs e só usa o segundo no catálogo.
// ===================================================================

module Processador_GUI_MIPS #(
    parameter CPU_DIV      = 5_000,         // ~5 kHz em CLOCK_50 (50 MHz / (2·5000))
    parameter BTN_STABLE   = 1_000_000,   // debounce @ 50 MHz; reduzir no testbench
    parameter ROM_FILE     = "so.txt",
    parameter HD_FILE      = "hd_image.txt",
    parameter LCD_T_POWER  = 2_000_000,
    parameter LCD_T_INIT1  = 220_000,
    parameter LCD_T_INIT2  = 6_000,
    parameter LCD_T_CLEAR  = 100_000,
    parameter LCD_T_CMD    = 2_000,
    parameter LCD_T_SETUP  = 3,
    parameter LCD_T_EN     = 20
) (
    input  wire        CLOCK_50,
    input  wire [17:0] SW,
    input  wire [3:0]  KEY,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
    output wire [6:0]  HEX4,
    output wire [6:0]  HEX5,
    output wire [6:0]  HEX6,
    output wire [17:0] LEDR,
    output wire [7:0]  LCD_DATA,
    output wire        LCD_EN,
    output wire        LCD_RS,
    output wire        LCD_RW,
    output wire        LCD_ON,
    output wire        LCD_BLON
);
    /* ========================= GERAÇÃO DO clk_cpu ======================== */
    // clk_cpu ≈ 50 MHz / (2·DIV). Referência rápida:
    //   DIV=12_500_000 → ~2 Hz   | DIV=  5_000 → ~5 kHz
    //   DIV= 1_250_000 → ~20 Hz  | DIV=    1   → metade de CLOCK_50
    // Aumente DIV para clock mais lento, diminua para mais rápido.
    wire clk_cpu;
    divisor_Freq #(.DIV(CPU_DIV)) u_div (
        .clk_in (CLOCK_50),
        .clk_out(clk_cpu)
    );

    /* ========================= RESET ===================================== */
    // 1) Debounce do KEY[0] no domínio rápido (CLOCK_50). Sem isso, o
    //    rebote mecânico do botão geraria múltiplos resets.
    wire rst_raw = ~KEY[0];                 // KEY ativo-baixo
    wire rst_db;
    Debounce #(.STABLE_CNT(BTN_STABLE)) u_rst_db (
        .clk(CLOCK_50), .btn_in(rst_raw), .btn_out(rst_db)
    );

    // 2) Sincronizador de 2 FFs para trazer rst_db (CLOCK_50) ao
    //    domínio do clk_cpu. Evita metaestabilidade na CDC.
    reg rst_sync_0, rst_sync_1;
    always @(posedge clk_cpu) begin
        rst_sync_0 <= rst_db;
        rst_sync_1 <= rst_sync_0;
    end
    wire rst = rst_sync_1;

    /* ========================= BOTÃO "ENTER" (KEY[1]) =================== */
    // O IN pausa o PC até o usuário apertar KEY[1]. O fluxo é:
    //   1) debounce no domínio rápido (CLOCK_50)
    //   2) sincronização de 2 FFs no domínio clk_cpu
    //   3) detector de borda → pulso de EXATAMENTE 1 ciclo de clk_cpu
    // Assim, dois IN consecutivos exigem dois apertos distintos.
    wire enter_raw = ~KEY[1];               // KEY ativo-baixo
    wire enter_db;
    Debounce #(.STABLE_CNT(BTN_STABLE)) u_enter_db (
        .clk(CLOCK_50), .btn_in(enter_raw), .btn_out(enter_db)
    );
    reg enter_s0, enter_s1, enter_s2;
    always @(posedge clk_cpu) begin
        enter_s0 <= enter_db;
        enter_s1 <= enter_s0;
        enter_s2 <= enter_s1;
    end
    wire enter_pulse = enter_s1 & ~enter_s2;

    /* ========================= KEY[2]/KEY[3] (menu LCD) ================= */
    // Mesmo caminho de KEY[1]: debounce @50 MHz, sync e borda em clk_cpu.
    // Durante stall_io as setas são ignoradas. O ciclo do Enter também:
    // nele o stall cai, e uma seta no mesmo pulso moveria o sel.
    wire left_raw  = ~KEY[2];
    wire right_raw = ~KEY[3];
    wire left_db, right_db;
    Debounce #(.STABLE_CNT(BTN_STABLE)) u_left_db (
        .clk(CLOCK_50), .btn_in(left_raw), .btn_out(left_db)
    );
    Debounce #(.STABLE_CNT(BTN_STABLE)) u_right_db (
        .clk(CLOCK_50), .btn_in(right_raw), .btn_out(right_db)
    );
    reg left_s0, left_s1, left_s2;
    reg right_s0, right_s1, right_s2;
    always @(posedge clk_cpu) begin
        left_s0  <= left_db;
        left_s1  <= left_s0;
        left_s2  <= left_s1;
        right_s0 <= right_db;
        right_s1 <= right_s0;
        right_s2 <= right_s1;
    end
    wire left_pulse  = left_s1  & ~left_s2;
    wire right_pulse = right_s1 & ~right_s2;

    /* Reset do LCD no domínio CLOCK_50 (independente do rst do CPU). */
    reg rst50_s0, rst50_s1;
    always @(posedge CLOCK_50) begin
        rst50_s0 <= rst_db;
        rst50_s1 <= rst50_s0;
    end
    wire rst_lcd = rst50_s1;

    /* ========================= PROGRAM COUNTER =========================== */
    reg  [31:0] pc;
    wire [31:0] pc_plus4 = pc + 32'd1;

    /* ========================= INSTRUCTION MEMORY ======================== */
    wire [31:0] instr;
    wire [11:0] dma_imem_addr;
    wire [31:0] dma_imem_wdata;
    wire        dma_imem_we;
    inst_mem_rw #(.ADDR_W(12), .FILENAME(ROM_FILE)) IMEM (
        .clk     (clk_cpu),
        .addr_a  (pc[11:0]),
        .rdata_a (instr),
        .addr_b  (dma_imem_addr),
        .wdata_b (dma_imem_wdata),
        .we_b    (dma_imem_we)
    );

    /* ======== CAMPOS DA INSTRUÇÃO (MIPS-Lite) ================= */
    wire [5:0]  opcode = instr[31:26];
    wire [5:0]  rs     = instr[25:20];
    wire [5:0]  rt     = instr[19:14];
    wire [5:0]  rd     = instr[13:8];
    wire [13:0] imm14  = instr[13:0];
    wire [25:0] jaddr  = instr[25:0];
    wire [7:0]  shamt  = instr[7:0];

    /* ========================= UNIDADE DE CONTROLE ======================= */
    wire regDst, aluSrc, memToReg, regWrite, memWrite;
    wire branchEq, branchNe, jump, jal, jr, halt;
    wire is_in, is_out, isMultDiv;
    wire [3:0] aluOp;
    control_unit CU (
        .opcode(opcode),
        .regDst(regDst), .aluSrc(aluSrc), .memToReg(memToReg),
        .regWrite(regWrite), .memWrite(memWrite),
        .branchEq(branchEq), .branchNe(branchNe),
        .jump(jump), .jal(jal), .jr(jr),
        .halt(halt),
        .is_in(is_in), .is_out(is_out), .isMultDiv(isMultDiv),
        .aluOp(aluOp)
    );

    /* ========================= EXTENSÃO DO IMEDIATO ======================
       Imediatos aritméticos/endereço usam sinal; ANDI/ORI usam máscara
       lógica, então precisam completar os bits altos com zero. */
    wire [31:0] immExt;
    sign_extend #(.IN_W(14)) SE (
        .in (imm14),
        .out(immExt)
    );
    wire        is_logic_imm = (opcode == 6'b001001) || (opcode == 6'b001011);
    wire [31:0] immZeroExt  = {18'b0, imm14};
    wire [31:0] aluImmExt   = is_logic_imm ? immZeroExt : immExt;

    /* ========================= STALL DE I/O ============================== */
    // IN e OUT congelam o PC até o usuário pulsar KEY[1].
    // IN só escreve no regfile no ciclo do pulso; OUT já atualiza o display
    // enquanto aguarda a confirmação.
    wire        stall_in   = is_in  & ~enter_pulse;
    wire        stall_out  = is_out & ~enter_pulse;
    wire        stall_io   = stall_in | stall_out;
    wire        hd_stall;
    wire        hd_freeze;
    wire [31:0] in_data    = {22'b0, SW[9:0]};
    wire        in_writeEn = is_in & enter_pulse;

    /* ========================= REGFILE E SIGN-EXT ======================== */
    localparam [5:0] LO_REG = 6'd61;
    localparam [5:0] HI_REG = 6'd62;

    // Leituras do banco: F1 usa RS/RT; F2 usa RS em rt e, em SW/BEQ/BNE, lê também o campo [25:20].
    // OUT (FI) precisa ler o registrador no campo [25:20] (= 'rs') por rd1.
    wire [5:0] rf_rs1 = (regDst | jr | branchEq | branchNe | is_out) ? rs : rt;
    wire [5:0] rf_rs2 = regDst ? rt : (memWrite ? rs : rt);

    // Destino de escrita: JAL → $ra (31); F1 → RD[13:8]; F2/FI → campo [25:20].
    wire [5:0] writeReg = jal ? 6'd31 : (regDst ? rd : rs);

    // Saídas brutas do banco (rd1/rd2) e versões já com bypass de $hi/$lo.
    // Declaração explícita evita que o Verilog crie wires de 1 bit por
    // inferência implícita.
    wire [31:0] rf_a_raw, rf_b_raw;
    wire [31:0] rf_a, rf_b;
    wire [31:0] rf_wd;

    regfile64 RF (
        .clk (clk_cpu), .rst(rst),
        .we  ((regWrite | in_writeEn) && !hd_freeze),
        .rs1 (rf_rs1),
        .rs2 (rf_rs2),
        .rd  (writeReg),
        .wd  (rf_wd),
        .rd1 (rf_a_raw),
        .rd2 (rf_b_raw)
    );

    reg [31:0] hi_reg, lo_reg;
    assign rf_a = (rf_rs1 == LO_REG) ? lo_reg :
                  (rf_rs1 == HI_REG) ? hi_reg :
                                        rf_a_raw;
    assign rf_b = (rf_rs2 == LO_REG) ? lo_reg :
                  (rf_rs2 == HI_REG) ? hi_reg :
                                        rf_b_raw;

    /* ========================= ALU ======================================= */
    wire [31:0] alu_in_b = aluSrc ? aluImmExt : rf_b;
    wire [31:0] alu_y;
    wire [31:0] alu_hi, alu_lo;
    wire        alu_zero;
    alu ALU (
        .a(rf_a), .b(alu_in_b), .op(aluOp), .shamt(shamt),
        .y(alu_y), .hi_out(alu_hi), .lo_out(alu_lo), .zero(alu_zero)
    );

    always @(posedge clk_cpu) begin
        if (rst) begin
            hi_reg <= 32'd0;
            lo_reg <= 32'd0;
        end else if (isMultDiv && !hd_freeze) begin
            hi_reg <= alu_hi;
            lo_reg <= alu_lo;
        end
    end

    /* ========================= HD MMIO 4092–4095 ======================== */
    // Endereço completo: 8188 não pode aliasar 4092.
    wire is_hd_mmio = (alu_y >= 32'd4092) && (alu_y <= 32'd4095);
    wire is_ram     = (alu_y <= 32'd4087);

    wire hd_cmd_write    = memWrite && (alu_y == 32'd4092);
    wire hd_sector_write = memWrite && (alu_y == 32'd4093);
    wire hd_addr_write   = memWrite && (alu_y == 32'd4094);

    wire [31:0] hd_cmd_out;
    wire [31:0] hd_sector_out;
    wire [31:0] hd_addr_out;
    wire [31:0] hd_status_out;

    wire [11:0] dma_ram_addr;
    wire [31:0] dma_ram_wdata;
    wire [31:0] dma_ram_rdata;
    wire        dma_ram_we;

    hd_sim #(
        .HD_FILE(HD_FILE),
        .RAM_ADDR_W(12),
        .RAM_MAX_ADDR(4087),
        .IMEM_ADDR_W(12),
        .IMEM_MAX_ADDR(4095)
    ) HD (
        .clk           (clk_cpu),
        .rst           (rst),
        .reg_cmd_in    (rf_b),
        .reg_sector_in (rf_b),
        .reg_addr_in   (rf_b),
        .cmd_write     (hd_cmd_write),
        .sector_write  (hd_sector_write),
        .addr_write    (hd_addr_write),
        .reg_cmd_out   (hd_cmd_out),
        .reg_sector_out(hd_sector_out),
        .reg_addr_out  (hd_addr_out),
        .reg_status_out(hd_status_out),
        .ram_addr_b    (dma_ram_addr),
        .ram_wdata_b   (dma_ram_wdata),
        .ram_rdata_b   (dma_ram_rdata),
        .ram_we_b      (dma_ram_we),
        .imem_addr_b   (dma_imem_addr),
        .imem_wdata_b  (dma_imem_wdata),
        .imem_we_b     (dma_imem_we),
        .cpu_stall     (hd_stall),
        .cpu_freeze    (hd_freeze)
    );

    wire [31:0] hd_mmio_read =
        (alu_y == 32'd4092) ? hd_cmd_out    :
        (alu_y == 32'd4093) ? hd_sector_out :
        (alu_y == 32'd4094) ? hd_addr_out   :
                              hd_status_out;

    /* ========================= DISPLAY_CTX 4091 ========================= */
    // 4088–4090 ficam reservados: leitura 0, escrita ignorada.
    // O DMA da RAM para em 4087.
    wire is_disp_ctx = (alu_y == 32'd4091);

    /* ========================= DATA MEMORY =============================== */
    wire [31:0] data_rd;
    data_ram #(.ADDR_W(12)) DRAM (
        .clk     (clk_cpu),
        .addr_a  (alu_y[11:0]),
        .wdata_a (rf_b),
        .rdata_a (data_rd),
        .we_a    (memWrite && is_ram && !hd_freeze),
        .addr_b  (dma_ram_addr),
        .wdata_b (dma_ram_wdata),
        .rdata_b (dma_ram_rdata),
        .we_b    (dma_ram_we)
    );

    reg  [7:0] disp_mode;
    reg  [9:0] disp_id;
    reg  [3:0] disp_pid;
    reg  [4:0] disp_sel;
    reg        disp_ack;
    /* 1 MENU=3, 6 PROG=10, 7 QUANTOS=10. As outras telas têm um item. */
    wire [4:0] disp_nitems =
        (disp_mode == 8'd1) ? 5'd3  :
        (disp_mode == 8'd6) ? 5'd10 :
        (disp_mode == 8'd7) ? 5'd10 :
                              5'd1;
    /* [27] ack, [26:22] sel, [21:18] pid, [17:8] id, [7:0] mode. */
    wire [31:0] disp_ctx_rd = {4'b0, disp_ack, disp_sel, disp_pid, disp_id, disp_mode};

    always @(posedge clk_cpu) begin
        if (rst) begin
            disp_mode <= 8'd0;
            disp_id   <= 10'd0;
            disp_pid  <= 4'd15;
            disp_sel  <= 5'd0;
            disp_ack  <= 1'b0;
        end else if (memWrite && is_disp_ctx && !hd_freeze) begin
            disp_mode <= rf_b[7:0];
            disp_id   <= rf_b[17:8];
            disp_pid  <= rf_b[21:18];
            disp_ack  <= 1'b0;
            if (rf_b[7:0] != disp_mode)
                disp_sel <= 5'd0;
        end else if (enter_pulse) begin
            /* KEY[1] confirma a tela. No ciclo em que solta IN/OUT, is_in/is_out
             * ainda valem 1, então esse Enter não liga o ack. O ramo inteiro
             * fica na frente das setas: stall_io cai nesse ciclo. */
            if (!is_in && !is_out)
                disp_ack <= 1'b1;
        end else if (!stall_io && (disp_nitems > 5'd1)) begin
            if (left_pulse) begin
                disp_sel <= (disp_sel == 5'd0) ? (disp_nitems - 5'd1)
                                               : (disp_sel - 5'd1);
            end else if (right_pulse) begin
                disp_sel <= (disp_sel + 5'd1 >= disp_nitems) ? 5'd0
                                                            : (disp_sel + 5'd1);
            end
        end
    end

    lcd_controller #(
        .T_POWER(LCD_T_POWER),
        .T_INIT1(LCD_T_INIT1),
        .T_INIT2(LCD_T_INIT2),
        .T_CLEAR(LCD_T_CLEAR),
        .T_CMD  (LCD_T_CMD),
        .T_SETUP(LCD_T_SETUP),
        .T_EN   (LCD_T_EN)
    ) u_lcd (
        .clk    (CLOCK_50),
        .rst    (rst_lcd),
        .mode   (disp_mode),
        .prog_id(disp_id),
        .pid    (disp_pid),
        .sel    (disp_sel),
        .LCD_DATA(LCD_DATA),
        .LCD_EN (LCD_EN),
        .LCD_RS (LCD_RS),
        .LCD_RW (LCD_RW),
        .LCD_ON (LCD_ON),
        .LCD_BLON(LCD_BLON)
    );

    /* ========================= WRITE-BACK MUX ============================ */
    wire [31:0] mem_read_value = is_disp_ctx ? disp_ctx_rd :
                                 is_hd_mmio  ? hd_mmio_read :
                                 is_ram      ? data_rd :
                                               32'd0;
    wire [31:0] wb_core = memToReg ? mem_read_value : alu_y;
    assign rf_wd = is_in ? in_data    :
                   jal   ? pc_plus4   :
                                       wb_core;

    /* ========================= LÓGICA DE DESVIO ========================== */
    wire        branch_taken  = (branchEq &&  alu_zero) ||
                                (branchNe && ~alu_zero);
    wire [31:0] branch_target = pc_plus4 + immExt;
    wire [31:0] jump_target   = {6'b0, jaddr};
    wire [31:0] jr_target     = rf_a;

    wire [31:0] pc_next = (halt | stall_io | hd_stall) ? pc :
                          jr            ? jr_target  :
                          jump          ? jump_target :
                          branch_taken  ? branch_target :
                                          pc_plus4;

    /* ========================= PC REGISTER ============================== */
    always @(posedge clk_cpu) begin
        if (rst) pc <= 32'd0;
        else     pc <= pc_next;
    end

    /* ========================= REGISTRADOR DE OUT ======================= */
    // Captura o operando do OUT (FI – campo Reg = bits 25:20 → rf_a) no
    // mesmo ciclo em que a instrução é decodificada. Mantém o último valor
    // entre OUTs sucessivos para que o display não pisque.
    reg [31:0] out_reg;
    always @(posedge clk_cpu) begin
        if (rst)         out_reg <= 32'd0;
        else if (is_out && !hd_freeze) out_reg <= rf_a;
    end

    /* ========================= I/O VISUAL =============================== */
    // LEDR fornece feedback visual do estado da máquina:
    //   [9:0]  – eco dos switches (o que será lido pelo próximo IN)
    //   [16]   – HALT  (programa terminou)
    //   [17]   – WAIT  (executando IN ou OUT, aguardando KEY[1])
    assign LEDR[9:0]  = SW[9:0];
    assign LEDR[15:10] = 6'b0;
    assign LEDR[16]   = halt;
    assign LEDR[17]   = stall_io;

    // HEX0..HEX6 mostram o último OUT em decimal (BCD):
    // HEX0 = unidade, HEX1 = dezena, ... HEX6 = milhão.
    wire [27:0] out_bcd;
    bin32_to_bcd7 u_out_bcd (
        .bin(out_reg),
        .bcd(out_bcd)
    );
    hex7seg h0 (.hex(out_bcd[ 3: 0]), .seg(HEX0));
    hex7seg h1 (.hex(out_bcd[ 7: 4]), .seg(HEX1));
    hex7seg h2 (.hex(out_bcd[11: 8]), .seg(HEX2));
    hex7seg h3 (.hex(out_bcd[15:12]), .seg(HEX3));
    hex7seg h4 (.hex(out_bcd[19:16]), .seg(HEX4));
    hex7seg h5 (.hex(out_bcd[23:20]), .seg(HEX5));
    hex7seg h6 (.hex(out_bcd[27:24]), .seg(HEX6));
endmodule
