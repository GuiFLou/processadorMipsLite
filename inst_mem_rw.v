// inst_mem_rw.v — memoria de instrucoes gravavel
//
// Porta A: fetch combinacional (mesmo timing da ROM original).
// Porta B: escrita sincrona do DMA do HD (setor -> IMEM).

module inst_mem_rw #(
    parameter ADDR_W   = 10,
    parameter DATA_W   = 32,
    parameter FILENAME = "gcd.txt"
)(
    input  wire               clk,
    input  wire [ADDR_W-1:0]  addr_a,
    output wire [DATA_W-1:0]  rdata_a,
    input  wire [ADDR_W-1:0]  addr_b,
    input  wire [DATA_W-1:0]  wdata_b,
    input  wire               we_b
);
    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

    initial begin
        $readmemb(FILENAME, mem);
    end

    assign rdata_a = mem[addr_a];

    always @(posedge clk) begin
        if (we_b)
            mem[addr_b] <= wdata_b;
    end
endmodule
