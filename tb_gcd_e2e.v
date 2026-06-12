`timescale 1ns / 1ps

module tb_gcd_e2e;

    parameter CPU_DIV    = 1;
    parameter BTN_STABLE = 3;

    reg        CLOCK_50;
    reg [17:0] SW;
    reg [3:0]  KEY;
    wire [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6;
    wire [17:0] LEDR;

    Processador_GUI_MIPS #(
        .CPU_DIV(CPU_DIV), .BTN_STABLE(BTN_STABLE), .ROM_FILE("gcd.txt")
    ) uut (
        .CLOCK_50(CLOCK_50), .SW(SW), .KEY(KEY),
        .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3),
        .HEX4(HEX4), .HEX5(HEX5), .HEX6(HEX6), .LEDR(LEDR)
    );

    initial CLOCK_50 = 1'b0;
    always #10 CLOCK_50 = ~CLOCK_50;

    task pulse_key1;
        begin
            KEY[1] = 0;
            repeat (BTN_STABLE + 20) @(posedge CLOCK_50);
            KEY[1] = 1;
            repeat (BTN_STABLE + 20) @(posedge CLOCK_50);
        end
    endtask

    initial begin
        integer n, in_i, last_pc;
        reg stall_prev;
        reg [9:0] in_a, in_b;
        reg saw_in;

        in_a = 48;
        in_b = 18;
        saw_in = 0;

        $display("=== E2E gcd.txt ===");
        $display("MDC(%0d,%0d) esperado=6 | SW[9:0] entradas + KEY[1] cada IN", in_a, in_b);

        SW = 0; KEY = 4'b1111;
        KEY[0] = 0;
        repeat (50) @(posedge CLOCK_50);
        KEY[0] = 1;
        repeat (200) @(posedge CLOCK_50);

        in_i = 0;
        stall_prev = 0;
        last_pc = -1;

        for (n = 0; n < 5000000; n = n + 1) begin
            @(posedge uut.clk_cpu);

            if (uut.pc !== last_pc) begin
                if (uut.instr[31:26] == 6'b011010)
                    $display("  opcode IN @ pc=%0d", uut.pc);
                last_pc = uut.pc;
            end

            if (LEDR[17] && !stall_prev) begin
                saw_in = 1;
                SW[9:0] = (in_i == 0) ? in_a : (in_i == 1) ? in_b :
                          (in_i % 2 == 0) ? in_a : in_b;
                $display(">> IN #%0d @ pc=%0d SW[9:0]=%0d (KEY[1])", in_i + 1,
                         uut.pc, SW[9:0]);
                pulse_key1();
                in_i = in_i + 1;
                stall_prev = 0;
            end else
                stall_prev = LEDR[17];

            if (LEDR[16]) begin
                if (uut.out_reg == 6)
                    $display("PASS E2E: MDC(%0d,%0d)=%0d", in_a, in_b, uut.out_reg);
                else
                    $display("FAIL E2E: esperado 6, obteve %0d (pc=%0d)",
                             uut.out_reg, uut.pc);
                $finish;
            end
        end

        $display("FAIL E2E: timeout pc=%0d INs=%0d saw_in_opcode=%b",
                 uut.pc, in_i, saw_in);
        $finish;
    end
endmodule
