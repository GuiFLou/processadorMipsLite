`timescale 1ns / 1ps

// Exercita display_ctx (1019) via SW/LW, catálogo MENU e KEY[2]/KEY[3].
// Programa: tb_lcd_mmio.txt (sem IN/OUT).

module tb_lcd;

    parameter CPU_DIV    = 1;
    parameter BTN_STABLE = 3;

    reg         CLOCK_50;
    reg  [17:0] SW;
    reg  [3:0]  KEY;
    wire [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6;
    wire [17:0] LEDR;
    wire [7:0]  LCD_DATA;
    wire        LCD_EN, LCD_RS, LCD_RW, LCD_ON, LCD_BLON;

    Processador_GUI_MIPS #(
        .CPU_DIV     (CPU_DIV),
        .BTN_STABLE  (BTN_STABLE),
        .ROM_FILE    ("tb_lcd_mmio.txt"),
        .LCD_T_POWER (8),
        .LCD_T_INIT1 (4),
        .LCD_T_INIT2 (3),
        .LCD_T_CLEAR (6),
        .LCD_T_CMD   (4),
        .LCD_T_SETUP (2),
        .LCD_T_EN    (2)
    ) uut (
        .CLOCK_50(CLOCK_50), .SW(SW), .KEY(KEY),
        .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3),
        .HEX4(HEX4), .HEX5(HEX5), .HEX6(HEX6), .LEDR(LEDR),
        .LCD_DATA(LCD_DATA), .LCD_EN(LCD_EN), .LCD_RS(LCD_RS),
        .LCD_RW(LCD_RW), .LCD_ON(LCD_ON), .LCD_BLON(LCD_BLON)
    );

    initial CLOCK_50 = 1'b0;
    always #10 CLOCK_50 = ~CLOCK_50;

    task pulse_key;
        input integer idx;
        begin
            KEY[idx] = 0;
            repeat (BTN_STABLE + 20) @(posedge CLOCK_50);
            KEY[idx] = 1;
            repeat (BTN_STABLE + 20) @(posedge CLOCK_50);
        end
    endtask

    reg [7:0] line1_cap [0:15];
    integer   col_cap;
    integer   n;
    integer   fails;

    always @(negedge LCD_EN) begin
        if (!LCD_RS && LCD_DATA == 8'h01)
            col_cap = 0;
        else if (LCD_RS && LCD_ON && col_cap < 16) begin
            line1_cap[col_cap] = LCD_DATA;
            col_cap = col_cap + 1;
        end
    end

    task wait_idle;
        begin
            for (n = 0; n < 40000 && !uut.u_lcd.idle; n = n + 1)
                @(posedge CLOCK_50);
        end
    endtask

    initial begin
        fails = 0;
        col_cap = 0;
        SW = 0;
        KEY = 4'b1111;

        KEY[0] = 0;
        repeat (40) @(posedge CLOCK_50);
        KEY[0] = 1;
        wait_idle();

        if (LCD_ON !== 1'b1 || LCD_RW !== 1'b0 || LCD_BLON !== 1'b1) begin
            $display("FAIL LCD: ON/RW/BLON");
            fails = fails + 1;
        end else
            $display("PASS LCD: ON RW BLON");

        for (n = 0; n < 5000 && uut.disp_mode !== 8'd1; n = n + 1)
            @(posedge uut.clk_cpu);
        if (uut.disp_mode !== 8'd1) begin
            $display("FAIL SW 1019: mode nao chegou a 1");
            fails = fails + 1;
        end else
            $display("PASS SW 1019: mode=1");

        for (n = 0; n < 40000; n = n + 1) begin
            @(posedge CLOCK_50);
            if (uut.u_lcd.idle && line1_cap[0] === "M" && line1_cap[1] === "E" &&
                line1_cap[2] === "N" && line1_cap[3] === "U")
                n = 40000;
        end

        if (line1_cap[0] !== "M" || line1_cap[1] !== "E" ||
            line1_cap[2] !== "N" || line1_cap[3] !== "U") begin
            $display("FAIL LCD: linha1 nao e MENU (%c%c%c%c)",
                     line1_cap[0], line1_cap[1], line1_cap[2], line1_cap[3]);
            fails = fails + 1;
        end else
            $display("PASS LCD: MENU na linha 1");

        pulse_key(3);
        @(posedge uut.clk_cpu);
        @(posedge uut.clk_cpu);
        if (uut.disp_sel !== 5'd1) begin
            $display("FAIL KEY3: sel=%0d", uut.disp_sel);
            fails = fails + 1;
        end else
            $display("PASS KEY3: sel=1");

        pulse_key(3);
        @(posedge uut.clk_cpu);
        @(posedge uut.clk_cpu);
        if (uut.disp_sel !== 5'd2) begin
            $display("FAIL KEY3#2: sel=%0d", uut.disp_sel);
            fails = fails + 1;
        end

        pulse_key(2);
        @(posedge uut.clk_cpu);
        @(posedge uut.clk_cpu);
        if (uut.disp_sel !== 5'd1) begin
            $display("FAIL KEY2: sel=%0d", uut.disp_sel);
            fails = fails + 1;
        end else
            $display("PASS KEY2: sel voltou a 1");

        begin : hold_sel
            reg [4:0] sel_before;
            sel_before = uut.disp_sel;
            pulse_key(1);
            @(posedge uut.clk_cpu);
            @(posedge uut.clk_cpu);
            if (uut.disp_sel !== sel_before) begin
                $display("FAIL KEY1: alterou sel");
                fails = fails + 1;
            end else
                $display("PASS KEY1: sel inalterado");
        end

        for (n = 0; n < 20000 && !LEDR[16]; n = n + 1)
            @(posedge uut.clk_cpu);
        if (!LEDR[16]) begin
            $display("FAIL HLT: programa nao parou");
            fails = fails + 1;
        end

        /* $t1 = LW apos as teclas; $t2 = LW apos SW do mesmo modo */
        if (uut.RF.rf[9][7:0] !== 8'd1 || uut.RF.rf[9][26:22] !== 5'd1) begin
            $display("FAIL LW 1019 $t1: %h", uut.RF.rf[9]);
            fails = fails + 1;
        end else
            $display("PASS LW 1019: mode+sel no $t1");

        if (uut.RF.rf[10][7:0] !== 8'd1 || uut.RF.rf[10][26:22] !== 5'd1) begin
            $display("FAIL same-mode SW zerou sel: %h", uut.RF.rf[10]);
            fails = fails + 1;
        end else
            $display("PASS same-mode SW: sel preservado");

        if (uut.RF.rf[8][7:0] !== 8'd2 || uut.RF.rf[8][26:22] !== 5'd0) begin
            $display("FAIL mode-change sel: %h", uut.RF.rf[8]);
            fails = fails + 1;
        end else
            $display("PASS mode-change: sel zerado");

        if (uut.RF.rf[12] !== 32'd77) begin
            $display("FAIL RAM 1016: $t4=%0d", uut.RF.rf[12]);
            fails = fails + 1;
        end else
            $display("PASS RAM 1016: 77");

        if (fails == 0)
            $display("PASS tb_lcd");
        else
            $display("FAIL tb_lcd (%0d)", fails);
        $finish;
    end
endmodule
