`timescale 1ns / 1ps

// Testbench do top-level Processador_GUI_MIPS.
// Simulação: iverilog -g2012 -o sim tb_processador.v *.v && vvp sim
// Requer tb_inout.txt e gcd.txt no diretório de execução.

module tb_processador;

    parameter CPU_DIV    = 1;
    parameter BTN_STABLE = 3;

    reg        CLOCK_50;
    reg [17:0] SW;
    reg [3:0]  KEY;
    wire [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6;
    wire [17:0] LEDR;

    reg  [31:0] alu_a, alu_b;
    reg  [3:0]  alu_op;
    reg  [7:0]  alu_shamt;
    wire [31:0] alu_y;

    alu u_alu (
        .a(alu_a), .b(alu_b), .op(alu_op), .shamt(alu_shamt),
        .y(alu_y), .hi_out(), .lo_out(), .zero()
    );

    Processador_GUI_MIPS #(
        .CPU_DIV(CPU_DIV),
        .BTN_STABLE(BTN_STABLE),
        .ROM_FILE("tb_inout.txt")
    ) uut (
        .CLOCK_50(CLOCK_50), .SW(SW), .KEY(KEY),
        .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3),
        .HEX4(HEX4), .HEX5(HEX5), .HEX6(HEX6), .LEDR(LEDR)
    );

    initial CLOCK_50 = 1'b0;
    always #10 CLOCK_50 = ~CLOCK_50;

    task automatic pulse_key1;
        begin
            KEY[1] = 1'b0;
            repeat (BTN_STABLE + 20) @(posedge CLOCK_50);
            KEY[1] = 1'b1;
            repeat (BTN_STABLE + 20) @(posedge CLOCK_50);
        end
    endtask

    task automatic apply_reset;
        begin
            KEY[0] = 1'b0;
            repeat (BTN_STABLE + 20) @(posedge CLOCK_50);
            KEY[0] = 1'b1;
            repeat (BTN_STABLE + 20) @(posedge CLOCK_50);
        end
    endtask

    initial begin
        integer n;
        reg halted;

        $display("=== tb_processador: SR (ALU) ===");
        alu_a = 32'hFFFF_FFF8; alu_b = 32'd0; alu_op = 4'h6; alu_shamt = 8'd1;
        #1;
        if (alu_y === 32'hFFFF_FFFC)
            $display("PASS SR: -8 >> 1 = %0d", $signed(alu_y));
        else
            $display("FAIL SR: esperado -4, obteve %h", alu_y);

        $display("=== tb_processador: IN/OUT/HLT (tb_inout.txt) ===");
        SW = 0; KEY = 4'b1111;
        apply_reset();

        for (n = 0; n < 50000; n = n + 1) begin
            @(posedge uut.clk_cpu);
            if (LEDR[17]) begin
                SW[9:0] = 10'd42;
                pulse_key1();
                n = 50000;
            end
        end

        halted = 0;
        for (n = 0; n < 50000; n = n + 1) begin
            @(posedge uut.clk_cpu);
            if (LEDR[16]) begin
                halted = 1;
                if (uut.out_reg === 32'd42)
                    $display("PASS top-level: IN(42) -> OUT(42)");
                else
                    $display("FAIL top-level: esperado 42, obteve %0d", uut.out_reg);
                n = 50000;
            end
        end
        if (!halted)
            $display("FAIL top-level: HLT nao atingido (pc=%0d stall=%b)", uut.pc, LEDR[17]);

        $display("=== Fim ===");
        $finish;
    end

endmodule
