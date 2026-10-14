// inst_mem_rw.v — memoria de instrucoes gravavel
//
// Porta A: fetch combinacional (mesmo timing da ROM original).
// Porta B: escrita sincrona do DMA do HD (setor -> IMEM).

module inst_mem_rw #(
    parameter ADDR_W   = 12,
    parameter DATA_W   = 32,
    parameter FILENAME = "so.txt"
)(
    input  wire               clk,
    input  wire [ADDR_W-1:0]  addr_a,
    output wire [DATA_W-1:0]  rdata_a,
    input  wire [ADDR_W-1:0]  addr_b,
    input  wire [DATA_W-1:0]  wdata_b,
    input  wire               we_b
);
    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];
    integer i;

    initial begin
        for (i = 0; i < (1<<ADDR_W); i = i + 1)
            mem[i] = {DATA_W{1'b0}};
        $readmemb(FILENAME, mem);
    end

    assign rdata_a = mem[addr_a];

    always @(posedge clk) begin
        if (we_b)
            mem[addr_b] <= wdata_b;
    end
endmodule
