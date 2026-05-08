// alu.v – cobre todas as operações do ISA caseiro
module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  op,
    input  wire [7:0]  shamt,
    output reg  [31:0] y,
    output reg  [31:0] hi_out,
    output reg  [31:0] lo_out,
    output wire        zero
);
    reg signed [63:0] mult_result;

    always @* begin
        mult_result = 64'sd0;
        hi_out = 32'd0;
        lo_out = 32'd0;

        case (op)
            4'h0: y = a + b;                                // ADD
            4'h1: y = a - b;                                // SUB
            4'h2: y = a & b;                                // AND
            4'h3: y = a | b;                                // OR
            4'h4: y = ~a;                                   // NOT (unário – usa A)
            4'h5: y = a << shamt[4:0];                      // SL
            4'h6: y = a >> shamt[4:0];                      // SR
            4'h7: y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0; // SLT
            4'h8: begin                                      // MULT
                mult_result = $signed({{32{a[31]}}, a}) * $signed({{32{b[31]}}, b});
                hi_out = mult_result[63:32];
                lo_out = mult_result[31:0];
                y = lo_out;
            end
            4'h9: begin                                      // DIV
                if (b == 0) begin
                    hi_out = a;
                    lo_out = 32'hFFFF_FFFF;
                end else begin
                    hi_out = $signed(a) % $signed(b);
                    lo_out = $signed(a) / $signed(b);
                end
                y = lo_out;
            end
            4'hA: y = a;                                    // PASS – MOVE
            default: y = 32'hDEAD_BEEF;
        endcase
    end
    assign zero = (y == 32'd0);
endmodule
