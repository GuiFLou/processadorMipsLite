module DataOutput
(
    input  wire        clk,
    input  wire [31:0] value,
    output wire [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6
);
    reg [31:0] v_reg /* synthesis preserve */;

    always @(posedge clk)
        v_reg <= value;     // sem EnableOut

    Hex7Seg h0 (.nibble(v_reg[ 3: 0]), .seg(HEX0));
    Hex7Seg h1 (.nibble(v_reg[ 7: 4]), .seg(HEX1));
    Hex7Seg h2 (.nibble(v_reg[11: 8]), .seg(HEX2));
    Hex7Seg h3 (.nibble(v_reg[15:12]), .seg(HEX3));
    Hex7Seg h4 (.nibble(v_reg[19:16]), .seg(HEX4));
    Hex7Seg h5 (.nibble(v_reg[23:20]), .seg(HEX5));
    Hex7Seg h6 (.nibble(v_reg[27:24]), .seg(HEX6));
endmodule
