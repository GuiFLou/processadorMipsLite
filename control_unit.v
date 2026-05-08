// control_unit.v – compatível com ISA do encoder.c
module control_unit (
    input  wire [5:0] opcode,
    output reg        regDst,
    output reg        aluSrc,
    output reg        memToReg,
    output reg        regWrite,
    output reg        memWrite,
    output reg        branchEq,
    output reg        branchNe,
    output reg        jump,
    output reg        jal,
    output reg        jr,      // <‑‑ NOVO
    output reg        halt,    // <‑‑ NOVO (para HLT)
    output reg        is_in,   // <‑‑ NOVO (FI – IN  : escrita do regfile e PC tratados no top-level)
    output reg        is_out,  // <‑‑ NOVO (FI – OUT : captura do valor para os displays no top-level)
    output reg        isMultDiv, // <-- NOVO (MULT/DIV: habilita escrita em $hi/$lo no top-level)
    output reg  [3:0] aluOp
);
    always @* begin
        /* defaults = NOP */
        {regDst, aluSrc, memToReg, regWrite, memWrite,
         branchEq, branchNe, jump, jal, jr, halt,
         is_in, is_out, isMultDiv} = 14'b0;
        aluOp = 4'd0;

        case (opcode)
            /* -------- F1 (R‑type) -------- */
            6'b000000: begin regDst=1; regWrite=1; aluOp=4'd0; end   // ADD
            6'b000010: begin regDst=1; regWrite=1; aluOp=4'd1; end   // SUB
            6'b000100: begin regDst=1; isMultDiv=1; aluOp=4'd8; end  // MULT
            6'b000110: begin regDst=1; isMultDiv=1; aluOp=4'd9; end  // DIV
            6'b001000: begin regDst=1; regWrite=1; aluOp=4'd2; end   // AND
            6'b001010: begin regDst=1; regWrite=1; aluOp=4'd3; end   // OR
            6'b001101: begin regDst=1; regWrite=1; aluOp=4'd6; end   // SR
            6'b001110: begin regDst=1; regWrite=1; aluOp=4'd5; end   // SL
            6'b011001: begin regDst=1; regWrite=1; aluOp=4'd7; end   // SLT
            6'b010010: begin jr=1; jump=1;                        end // JUMPR

            /* -------- F2 (I‑type) -------- */
            6'b000001: begin aluSrc=1; regWrite=1; aluOp=4'd0; end   // ADDI
            6'b000011: begin aluSrc=1; regWrite=1; aluOp=4'd1; end   // SUBI
            6'b000101: begin aluSrc=1; regWrite=1; aluOp=4'd8; end   // MULTI
            6'b000111: begin aluSrc=1; regWrite=1; aluOp=4'd9; end   // DIVI
            6'b001001: begin aluSrc=1; regWrite=1; aluOp=4'd2; end   // ANDI
            6'b001011: begin aluSrc=1; regWrite=1; aluOp=4'd3; end   // ORI
            6'b001100: begin aluSrc=1; regWrite=1; aluOp=4'd4; end   // NOT
            6'b001111: begin aluSrc=1; memToReg=1; regWrite=1;      end // LOAD
            6'b010000: begin aluSrc=1; memWrite=1;                 end // STORE
            6'b010100: begin branchEq=1; aluOp=4'd1;               end // BEQ
            6'b010101: begin branchNe=1; aluOp=4'd1;               end // BNE
            6'b010110: begin regWrite=1; aluOp=4'd10;              end // MOVE

            /* -------- F3 (J‑type) -------- */
            6'b010001:            jump = 1;                          // JUMP
            6'b010011: begin jump=1; jal=1; regWrite=1; end          // JAL
            6'b011000:            halt = 1;                          // HLT

            /* -------- FI (I/O) -------- */
            6'b011010:            is_in  = 1;                        // IN  (pausa PC + escreve switches – top-level)
            6'b011011:            is_out = 1;                        // OUT (captura rf_a no display – top-level)
            /* 010111 = NOP – manter defaults */
        endcase
    end
endmodule