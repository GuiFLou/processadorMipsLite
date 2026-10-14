`timescale 1ns / 1ps

// Confere a imagem do HD e a cópia de um setor para a folha da vez.

module tb_hd_map;
    reg clk;
    reg rst;
    reg [31:0] cmd_in, sector_in, addr_in;
    reg cmd_w, sector_w, addr_w;

    wire [31:0] cmd_out, sector_out, addr_out, status_out;
    wire [11:0] ram_addr, imem_addr;
    wire [31:0] ram_wdata, ram_rdata, imem_wdata;
    wire ram_we, imem_we;

    hd_sim hd (
        .clk(clk), .rst(rst),
        .reg_cmd_in(cmd_in),
        .reg_sector_in(sector_in),
        .reg_addr_in(addr_in),
        .cmd_write(cmd_w),
        .sector_write(sector_w),
        .addr_write(addr_w),
        .reg_cmd_out(cmd_out),
        .reg_sector_out(sector_out),
        .reg_addr_out(addr_out),
        .reg_status_out(status_out),
        .ram_addr_b(ram_addr),
        .ram_wdata_b(ram_wdata),
        .ram_rdata_b(ram_rdata),
        .ram_we_b(ram_we),
        .imem_addr_b(imem_addr),
        .imem_wdata_b(imem_wdata),
        .imem_we_b(imem_we)
    );

    data_ram ram (
        .clk(clk),
        .addr_a(12'd0), .wdata_a(32'd0), .rdata_a(), .we_a(1'b0),
        .addr_b(ram_addr), .wdata_b(ram_wdata), .rdata_b(ram_rdata), .we_b(ram_we)
    );

    inst_mem_rw #(.FILENAME("gcd.txt")) imem (
        .clk(clk),
        .addr_a(12'd0), .rdata_a(),
        .addr_b(imem_addr), .wdata_b(imem_wdata), .we_b(imem_we)
    );

    integer fails, n;

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
        rst = 1'b1;
        cmd_in = 32'd0;
        sector_in = 32'd0;
        addr_in = 32'd0;
        cmd_w = 1'b0;
        sector_w = 1'b0;
        addr_w = 1'b0;

        repeat (2) @(posedge clk);
        rst = 1'b0;
        step();

        if (hd.storage[0] !== 32'd20261013) begin
            $display("FAIL assinatura %0d", hd.storage[0]);
            fails = fails + 1;
        end else
            $display("PASS assinatura");

        if (hd.storage[3327] !== 32'b01000100000000000000101111111111) begin
            $display("FAIL guarda %b", hd.storage[3327]);
            fails = fails + 1;
        end else
            $display("PASS salto de guarda");

        sector_in = 32'd0;
        sector_w = 1'b1;
        step();
        sector_w = 1'b0;
        addr_in = 32'd3833;
        addr_w = 1'b1;
        step();
        addr_w = 1'b0;
        cmd_in = 32'd1;
        cmd_w = 1'b1;
        step();
        cmd_w = 1'b0;
        if (status_out !== 32'd3) begin
            $display("FAIL base 3833 status %0d", status_out);
            fails = fails + 1;
        end else
            $display("PASS base 3833 recusada");

        sector_in = 32'd20;
        sector_w = 1'b1;
        step();
        sector_w = 1'b0;
        addr_in = 32'd3072;
        addr_w = 1'b1;
        step();
        addr_w = 1'b0;
        cmd_in = 32'd2;
        cmd_w = 1'b1;
        step();
        cmd_w = 1'b0;
        for (n = 0; n < 400 && status_out !== 32'd2; n = n + 1)
            step();
        if (status_out !== 32'd2) begin
            $display("FAIL dma status %0d apos %0d", status_out, n);
            fails = fails + 1;
        end else if (imem.mem[3072] !== hd.storage[5120]) begin
            $display("FAIL imem[3072] %h hd %h", imem.mem[3072], hd.storage[5120]);
            fails = fails + 1;
        end else
            $display("PASS setor 20 na folha 3072");

        if (fails == 0)
            $display("PASS tb_hd_map");
        else
            $display("FAIL tb_hd_map (%0d)", fails);
        $finish;
    end
endmodule
