`timescale 1ns / 1ps

// SW em 4088 desvia o PC e arma o retorno. O HLT armado volta para PC+1.
// O HLT seguinte, já sem arma, congela o PC como o tb_lcd espera.

module tb_retorno;
    reg         CLOCK_50;
    reg  [17:0] SW;
    reg  [3:0]  KEY;
    wire [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6;
    wire [17:0] LEDR;
    wire [7:0]  LCD_DATA;
    wire        LCD_EN, LCD_RS, LCD_RW, LCD_ON, LCD_BLON;

    Processador_GUI_MIPS #(
        .CPU_DIV(1),
        .BTN_STABLE(3),
        .ROM_FILE("tb_retorno.txt"),
        .LCD_T_POWER(8),
        .LCD_T_INIT1(4),
        .LCD_T_INIT2(3),
        .LCD_T_CLEAR(6),
        .LCD_T_CMD(4),
        .LCD_T_SETUP(2),
        .LCD_T_EN(2)
    ) uut (
        .CLOCK_50(CLOCK_50), .SW(SW), .KEY(KEY),
        .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3),
        .HEX4(HEX4), .HEX5(HEX5), .HEX6(HEX6), .LEDR(LEDR),
        .LCD_DATA(LCD_DATA), .LCD_EN(LCD_EN), .LCD_RS(LCD_RS),
        .LCD_RW(LCD_RW), .LCD_ON(LCD_ON), .LCD_BLON(LCD_BLON)
    );

    integer n, fails;
    reg saw_leaf;

    initial CLOCK_50 = 1'b0;
    always #10 CLOCK_50 = ~CLOCK_50;

    initial begin
        fails = 0;
        saw_leaf = 1'b0;
        SW = 18'd0;
        KEY = 4'b1111;
        KEY[0] = 1'b0;
        repeat (40) @(posedge CLOCK_50);
        KEY[0] = 1'b1;

        for (n = 0; n < 4000 && !(uut.pc === 32'd3 && LEDR[16]); n = n + 1) begin
            @(posedge uut.clk_cpu);
            if (uut.pc === 32'd3072)
                saw_leaf = 1'b1;
        end

        if (!saw_leaf) begin
            $display("FAIL nao executou o HLT da folha, pc=%0d", uut.pc);
            fails = fails + 1;
        end else
            $display("PASS HLT armado na folha");

        if (uut.pc !== 32'd3 || !LEDR[16]) begin
            $display("FAIL HLT sem arma nao congelou, pc=%0d halt=%b", uut.pc, LEDR[16]);
            fails = fails + 1;
        end else
            $display("PASS HLT sem arma congelou em 3");

        if (uut.RF.rf[9] !== 32'd1) begin
            $display("FAIL retorno nao executou o ADDI, t1=%0d", uut.RF.rf[9]);
            fails = fails + 1;
        end else
            $display("PASS voltou e executou a instrucao seguinte");

        if (uut.kret !== 32'd2 || uut.DRAM.mem[1042] !== 32'd2) begin
            $display("FAIL kret=%0d ram1042=%0d", uut.kret, uut.DRAM.mem[1042]);
            fails = fails + 1;
        end else
            $display("PASS kret e RAM 1042 guardam PC+1");

        if (uut.armed !== 1'b0 || uut.cause_reg !== 32'd2 || uut.epc !== 32'd3072) begin
            $display("FAIL armed=%b cause=%0d epc=%0d", uut.armed, uut.cause_reg, uut.epc);
            fails = fails + 1;
        end else
            $display("PASS causa 2, epc na folha, arma desligada");

        if (fails == 0)
            $display("PASS tb_retorno");
        else
            $display("FAIL tb_retorno (%0d)", fails);
        $finish;
    end
endmodule
