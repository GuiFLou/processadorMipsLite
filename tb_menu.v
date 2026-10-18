`timescale 1ns / 1ps

// Roda so/src/so.txt: boas-vindas, menu e as tres opcoes.
// Compilar antes, a partir de so/src:
//   ../../compilador/compilador --txt so.cms
module tb_menu;
    parameter BTN_STABLE = 3;

    reg         CLOCK_50;
    reg  [17:0] SW;
    reg  [3:0]  KEY;
    wire [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6;
    wire [17:0] LEDR;
    wire [7:0]  LCD_DATA;
    wire        LCD_EN, LCD_RS, LCD_RW, LCD_ON, LCD_BLON;

    Processador_GUI_MIPS #(
        .CPU_DIV(1),
        .BTN_STABLE(BTN_STABLE),
        .ROM_FILE("../so/src/so.txt"),
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

    initial CLOCK_50 = 1'b0;
    always #10 CLOCK_50 = ~CLOCK_50;

    integer n;
    integer fails;
    integer picks;
    reg     saw_stall;

    task pulse_key;
        input integer idx;
        begin
            KEY[idx] = 1'b0;
            repeat (BTN_STABLE + 20) @(posedge CLOCK_50);
            KEY[idx] = 1'b1;
            repeat (BTN_STABLE + 20) @(posedge CLOCK_50);
        end
    endtask

    task wait_mode;
        input integer wanted;
        begin
            for (n = 0; n < 100000 && uut.disp_mode !== wanted; n = n + 1) begin
                @(posedge uut.clk_cpu);
                if (LEDR[17])
                    saw_stall = 1'b1;
            end
            if (uut.disp_mode !== wanted) begin
                $display("FAIL modo %0d, ficou %0d", wanted, uut.disp_mode);
                fails = fails + 1;
            end
        end
    endtask

    task wait_id;
        input integer wanted;
        begin
            for (n = 0; n < 100000 && uut.disp_id !== wanted; n = n + 1) begin
                @(posedge uut.clk_cpu);
                if (LEDR[17])
                    saw_stall = 1'b1;
            end
            if (uut.disp_id !== wanted) begin
                $display("FAIL id %0d, ficou %0d", wanted, uut.disp_id);
                fails = fails + 1;
            end
        end
    endtask

    /* O software viu o Enter e reescreveu a tela, zerando o ack. */
    task wait_rearm;
        begin
            for (n = 0; n < 100000 && uut.disp_ack !== 1'b0; n = n + 1) begin
                @(posedge uut.clk_cpu);
                if (LEDR[17])
                    saw_stall = 1'b1;
            end
            if (uut.disp_ack !== 1'b0) begin
                $display("FAIL rearm: ack ficou 1 no modo %0d", uut.disp_mode);
                fails = fails + 1;
            end
        end
    endtask

    initial begin
        fails = 0;
        saw_stall = 1'b0;
        SW = 18'd0;
        KEY = 4'b1111;
        KEY[0] = 1'b0;
        repeat (40) @(posedge CLOCK_50);
        KEY[0] = 1'b1;

        wait_mode(8'd2);
        repeat (8) @(posedge CLOCK_50);
        if (uut.u_lcd.line1[0] !== "B") begin
            $display("FAIL boas-vindas");
            fails = fails + 1;
        end else
            $display("PASS boas-vindas");

        pulse_key(1);
        wait_mode(8'd1);
        if (uut.disp_sel !== 5'd0) begin
            $display("FAIL menu sel=%0d", uut.disp_sel);
            fails = fails + 1;
        end else
            $display("PASS menu");

        pulse_key(3);
        pulse_key(3);
        @(posedge uut.clk_cpu);
        if (uut.disp_mode !== 8'd1 || uut.disp_sel !== 5'd2) begin
            $display("FAIL andar ate ARQ: mode=%0d sel=%0d", uut.disp_mode, uut.disp_sel);
            fails = fails + 1;
        end
        pulse_key(1);
        wait_mode(8'd8);
        $display("PASS arquivos");
        pulse_key(1);
        wait_mode(8'd1);

        pulse_key(1);
        wait_mode(8'd6);
        wait_id(10'd1);
        $display("PASS lista no primeiro programa");
        pulse_key(3);
        wait_id(10'd2);
        pulse_key(3);
        wait_id(10'd3);
        if (uut.disp_sel !== 5'd2) begin
            $display("FAIL lista sel=%0d", uut.disp_sel);
            fails = fails + 1;
        end else
            $display("PASS lista acompanhou o indice");
        pulse_key(1);
        wait_mode(8'd3);
        if (uut.disp_id !== 10'd3 || uut.disp_pid !== 4'd15) begin
            $display("FAIL run: id=%0d pid=%0d", uut.disp_id, uut.disp_pid);
            fails = fails + 1;
        end else
            $display("PASS run do id 3, sem executar");
        pulse_key(1);
        wait_mode(8'd1);

        pulse_key(3);
        @(posedge uut.clk_cpu);
        pulse_key(1);
        wait_mode(8'd7);
        pulse_key(3);
        pulse_key(3);
        @(posedge uut.clk_cpu);
        if (uut.disp_sel !== 5'd2) begin
            $display("FAIL quantos sel=%0d", uut.disp_sel);
            fails = fails + 1;
        end else
            $display("PASS quantos N=3");
        pulse_key(1);

        for (picks = 0; picks < 3; picks = picks + 1) begin
            wait_mode(8'd6);
            wait_rearm();
            if (uut.disp_mode !== 8'd6) begin
                $display("FAIL escolha %0d caiu no modo %0d", picks, uut.disp_mode);
                fails = fails + 1;
            end
            pulse_key(1);
        end
        wait_mode(8'd5);
        $display("PASS tres escolhas e erro");
        pulse_key(1);
        wait_mode(8'd1);

        if (saw_stall) begin
            $display("FAIL CPU parou em IN/OUT");
            fails = fails + 1;
        end else
            $display("PASS sem IN/OUT");

        if (fails == 0)
            $display("PASS tb_menu");
        else
            $display("FAIL tb_menu (%0d)", fails);
        $finish;
    end
endmodule
