module data_ram #(
    parameter DATA_W = 32,
    parameter ADDR_W = 12              // 4096 palavras
)(
    input  wire                 clk,
    // porta A – CPU
    input  wire [ADDR_W-1:0]    addr_a,
    input  wire [DATA_W-1:0]    wdata_a,
    output reg  [DATA_W-1:0]    rdata_a,
    input  wire                 we_a,
    // porta B – DMA do HD (leitura e escrita)
    input  wire [ADDR_W-1:0]    addr_b,
    input  wire [DATA_W-1:0]    wdata_b,
    output reg  [DATA_W-1:0]    rdata_b,
    input  wire                 we_b
);
    // Leituras sincronas e processos separados seguem o template de RAM
    // true dual-port dos M9K. Colisoes de escrita sao proibidas pelo sistema:
    // durante o DMA, hd_freeze desabilita a porta A da CPU.
    (* ramstyle = "M9K" *) reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];
    integer i;

    initial begin
        for (i = 0; i < (1<<ADDR_W); i = i + 1)
            mem[i] = {DATA_W{1'b0}};
    end

    always @(posedge clk) begin
        if (we_a)
            mem[addr_a] <= wdata_a;
        rdata_a <= mem[addr_a];
    end

    always @(posedge clk) begin
        if (we_b)
            mem[addr_b] <= wdata_b;
        rdata_b <= mem[addr_b];
    end

    // synthesis translate_off
    always @(posedge clk) begin
        if (we_a && we_b && (addr_a == addr_b))
            $display("ERROR data_ram: colisao de escrita A/B no endereco %0d", addr_a);
    end
    // synthesis translate_on
endmodule
