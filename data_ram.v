module data_ram #(
    parameter DATA_W = 32,
    parameter ADDR_W = 10              // 1024 palavras
)(
    input  wire                 clk,
    // porta A – CPU
    input  wire [ADDR_W-1:0]    addr_a,
    input  wire [DATA_W-1:0]    wdata_a,
    output wire [DATA_W-1:0]    rdata_a,
    input  wire                 we_a,
    // porta B – escrita assíncrona (ex.: switches)
    input  wire [ADDR_W-1:0]    addr_b,
    input  wire [DATA_W-1:0]    wdata_b,
    input  wire                 we_b
);
    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];
    integer i;

    initial begin
        for (i = 0; i < (1<<ADDR_W); i = i + 1)
            mem[i] = {DATA_W{1'b0}};
    end

    always @(posedge clk) begin
        if (we_a) mem[addr_a] <= wdata_a;
        if (we_b) mem[addr_b] <= wdata_b;
    end

    assign rdata_a = mem[addr_a];
endmodule
