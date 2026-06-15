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
//        Alimenta apenas a "borda" do design — o divisor de
//        frequência e o debouncer do botão de reset. Esses módulos
//        precisam de uma base de tempo rápida para funcionar.
//
//    • clk_cpu  (~2 Hz, gerado pelo divisor_Freq):
//        Clock REAL de todo o núcleo do processador.
//        PC, RegFile, RAM e ROM são clocados por ele. Como roda
//        devagar, dá para acompanhar visualmente cada instrução
//        executando nos displays de 7 segmentos.
//
//  Cuidado com CDC (Clock Domain Crossing):
//    O único sinal que cruza de CLOCK_50 → clk_cpu é o `rst` (saída
//    do debouncer). Para evitar metaestabilidade, ele passa por um
//    sincronizador de 2 flip-flops no domínio do clk_cpu antes de
//    ser usado pelo restante do design.
// ===================================================================

module Processador_GUI_MIPS #(
    parameter CPU_DIV      = 416_667,     // ~60 Hz em CLOCK_50 (50 MHz / (2·416667))
    parameter BTN_STABLE   = 1_000_000,   // debounce @ 50 MHz; reduzir no testbench
    parameter ROM_FILE     = "gcd.txt"
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
    output wire [17:0] LEDR
);
    /* ========================= GERAÇÃO DO clk_cpu ======================== */
    // clk_cpu ≈ 50 MHz / (2·DIV). Referência rápida:
    //   DIV=12_500_000 → ~2 Hz   | DIV=  416_667 → ~60 Hz
    //   DIV= 1_250_000 → ~20 Hz  | DIV=  250_000  → ~100 Hz
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

    /* ========================= PROGRAM COUNTER =========================== */
    reg  [31:0] pc;
    wire [31:0] pc_plus4 = pc + 32'd1;

    /* ========================= INSTRUCTION ROM =========================== */
    wire [31:0] instr;
    single_port_rom #(.ADDR_W(10), .FILENAME(ROM_FILE)) ROM (
        .clk  (clk_cpu),
        .addr (pc[9:0]),                // PC em endereço de palavra (CONTEXTO §1)
        .data (instr)
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

    /* ========================= STALL DO IN =============================== */
    // Enquanto o opcode for IN e o usuário não tiver pulsado KEY[1],
    // o PC fica congelado e o regfile não escreve. No ciclo do pulso,
    // grava {22'b0, SW[9:0]} no registrador apontado pelo campo Reg (FI[25:20]).
    wire        stall_in   = is_in & ~enter_pulse;
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
        .we  (regWrite | in_writeEn),
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
        end else if (isMultDiv) begin
            hi_reg <= alu_hi;
            lo_reg <= alu_lo;
        end
    end

    /* ========================= DATA MEMORY =============================== */
    wire [31:0] data_rd;
    data_ram DRAM (
        .clk     (clk_cpu),
        .addr_a  (alu_y[9:0]),
        .wdata_a (rf_b),
        .rdata_a (data_rd),
        .we_a    (memWrite),
        .addr_b  (10'd0), .wdata_b(32'd0), .we_b(1'b0)
    );

    /* ========================= WRITE-BACK MUX ============================ */
    wire [31:0] wb_core = memToReg ? data_rd : alu_y;
    assign rf_wd = is_in ? in_data    :
                   jal   ? pc_plus4   :
                                       wb_core;

    /* ========================= LÓGICA DE DESVIO ========================== */
    wire        branch_taken  = (branchEq &&  alu_zero) ||
                                (branchNe && ~alu_zero);
    wire [31:0] branch_target = pc_plus4 + immExt;
    wire [31:0] jump_target   = {6'b0, jaddr};
    wire [31:0] jr_target     = rf_a;

    wire [31:0] pc_next = (halt | stall_in) ? pc :
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
        else if (is_out) out_reg <= rf_a;
    end

    /* ========================= I/O VISUAL =============================== */
    // LEDR fornece feedback visual do estado da máquina:
    //   [9:0]  – eco dos switches (o que será lido pelo próximo IN)
    //   [16]   – HALT  (programa terminou)
    //   [17]   – WAIT  (executando IN, aguardando KEY[1])
    assign LEDR[9:0]  = SW[9:0];
    assign LEDR[15:10] = 6'b0;
    assign LEDR[16]   = halt;
    assign LEDR[17]   = stall_in;

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
