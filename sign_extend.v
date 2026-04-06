module sign_extend #(
    parameter IN_W = 16                 // largura da entrada a estender
)(
    input  wire [IN_W-1:0] in,
    output wire [31:0]     out
);
    assign out = {{(32-IN_W){in[IN_W-1]}}, in};
endmodule