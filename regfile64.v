module regfile64 #(
    parameter DATA_W = 32,
    parameter ADDR_W = 6               // 64 registradores
)(
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 we,     // write‑enable
    input  wire [ADDR_W-1:0]    rs1,    // endereço fonte A
    input  wire [ADDR_W-1:0]    rs2,    // endereço fonte B
    input  wire [ADDR_W-1:0]    rd,     // endereço destino
    input  wire [DATA_W-1:0]    wd,     // write‑data
    output wire [DATA_W-1:0]    rd1,    // read‑data A
    output wire [DATA_W-1:0]    rd2     // read‑data B
);
    reg [DATA_W-1:0] rf [0:(1<<ADDR_W)-1];
    integer i;

    // reset sincrono – zera todos os registradores
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < (1<<ADDR_W); i = i + 1) rf[i] <= {DATA_W{1'b0}};
        end else if (we && rd != 0) begin       // $0 permanece zero
            rf[rd] <= wd;
        end
    end

    assign rd1 = (rs1 == 0) ? {DATA_W{1'b0}} : rf[rs1];
    assign rd2 = (rs2 == 0) ? {DATA_W{1'b0}} : rf[rs2];
endmodule