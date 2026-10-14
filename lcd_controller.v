// lcd_controller.v — HD44780 16x2 com catálogo de mensagens fixas
//
// Relógio CLOCK_50. A CPU entrega modo/ID/PID/sel; o módulo sincroniza
// com 2 FFs e só usa o segundo (estável) no catálogo e no refresh.
//
// Init: espera >40 ms, 0x30 × 3 (4.1 ms / 100 us / 40 us), function set
// 0x38, display off, clear, entry mode, display on.
// Cada byte: RS/DATA estáveis (tAS), depois pulso EN.
//
// T_* em ciclos de clk. Defaults para 50 MHz. O testbench reduz.

module lcd_controller #(
    parameter T_POWER = 2_000_000, // > 40 ms @ 50 MHz
    parameter T_INIT1 = 220_000,   // > 4.1 ms após o 1º 0x30
    parameter T_INIT2 = 6_000,     // > 100 us após o 2º 0x30
    parameter T_CLEAR = 100_000,   // ~2.0 ms (folga sobre 1.52 ms)
    parameter T_CMD   = 2_000,     // >= 40 us
    parameter T_SETUP = 3,         // EN=0 após RS/DATA; tAS >= 40 ns
    parameter T_EN    = 20         // pulso EN >= 230 ns
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  mode,
    input  wire [9:0]  prog_id,
    input  wire [3:0]  pid,
    input  wire [4:0]  sel,
    output reg  [7:0]  LCD_DATA,
    output reg         LCD_EN,
    output reg         LCD_RS,
    output wire        LCD_RW,
    output wire        LCD_ON,
    output wire        LCD_BLON,
    output wire        idle
);
    assign LCD_RW   = 1'b0;
    assign LCD_ON   = 1'b1;
    assign LCD_BLON = 1'b1;

    localparam [4:0]
        ST_POWER    = 5'd0,
        ST_I30A     = 5'd1,
        ST_I30B     = 5'd2,
        ST_I30C     = 5'd3,
        ST_I38      = 5'd4,
        ST_I08      = 5'd5,
        ST_I01      = 5'd6,
        ST_I06      = 5'd7,
        ST_I0C      = 5'd8,
        ST_IDLE     = 5'd9,
        ST_CLEAR    = 5'd10,
        ST_L1       = 5'd11,
        ST_DDRAM2   = 5'd12,
        ST_L2       = 5'd13,
        ST_SETUP    = 5'd14,
        ST_PULSE    = 5'd15,
        ST_WAIT     = 5'd16;

    reg [4:0]  state, ret_state;
    assign idle = (state == ST_IDLE);
    reg [20:0] timer;
    reg [4:0]  col;
    reg        wait_clear;
    reg        need_refresh;

    /* 2 FFs de CDC; o catálogo lê só o 2º. */
    reg [7:0]  mode_s, mode_q, mode_d;
    reg [9:0]  id_s, id_q, id_d;
    reg [3:0]  pid_s, pid_q, pid_d;
    reg [4:0]  sel_s, sel_q, sel_d;

    reg [7:0]  line1 [0:15];
    reg [7:0]  line2 [0:15];

    integer i;
    integer val;
    integer d0, d1, d2, d3;

    always @* begin
        for (i = 0; i < 16; i = i + 1) begin
            line1[i] = 8'h20;
            line2[i] = 8'h20;
        end

        case (mode_q)
            8'd1: begin
                line1[0] = "M"; line1[1] = "E"; line1[2] = "N"; line1[3] = "U";
                line2[0] = ">";
                case (sel_q)
                    5'd1: begin line2[1]="M"; line2[2]="L"; line2[3]="T"; end
                    5'd2: begin line2[1]="L"; line2[2]="S"; line2[3]="T"; end
                    5'd3: begin line2[1]="R"; line2[2]="E"; line2[3]="N"; end
                    5'd4: begin line2[1]="D"; line2[2]="E"; line2[3]="L"; end
                    default: begin line2[1]="R"; line2[2]="U"; line2[3]="N"; end
                endcase
            end
            8'd2: begin
                line1[0] = "I"; line1[1] = "D"; line1[2] = "?";
                val = id_q;
                d3 = val / 1000; val = val % 1000;
                d2 = val / 100;  val = val % 100;
                d1 = val / 10;
                d0 = val % 10;
                line2[0] = 8'h30 + d3[3:0];
                line2[1] = 8'h30 + d2[3:0];
                line2[2] = 8'h30 + d1[3:0];
                line2[3] = 8'h30 + d0[3:0];
            end
            8'd3: begin
                line1[0] = "R"; line1[1] = "U"; line1[2] = "N";
                line2[0] = "I"; line2[1] = "D"; line2[2] = " ";
                val = id_q;
                d3 = val / 1000; val = val % 1000;
                d2 = val / 100;  val = val % 100;
                d1 = val / 10;
                d0 = val % 10;
                line2[3] = 8'h30 + d3[3:0];
                line2[4] = 8'h30 + d2[3:0];
                line2[5] = 8'h30 + d1[3:0];
                line2[6] = 8'h30 + d0[3:0];
                line2[7] = " ";
                line2[8] = "P"; line2[9] = "I"; line2[10] = "D"; line2[11] = " ";
                if (pid_q >= 4'd10)
                    line2[12] = "-";
                else
                    line2[12] = 8'h30 + pid_q;
            end
            8'd4: begin
                line1[0] = "O"; line1[1] = "K";
            end
            8'd5: begin
                line1[0] = "E"; line1[1] = "R"; line1[2] = "R";
            end
            default: ;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            mode_s <= 8'd0;
            id_s   <= 10'd0;
            pid_s  <= 4'd15;
            sel_s  <= 5'd0;
            mode_q <= 8'd0;
            id_q   <= 10'd0;
            pid_q  <= 4'd15;
            sel_q  <= 5'd0;
            mode_d <= 8'd0;
            id_d   <= 10'd0;
            pid_d  <= 4'd15;
            sel_d  <= 5'd0;
        end else begin
            mode_s <= mode;
            id_s   <= prog_id;
            pid_s  <= pid;
            sel_s  <= sel;
            mode_q <= mode_s;
            id_q   <= id_s;
            pid_q  <= pid_s;
            sel_q  <= sel_s;
            mode_d <= mode_q;
            id_d   <= id_q;
            pid_d  <= pid_q;
            sel_d  <= sel_q;
        end
    end

    /* Mudança só depois que o 2º FF estabilizou. */
    wire changed = (mode_q != mode_d) || (id_q != id_d) ||
                   (pid_q != pid_d) || (sel_q != sel_d);

    always @(posedge clk) begin
        if (rst) begin
            state        <= ST_POWER;
            ret_state    <= ST_I30A;
            timer        <= T_POWER[20:0];
            col          <= 5'd0;
            wait_clear   <= 1'b0;
            LCD_DATA     <= 8'd0;
            LCD_EN       <= 1'b0;
            LCD_RS       <= 1'b0;
            need_refresh <= 1'b0;
        end else begin
            if (changed)
                need_refresh <= 1'b1;

            case (state)
                ST_POWER: begin
                    LCD_EN <= 1'b0;
                    if (timer == 0) begin
                        LCD_RS     <= 1'b0;
                        LCD_DATA   <= 8'h30;
                        ret_state  <= ST_I30A;
                        wait_clear <= 1'b0;
                        state      <= ST_SETUP;
                        timer      <= T_SETUP[20:0];
                    end else
                        timer <= timer - 21'd1;
                end
                ST_I30A: begin
                    LCD_EN     <= 1'b0;
                    LCD_RS     <= 1'b0;
                    LCD_DATA   <= 8'h30;
                    ret_state  <= ST_I30B;
                    wait_clear <= 1'b0;
                    state      <= ST_SETUP;
                    timer      <= T_SETUP[20:0];
                end
                ST_I30B: begin
                    LCD_EN     <= 1'b0;
                    LCD_RS     <= 1'b0;
                    LCD_DATA   <= 8'h30;
                    ret_state  <= ST_I30C;
                    wait_clear <= 1'b0;
                    state      <= ST_SETUP;
                    timer      <= T_SETUP[20:0];
                end
                ST_I30C: begin
                    LCD_EN     <= 1'b0;
                    LCD_RS     <= 1'b0;
                    LCD_DATA   <= 8'h38;
                    ret_state  <= ST_I38;
                    wait_clear <= 1'b0;
                    state      <= ST_SETUP;
                    timer      <= T_SETUP[20:0];
                end
                ST_I38: begin
                    LCD_EN     <= 1'b0;
                    LCD_RS     <= 1'b0;
                    LCD_DATA   <= 8'h08;
                    ret_state  <= ST_I08;
                    wait_clear <= 1'b0;
                    state      <= ST_SETUP;
                    timer      <= T_SETUP[20:0];
                end
                ST_I08: begin
                    LCD_EN     <= 1'b0;
                    LCD_RS     <= 1'b0;
                    LCD_DATA   <= 8'h01;
                    ret_state  <= ST_I01;
                    wait_clear <= 1'b1;
                    state      <= ST_SETUP;
                    timer      <= T_SETUP[20:0];
                end
                ST_I01: begin
                    LCD_EN     <= 1'b0;
                    LCD_RS     <= 1'b0;
                    LCD_DATA   <= 8'h06;
                    ret_state  <= ST_I06;
                    wait_clear <= 1'b0;
                    state      <= ST_SETUP;
                    timer      <= T_SETUP[20:0];
                end
                ST_I06: begin
                    LCD_EN     <= 1'b0;
                    LCD_RS     <= 1'b0;
                    LCD_DATA   <= 8'h0C;
                    ret_state  <= ST_I0C;
                    wait_clear <= 1'b0;
                    state      <= ST_SETUP;
                    timer      <= T_SETUP[20:0];
                end
                ST_I0C: begin
                    need_refresh <= 1'b1;
                    state        <= ST_IDLE;
                end
                ST_IDLE: begin
                    LCD_EN <= 1'b0;
                    if (need_refresh) begin
                        need_refresh <= 1'b0;
                        LCD_RS     <= 1'b0;
                        LCD_DATA   <= 8'h01;
                        ret_state  <= ST_CLEAR;
                        wait_clear <= 1'b1;
                        state      <= ST_SETUP;
                        timer      <= T_SETUP[20:0];
                    end
                end
                ST_CLEAR: begin
                    col        <= 5'd0;
                    LCD_EN     <= 1'b0;
                    LCD_RS     <= 1'b1;
                    LCD_DATA   <= line1[0];
                    ret_state  <= ST_L1;
                    wait_clear <= 1'b0;
                    state      <= ST_SETUP;
                    timer      <= T_SETUP[20:0];
                end
                ST_L1: begin
                    LCD_EN <= 1'b0;
                    if (col >= 5'd15) begin
                        LCD_RS     <= 1'b0;
                        LCD_DATA   <= 8'hC0;
                        ret_state  <= ST_DDRAM2;
                        wait_clear <= 1'b0;
                        state      <= ST_SETUP;
                        timer      <= T_SETUP[20:0];
                    end else begin
                        col        <= col + 5'd1;
                        LCD_RS     <= 1'b1;
                        LCD_DATA   <= line1[col + 5'd1];
                        ret_state  <= ST_L1;
                        wait_clear <= 1'b0;
                        state      <= ST_SETUP;
                        timer      <= T_SETUP[20:0];
                    end
                end
                ST_DDRAM2: begin
                    col        <= 5'd0;
                    LCD_EN     <= 1'b0;
                    LCD_RS     <= 1'b1;
                    LCD_DATA   <= line2[0];
                    ret_state  <= ST_L2;
                    wait_clear <= 1'b0;
                    state      <= ST_SETUP;
                    timer      <= T_SETUP[20:0];
                end
                ST_L2: begin
                    LCD_EN <= 1'b0;
                    if (col >= 5'd15)
                        state <= ST_IDLE;
                    else begin
                        col        <= col + 5'd1;
                        LCD_RS     <= 1'b1;
                        LCD_DATA   <= line2[col + 5'd1];
                        ret_state  <= ST_L2;
                        wait_clear <= 1'b0;
                        state      <= ST_SETUP;
                        timer      <= T_SETUP[20:0];
                    end
                end
                ST_SETUP: begin
                    LCD_EN <= 1'b0;
                    if (timer == 0) begin
                        state <= ST_PULSE;
                        timer <= T_EN[20:0];
                    end else
                        timer <= timer - 21'd1;
                end
                ST_PULSE: begin
                    LCD_EN <= 1'b1;
                    if (timer == 0) begin
                        LCD_EN <= 1'b0;
                        state  <= ST_WAIT;
                        if (wait_clear)
                            timer <= T_CLEAR[20:0];
                        else if (ret_state == ST_I30A)
                            timer <= T_INIT1[20:0];
                        else if (ret_state == ST_I30B)
                            timer <= T_INIT2[20:0];
                        else
                            timer <= T_CMD[20:0];
                    end else
                        timer <= timer - 21'd1;
                end
                ST_WAIT: begin
                    if (timer == 0)
                        state <= ret_state;
                    else
                        timer <= timer - 21'd1;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
