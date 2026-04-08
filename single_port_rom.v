module single_port_rom #(
    parameter ADDR_W  = 10,                // 1024 palavras de 32 bits
    parameter DATA_W  = 32,
    parameter FILENAME = "gcd.txt"         // arquivo binário (mem‑init)
)(
    input  wire               clk,
    input  wire [ADDR_W-1:0]  addr,
    output wire [DATA_W-1:0]  data
);
    reg [DATA_W-1:0] rom [0:(1<<ADDR_W)-1];
    initial begin
        $readmemb(FILENAME, rom);          // carrega programa
    end
    assign data = rom[addr];
endmodule