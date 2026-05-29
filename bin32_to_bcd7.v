module bin32_to_bcd7 (
    input  wire [31:0] bin,
    output reg  [27:0] bcd
);
    integer i;
    reg [59:0] shift;

    always @* begin
        shift = 60'd0;
        shift[31:0] = bin;

        for (i = 0; i < 32; i = i + 1) begin
            if (shift[35:32] >= 4'd5) shift[35:32] = shift[35:32] + 4'd3;
            if (shift[39:36] >= 4'd5) shift[39:36] = shift[39:36] + 4'd3;
            if (shift[43:40] >= 4'd5) shift[43:40] = shift[43:40] + 4'd3;
            if (shift[47:44] >= 4'd5) shift[47:44] = shift[47:44] + 4'd3;
            if (shift[51:48] >= 4'd5) shift[51:48] = shift[51:48] + 4'd3;
            if (shift[55:52] >= 4'd5) shift[55:52] = shift[55:52] + 4'd3;
            if (shift[59:56] >= 4'd5) shift[59:56] = shift[59:56] + 4'd3;
            shift = shift << 1;
        end

        bcd = shift[59:32];
    end
endmodule
