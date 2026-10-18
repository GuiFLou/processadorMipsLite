`timescale 1ns / 1ps

// Exercita display_ctx (4091): SW/LW, catálogo, KEY[2]/KEY[3] e o ack do KEY[1].
// Programa: tb_lcd_mmio.txt. O IN no final prova que o Enter da entrada
// não liga o ack.

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
            $display("FAIL SW 4091: mode nao chegou a 1");
            fails = fails + 1;
        end else
            $display("PASS SW 4091: mode=1");

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

        pulse_key(3);
        @(posedge uut.clk_cpu);
        @(posedge uut.clk_cpu);
        if (uut.disp_sel !== 5'd0) begin
            $display("FAIL KEY3 wrap: sel=%0d", uut.disp_sel);
            fails = fails + 1;
        end else
            $display("PASS KEY3: sel voltou a 0");

        pulse_key(2);
        @(posedge uut.clk_cpu);
        @(posedge uut.clk_cpu);
        if (uut.disp_sel !== 5'd2) begin
            $display("FAIL KEY2 wrap: sel=%0d", uut.disp_sel);
            fails = fails + 1;
        end else
            $display("PASS KEY2: sel foi a 2");

        pulse_key(3);
        @(posedge uut.clk_cpu);
        @(posedge uut.clk_cpu);
        pulse_key(3);
        @(posedge uut.clk_cpu);
        @(posedge uut.clk_cpu);
        if (uut.disp_sel !== 5'd1) begin
            $display("FAIL KEY3 volta: sel=%0d", uut.disp_sel);
            fails = fails + 1;
        end

        begin : hold_sel
            reg [4:0] sel_before;
            sel_before = uut.disp_sel;
            pulse_key(1);
            @(posedge uut.clk_cpu);
            @(posedge uut.clk_cpu);
            if (uut.disp_sel !== sel_before || uut.disp_ack !== 1'b1) begin
                $display("FAIL KEY1: sel=%0d ack=%b", uut.disp_sel, uut.disp_ack);
                fails = fails + 1;
            end else
                $display("PASS KEY1: sel inalterado, ack=1");
        end

        begin : release_in
            reg saw_in;
            reg saw_edge;
            reg [4:0] sel_now;
            integer k;
            saw_in = 1'b0;
            saw_edge = 1'b0;
            for (n = 0; n < 20000 && !LEDR[16]; n = n + 1) begin
                @(posedge uut.clk_cpu);
                if (LEDR[17] && !saw_in) begin
                    saw_in = 1'b1;
                    if (uut.disp_ack !== 1'b0 || uut.disp_mode !== 8'd1 ||
                        uut.disp_sel !== 5'd0) begin
                        $display("FAIL IN: mode=%0d sel=%0d ack=%b",
                                 uut.disp_mode, uut.disp_sel, uut.disp_ack);
                        fails = fails + 1;
                    end
                    SW[9:0] = 10'd37;
                    /* O pulso nasce no aperto. KEY[1] e KEY[3] descem juntos. */
                    KEY[1] = 1'b0;
                    KEY[3] = 1'b0;
                    for (k = 0; k < 80 && !saw_edge; k = k + 1) begin
                        @(posedge uut.clk_cpu);
                        if (uut.enter_pulse && uut.right_pulse) begin
                            saw_edge = 1'b1;
                            sel_now = uut.disp_sel;
                            @(posedge uut.clk_cpu);
                            if (uut.disp_sel !== sel_now || uut.disp_ack !== 1'b0 ||
                                uut.RF.rf[15] !== 32'd37) begin
                                $display("FAIL IN+KEY3: sel %0d->%0d ack=%b $t7=%0d",
                                         sel_now, uut.disp_sel, uut.disp_ack, uut.RF.rf[15]);
                                fails = fails + 1;
                            end else
                                $display("PASS IN: KEY1+KEY3 gravou 37 sem ack e sem andar");
                        end
                    end
                    KEY[1] = 1'b1;
                    KEY[3] = 1'b1;
                    repeat (BTN_STABLE + 20) @(posedge CLOCK_50);
                end
            end
            if (!saw_in) begin
                $display("FAIL IN: CPU nao parou no IN");
                fails = fails + 1;
            end
            if (!saw_edge) begin
                $display("FAIL IN: KEY1 e KEY3 nao pulsaram juntos");
                fails = fails + 1;
            end
        end
        if (!LEDR[16]) begin
            $display("FAIL HLT: programa nao parou");
            fails = fails + 1;
        end

        /* $t1 = LW apos as teclas; $t2 = LW apos SW do mesmo modo */
        if (uut.RF.rf[9][7:0] !== 8'd1 || uut.RF.rf[9][26:22] !== 5'd1 ||
            uut.RF.rf[9][27] !== 1'b1) begin
            $display("FAIL LW 4091 $t1: %h", uut.RF.rf[9]);
            fails = fails + 1;
        end else
            $display("PASS LW 4091: mode+sel+ack no $t1");

        if (uut.RF.rf[10][7:0] !== 8'd1 || uut.RF.rf[10][26:22] !== 5'd1 ||
            uut.RF.rf[10][27] !== 1'b0) begin
            $display("FAIL same-mode SW: %h", uut.RF.rf[10]);
            fails = fails + 1;
        end else
            $display("PASS same-mode SW: sel preservado, ack zerado");

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

        if (uut.RF.rf[13] !== 32'd0 || uut.DRAM.mem[4088] !== 32'd0) begin
            $display("FAIL CSR 4088: $t5=%0d ram=%0d", uut.RF.rf[13], uut.DRAM.mem[4088]);
            fails = fails + 1;
        end else
            $display("PASS CSR 4088: leitura 0, RAM intacta");

        if (uut.RF.rf[14][7:0] !== 8'd2 || uut.disp_mode !== 8'd2 ||
            uut.DRAM.mem[4091] !== 32'd0) begin
            $display("FAIL alias 8187: $t6=%h mode=%0d ram4091=%0d",
                     uut.RF.rf[14], uut.disp_mode, uut.DRAM.mem[4091]);
            fails = fails + 1;
        end else
            $display("PASS alias 8187: display_ctx intacto");

        /* Modo 2 tem um item e a CPU já parou. KEY[1] ainda confirma. */
        pulse_key(1);
        @(posedge uut.clk_cpu);
        @(posedge uut.clk_cpu);
        if (uut.disp_ack !== 1'b1 || uut.disp_sel !== 5'd0 || uut.disp_mode !== 8'd2) begin
            $display("FAIL KEY1 apos HLT: ack=%b sel=%0d mode=%0d",
                     uut.disp_ack, uut.disp_sel, uut.disp_mode);
            fails = fails + 1;
        end else
            $display("PASS KEY1 apos HLT: ack=1 com um item");

        force uut.disp_mode = 8'd1;
        force uut.disp_sel  = 5'd2;
        force uut.disp_id   = 10'd0;
        repeat (8) @(posedge CLOCK_50);
        if (uut.u_lcd.line2[0] !== ">" || uut.u_lcd.line2[1] !== "3" ||
            uut.u_lcd.line2[3] !== "A" || uut.u_lcd.line2[5] !== "Q") begin
            $display("FAIL catalogo MENU");
            fails = fails + 1;
        end else
            $display("PASS catalogo: 3 ARQ");

        force uut.disp_mode = 8'd6;
        force uut.disp_sel  = 5'd0;
        force uut.disp_id   = 10'd1;
        repeat (8) @(posedge CLOCK_50);
        if (uut.disp_nitems !== 5'd10 ||
            uut.u_lcd.line1[0] !== "P" || uut.u_lcd.line2[1] !== "0" ||
            uut.u_lcd.line2[4] !== "1" || uut.u_lcd.line2[6] !== "A" ||
            uut.u_lcd.line2[9] !== "A") begin
            $display("FAIL catalogo PROG");
            fails = fails + 1;
        end else
            $display("PASS catalogo: >0001 AREA");

        force uut.disp_sel = 5'd9;
        repeat (8) @(posedge CLOCK_50);
        if (uut.u_lcd.line2[6] !== "S" || uut.u_lcd.line2[9] !== "T") begin
            $display("FAIL catalogo SORT");
            fails = fails + 1;
        end else
            $display("PASS catalogo: SORT");

        force uut.disp_mode = 8'd7;
        force uut.disp_sel  = 5'd9;
        repeat (8) @(posedge CLOCK_50);
        if (uut.disp_nitems !== 5'd10 ||
            uut.u_lcd.line1[0] !== "Q" || uut.u_lcd.line2[0] !== ">" ||
            uut.u_lcd.line2[1] !== "1" || uut.u_lcd.line2[2] !== "0") begin
            $display("FAIL catalogo QUANTOS");
            fails = fails + 1;
        end else
            $display("PASS catalogo: >10");

        force uut.disp_mode = 8'd2;
        repeat (8) @(posedge CLOCK_50);
        if (uut.u_lcd.line1[0] !== "B" || uut.u_lcd.line1[3] !== "-" ||
            uut.u_lcd.line1[8] !== "O" || uut.u_lcd.line2[0] !== "S" ||
            uut.u_lcd.line2[1] !== "O") begin
            $display("FAIL catalogo BEM-VINDO");
            fails = fails + 1;
        end else
            $display("PASS catalogo: BEM-VINDO");

        force uut.disp_mode = 8'd8;
        repeat (8) @(posedge CLOCK_50);
        if (uut.disp_nitems !== 5'd1 ||
            uut.u_lcd.line1[0] !== "A" || uut.u_lcd.line2[0] !== "F" ||
            uut.u_lcd.line2[5] !== "3") begin
            $display("FAIL catalogo ARQ");
            fails = fails + 1;
        end else
            $display("PASS catalogo: FASE 3");
        release uut.disp_mode;
        release uut.disp_sel;
        release uut.disp_id;

        if (fails == 0)
            $display("PASS tb_lcd");
        else
            $display("FAIL tb_lcd (%0d)", fails);
        $finish;
    end
endmodule
