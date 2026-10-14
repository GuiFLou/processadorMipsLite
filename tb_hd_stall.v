`timescale 1ns / 1ps

// O SW em hd_cmd segura o PC durante as 256 palavras e avança uma vez no fim.

module tb_hd_stall;
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
        .ROM_FILE("tb_hd_stall.txt"),
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

    integer held, fails, n;

    initial CLOCK_50 = 1'b0;
    always #10 CLOCK_50 = ~CLOCK_50;

    initial begin
        fails = 0;
        SW = 18'd0;
        KEY = 4'b1111;
        KEY[0] = 1'b0;
        repeat (40) @(posedge CLOCK_50);
        KEY[0] = 1'b1;

        held = 0;
        for (n = 0; n < 5000 && uut.pc !== 32'd5; n = n + 1)
            @(posedge uut.clk_cpu);
        if (uut.pc !== 32'd5) begin
            $display("FAIL nao chegou no SW hd_cmd, pc=%0d", uut.pc);
            fails = fails + 1;
        end else begin
            while (uut.pc === 32'd5 && held < 1000) begin
                held = held + 1;
                @(posedge uut.clk_cpu);
            end
            // Aceite + 256 ciclos de leitura + o ciclo que grava a 256ª e avança o PC.
            if (held !== 258 || uut.pc !== 32'd6) begin
                $display("FAIL stall pc=%0d ciclos=%0d", uut.pc, held);
                fails = fails + 1;
            end else
                $display("PASS hd_cmd segurou o PC por %0d ciclos", held);
        end

        for (n = 0; n < 20 && !LEDR[16]; n = n + 1)
            @(posedge uut.clk_cpu);
        if (uut.RF.rf[9] !== 32'd1) begin
            $display("FAIL instrucao seguinte nao rodou, t1=%0d", uut.RF.rf[9]);
            fails = fails + 1;
        end else
            $display("PASS PC avancou uma vez e executou o ADDI");

        if (uut.IMEM.mem[3072] !== uut.HD.storage[5120]) begin
            $display("FAIL copia %h", uut.IMEM.mem[3072]);
            fails = fails + 1;
        end else
            $display("PASS setor 20 copiado na folha");

        if (fails == 0)
            $display("PASS tb_hd_stall");
        else
            $display("FAIL tb_hd_stall (%0d)", fails);
        $finish;
    end
endmodule
