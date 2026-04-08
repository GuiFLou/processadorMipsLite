`timescale 1ns/1ps
module tb_control_loadstore;
    // ----- DUTs -----
    reg  [5:0] opc;            // entrada para Control Unit
    wire regDst, aluSrc, memToReg, regWrite, memWrite, beq, bne, jump, jal, jr, halt;
    wire [3:0] aluOp;
    control_unit CU (
        .opcode(opc), .regDst(regDst), .aluSrc(aluSrc), .memToReg(memToReg),
        .regWrite(regWrite), .memWrite(memWrite),
        .branchEq(beq), .branchNe(bne), .jump(jump),
        .jal(jal), .jr(jr), .halt(halt), .aluOp(aluOp)
    );

    reg clk; initial clk = 0; always #5 clk = ~clk;      // 100 MHz

    // memoria sob teste
    reg  [31:0] inData;
    wire [31:0] outData;
    data_ram MEM(.clk(clk),
                 .addr_a(10'd3), .wdata_a(inData), .rdata_a(outData),
                 .we_a(memWrite),
                 .addr_b(10'd0), .wdata_b(32'd0), .we_b(1'b0));

    initial begin
        // ---- STORE ----
        opc = 6'b010000;      // STORE
        inData = 32'hCAFE_BABE;
        #10;                  // 1 ciclo de clock
        if (MEM.mem[3] !== 32'hCAFE_BABE) $fatal("STORE falhou");

        // ---- LOAD ----
        opc = 6'b001111;      // LOAD
        #10;
        if (outData !== 32'hCAFE_BABE)   $fatal("LOAD falhou");

        // ---- ADDI / ALU ----
        opc = 6'b000001;      // ADDI
        if (aluOp !== 4'h0 || aluSrc !== 1 || regWrite !== 1)
            $fatal("Controle ADDI incorreto");

        $display("Todos os testes passaram!");
        $finish;
    end
endmodule
