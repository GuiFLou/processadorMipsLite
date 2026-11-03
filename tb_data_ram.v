`timescale 1ns / 1ps

// Confere a latencia de um ciclo e as duas portas da DRAM sincrona.
module tb_data_ram;
    reg clk;
    reg [3:0] addr_a, addr_b;
    reg [31:0] wdata_a, wdata_b;
    reg we_a, we_b;
    wire [31:0] rdata_a, rdata_b;
    integer fails;

    data_ram #(.ADDR_W(4)) dut (
        .clk(clk),
        .addr_a(addr_a), .wdata_a(wdata_a),
        .rdata_a(rdata_a), .we_a(we_a),
        .addr_b(addr_b), .wdata_b(wdata_b),
        .rdata_b(rdata_b), .we_b(we_b)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task step;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        fails = 0;
        addr_a = 4'd0;
        addr_b = 4'd0;
        wdata_a = 32'd0;
        wdata_b = 32'd0;
        we_a = 1'b0;
        we_b = 1'b0;

        step();
        if (rdata_a !== 32'd0 || rdata_b !== 32'd0) begin
            $display("FAIL inicializacao A=%h B=%h", rdata_a, rdata_b);
            fails = fails + 1;
        end

        // Escreve em enderecos diferentes pelas duas portas.
        addr_a = 4'd3;
        wdata_a = 32'h11223344;
        we_a = 1'b1;
        addr_b = 4'd12;
        wdata_b = 32'hAABBCCDD;
        we_b = 1'b1;
        step();
        we_a = 1'b0;
        we_b = 1'b0;

        // A leitura e sincrona: os enderecos sao capturados nesta borda.
        addr_a = 4'd3;
        addr_b = 4'd12;
        step();
        if (rdata_a !== 32'h11223344 || rdata_b !== 32'hAABBCCDD) begin
            $display("FAIL leitura sincrona A=%h B=%h", rdata_a, rdata_b);
            fails = fails + 1;
        end else
            $display("PASS leitura sincrona nas duas portas");

        // Cruza as portas para confirmar que ambas enxergam a mesma memoria.
        addr_a = 4'd12;
        addr_b = 4'd3;
        step();
        if (rdata_a !== 32'hAABBCCDD || rdata_b !== 32'h11223344) begin
            $display("FAIL leitura cruzada A=%h B=%h", rdata_a, rdata_b);
            fails = fails + 1;
        end else
            $display("PASS memoria compartilhada entre portas");

        if (fails == 0)
            $display("PASS tb_data_ram");
        else
            $display("FAIL tb_data_ram (%0d)", fails);
        $finish;
    end
endmodule
