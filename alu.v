// alu.v – cobre todas as operações do ISA caseiro
module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  op,
    output reg  [31:0] y,
    output wire        zero
);
    always @* begin
        case (op)
            4'h0: y = a + b;                                // ADD
            4'h1: y = a - b;                                // SUB
            4'h2: y = a & b;                                // AND
            4'h3: y = a | b;                                // OR
            4'h4: y = ~a;                                   // NOT (unário – usa A)
            4'h5: y = b << a[4:0];                          // SLL – shamt em A
            4'h6: y = b >> a[4:0];                          // SRL
            4'h7: y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0; // SLT
            4'h8: y = a * b;                                // MUL (produto low‑32)
            4'h9: y = (b == 0) ? 32'hFFFF_FFFF : a / b;     // DIV (quociente; defensiva)
            4'hA: y = a;                                    // PASS – MOVE
            default: y = 32'hDEAD_BEEF;
        endcase
    end
    assign zero = (y == 32'd0);
endmodule
