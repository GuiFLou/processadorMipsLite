module mux2 #(
    parameter W = 32
)(
    input  wire [W-1:0] a,
    input  wire [W-1:0] b,
    input  wire         sel,
    output wire [W-1:0] y
);
    assign y = sel ? b : a;
endmodule