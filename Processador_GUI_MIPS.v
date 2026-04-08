// Processador_GUI_MIPS.v – TOP‑LEVEL com suporte a JAL, JR e HLT
//  • JAL grava PC+1 no registrador‑link ($ra = 31)
//  • JR salta para endereço contido em RS
//  • HLT congela o PC (processador “entra em loop”)

module Processador_GUI_MIPS (
    input  wire        CLOCK_50,
    input  wire [17:0] SW,
    input  wire [3:0]  KEY,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
    output wire [6:0]  HEX4,
    output wire [6:0]  HEX5,
    output wire [17:0] LEDR
);
    /* ========================= RESET ===================================== */
    wire rst = ~KEY[0];                 // botão KEY0 ativo‑baixo

    /* ========================= PROGRAM COUNTER =========================== */
    reg  [31:0] pc;
    wire [31:0] pc_plus4     = pc + 32'd1;

    /* ========================= INSTRUCTION ROM =========================== */
    wire [31:0] instr;
    single_port_rom #(.ADDR_W(10), .FILENAME("gcd.txt")) ROM (
        .clk  (CLOCK_50),
        .addr (pc[9:0]),                // PC em endereço de palavra (CONTEXTO §1)
        .data (instr)
    );

    /* ======== CAMPOS DA INSTRUÇÃO (MIPS‑Lite) ================= */
	wire [5:0] opcode = instr[31:26];
	wire [5:0] rs     = instr[25:20];
	wire [5:0] rt     = instr[19:14];
	wire [5:0] rd     = instr[13:8];
	wire [13:0] imm14 = instr[13:0];
	wire [25:0] jaddr = instr[25:0];
	wire [7:0]  shamt = instr[7:0];

    /* ========================= UNIDADE DE CONTROLE ======================= */
    wire regDst, aluSrc, memToReg, regWrite, memWrite;
    wire branchEq, branchNe, jump, jal, jr, halt;
    wire [3:0] aluOp;
    control_unit CU (
			 .opcode(opcode),
			 .regDst(regDst), .aluSrc(aluSrc), .memToReg(memToReg),
			 .regWrite(regWrite), .memWrite(memWrite),
			 .branchEq(branchEq), .branchNe(branchNe),
			 .jump(jump), .jal(jal), .jr(jr),
			 .halt(halt),           // <‑‑ adicionar
			 .aluOp(aluOp)
		);

    /* ========================= REGFILE E SIGN‑EXT ======================== */
    wire [31:0] rf_a, rf_b, rf_wd;
    wire [31:0] immExt;
    sign_extend #(.IN_W(14)) SE (.in(imm14), .out(immExt));

    // Leituras do banco: F1 usa RS/RT; F2 usa RS em rt e, em SW/BEQ/BNE, lê também o campo [25:20].
    wire [5:0] rf_rs1 = (regDst | jr | branchEq | branchNe) ? rs : rt;
    wire [5:0] rf_rs2 = regDst ? rt : (memWrite ? rs : rt);

    // Destino de escrita: JAL → $ra (31); F1 → RD[13:8]; F2/FI → campo [25:20].
    wire [5:0] writeReg = jal ? 6'd31 : (regDst ? rd : rs);

    regfile64 RF (
        .clk (CLOCK_50), .rst(rst),
        .we  (regWrite),
        .rs1 (rf_rs1),
        .rs2 (rf_rs2),
        .rd  (writeReg),
        .wd  (rf_wd),
        .rd1 (rf_a),
        .rd2 (rf_b)
    );

    /* ========================= ALU ======================================= */
    wire [31:0] alu_in_b   = aluSrc ? immExt : rf_b;
    wire [31:0] alu_y;
    wire        alu_zero;
    alu ALU (.a(rf_a), .b(alu_in_b), .op(aluOp), .y(alu_y), .zero(alu_zero));

    /* ========================= DATA MEMORY =============================== */
    wire [31:0] data_rd;
    data_ram DRAM (
        .clk     (CLOCK_50),
        .addr_a  (alu_y[9:0]),
        .wdata_a (rf_b),
        .rdata_a (data_rd),
        .we_a    (memWrite),
        .addr_b  (10'd0), .wdata_b(32'd0), .we_b(1'b0)  // porta B ociosa
    );

    /* ========================= WRITE‑BACK MUX ============================ */
    wire [31:0] wb_core = memToReg ? data_rd : alu_y;
    assign rf_wd = jal ? pc_plus4 : wb_core;

    /* ========================= LÓGICA DE DESVIO ========================== */
    wire        branch_taken = (branchEq &&  alu_zero) ||
                               (branchNe && ~alu_zero);
    wire [31:0] branch_target = pc_plus4 + immExt;  // PC+1 + signext(Imm); word addr (§6.2)
    wire [31:0] jump_target   = {6'b0, jaddr};      // salto absoluto 26 bits (§6.1)
    wire [31:0] jr_target     = rf_a;               // RS já lido

    wire [31:0] pc_next = halt          ? pc :               // HLT congela
                          jr            ? jr_target  :
                          jump          ? jump_target :
                          branch_taken  ? branch_target :
                                          pc_plus4;

    /* ========================= PC REGISTER ============================== */
    always @(posedge CLOCK_50) begin
        if (rst) pc <= 32'd0;
        else     pc <= pc_next;
    end

    /* ========================= I/O VISUAL =============================== */
    assign LEDR = alu_y[17:0];            // debug ULA

    hex7seg h0 (.hex(pc[ 3: 0]), .seg(HEX0));
    hex7seg h1 (.hex(pc[ 7: 4]), .seg(HEX1));
    hex7seg h2 (.hex(pc[11: 8]), .seg(HEX2));
    hex7seg h3 (.hex(pc[15:12]), .seg(HEX3));
    hex7seg h4 (.hex(pc[19:16]), .seg(HEX4));
    hex7seg h5 (.hex(pc[23:20]), .seg(HEX5));
endmodule
