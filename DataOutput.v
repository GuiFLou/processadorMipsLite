module DataOutput
(
    input  wire        clk,
    input  wire [31:0] value,
    output wire [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6
);
    reg [31:0] v_reg /* synthesis preserve */;

    always @(posedge clk)
        v_reg <= value;     // sem EnableOut

    hex7seg h0 (.hex(v_reg[ 3: 0]), .seg(HEX0));
    hex7seg h1 (.hex(v_reg[ 7: 4]), .seg(HEX1));
    hex7seg h2 (.hex(v_reg[11: 8]), .seg(HEX2));
    hex7seg h3 (.hex(v_reg[15:12]), .seg(HEX3));
    hex7seg h4 (.hex(v_reg[19:16]), .seg(HEX4));
    hex7seg h5 (.hex(v_reg[23:20]), .seg(HEX5));
    hex7seg h6 (.hex(v_reg[27:24]), .seg(HEX6));
endmodule
