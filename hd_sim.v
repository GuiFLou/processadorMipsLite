// hd_sim.v — HD simulado com transferencias de setor entre HD e RAM
//
// O armazenamento e linear internamente, mas a CPU seleciona um setor logico.
// Cada comando transfere SECTOR_SZ palavras pela porta B da data_ram.
//
// Registradores MMIO:
//   cmd    (1020): 1 = HD -> RAM, 3 = RAM -> HD
//   sector (1021): setor logico
//   addr   (1022): endereco-base na RAM
//   status (1023): 0 = idle, 1 = busy, 2 = done, 3 = error

module hd_sim #(
    parameter TRACKS       = 8,
    parameter SPT          = 8,
    parameter SECTOR_SZ    = 256,
    parameter DATA_W       = 32,
    parameter RAM_ADDR_W   = 10,
    parameter RAM_MAX_ADDR = 1015,
    parameter HD_FILE      = "hd_image.txt"
)(
    input  wire                  clk,
    input  wire                  rst,

    input  wire [DATA_W-1:0]     reg_cmd_in,
    input  wire [DATA_W-1:0]     reg_sector_in,
    input  wire [DATA_W-1:0]     reg_addr_in,
    input  wire                  cmd_write,
    input  wire                  sector_write,
    input  wire                  addr_write,

    output wire [DATA_W-1:0]     reg_cmd_out,
    output wire [DATA_W-1:0]     reg_sector_out,
    output wire [DATA_W-1:0]     reg_addr_out,
    output wire [DATA_W-1:0]     reg_status_out,

    output wire [RAM_ADDR_W-1:0] ram_addr_b,
    output wire [DATA_W-1:0]     ram_wdata_b,
    input  wire [DATA_W-1:0]     ram_rdata_b,
    output wire                  ram_we_b
);
    localparam TOTAL_SECTORS = TRACKS * SPT;
    localparam TOTAL_WORDS   = TOTAL_SECTORS * SECTOR_SZ;
    localparam HD_ADDR_W     = (TOTAL_WORDS <= 2) ? 1 : $clog2(TOTAL_WORDS);
    localparam SECTOR_W      = (TOTAL_SECTORS <= 2) ? 1 : $clog2(TOTAL_SECTORS);
    localparam WORD_COUNT_W  = (SECTOR_SZ <= 2) ? 1 : $clog2(SECTOR_SZ);
    localparam MAX_DMA_BASE  = RAM_MAX_ADDR - (SECTOR_SZ - 1);

    localparam [DATA_W-1:0] CMD_HD_TO_RAM = {{(DATA_W-1){1'b0}}, 1'b1};
    localparam [DATA_W-1:0] CMD_RAM_TO_HD = {{(DATA_W-2){1'b0}}, 2'b11};

    localparam [1:0] STATUS_IDLE  = 2'd0;
    localparam [1:0] STATUS_BUSY  = 2'd1;
    localparam [1:0] STATUS_DONE  = 2'd2;
    localparam [1:0] STATUS_ERROR = 2'd3;

    localparam [1:0] STATE_IDLE       = 2'd0;
    localparam [1:0] STATE_HD_TO_RAM  = 2'd1;
    localparam [1:0] STATE_HD_DRAIN   = 2'd2;
    localparam [1:0] STATE_RAM_TO_HD  = 2'd3;

    (* ramstyle = "M9K" *) reg [DATA_W-1:0] storage [0:TOTAL_WORDS-1];

    integer i;
    initial begin
        for (i = 0; i < TOTAL_WORDS; i = i + 1)
            storage[i] = {DATA_W{1'b0}};
        if (HD_FILE != "")
            $readmemb(HD_FILE, storage);
    end

    // Registradores configurados pela CPU.
    reg [DATA_W-1:0] r_cmd;
    reg [DATA_W-1:0] r_sector;
    reg [DATA_W-1:0] r_addr;
    reg [1:0]        r_status;

    // Parametros ativos ficam congelados durante toda a transferencia.
    reg [SECTOR_W-1:0]    active_sector;
    reg [RAM_ADDR_W-1:0]  active_ram_base;
    reg [WORD_COUNT_W-1:0] word_count;
    reg [1:0]              state;

    // A leitura do HD e sincrona para permitir inferencia de block RAM.
    // O estado DRAIN mantem a ultima palavra valida ate a escrita na RAM.
    reg [DATA_W-1:0]     hd_read_data;
    reg [RAM_ADDR_W-1:0] hd_read_ram_addr;
    reg                  hd_read_valid;

    wire command_valid = (reg_cmd_in == CMD_HD_TO_RAM) ||
                         (reg_cmd_in == CMD_RAM_TO_HD);
    wire sector_valid  = (r_sector < TOTAL_SECTORS);
    wire address_valid = (r_addr <= MAX_DMA_BASE);

    wire [HD_ADDR_W-1:0] hd_word_addr =
        (active_sector * SECTOR_SZ) + word_count;
    wire [RAM_ADDR_W-1:0] ram_word_addr =
        active_ram_base + word_count;

    assign reg_cmd_out    = r_cmd;
    assign reg_sector_out = r_sector;
    assign reg_addr_out   = r_addr;
    assign reg_status_out = {{(DATA_W-2){1'b0}}, r_status};

    assign ram_addr_b  = (state == STATE_RAM_TO_HD)
                       ? ram_word_addr
                       : hd_read_ram_addr;
    assign ram_wdata_b = hd_read_data;
    assign ram_we_b    = hd_read_valid;

    always @(posedge clk) begin
        if (rst) begin
            r_cmd          <= {DATA_W{1'b0}};
            r_sector       <= {DATA_W{1'b0}};
            r_addr         <= {DATA_W{1'b0}};
            r_status       <= STATUS_IDLE;
            active_sector  <= {SECTOR_W{1'b0}};
            active_ram_base <= {RAM_ADDR_W{1'b0}};
            word_count     <= {WORD_COUNT_W{1'b0}};
            state           <= STATE_IDLE;
            hd_read_data    <= {DATA_W{1'b0}};
            hd_read_ram_addr <= {RAM_ADDR_W{1'b0}};
            hd_read_valid   <= 1'b0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (sector_write)
                        r_sector <= reg_sector_in;
                    if (addr_write)
                        r_addr <= reg_addr_in;

                    if (cmd_write) begin
                        r_cmd <= reg_cmd_in;
                        if (!command_valid || !sector_valid || !address_valid) begin
                            r_status <= STATUS_ERROR;
                        end else begin
                            active_sector   <= r_sector[SECTOR_W-1:0];
                            active_ram_base <= r_addr[RAM_ADDR_W-1:0];
                            word_count      <= {WORD_COUNT_W{1'b0}};
                            hd_read_valid   <= 1'b0;
                            r_status        <= STATUS_BUSY;
                            state           <= (reg_cmd_in == CMD_HD_TO_RAM)
                                             ? STATE_HD_TO_RAM
                                             : STATE_RAM_TO_HD;
                        end
                    end
                end

                STATE_HD_TO_RAM: begin
                    hd_read_data     <= storage[hd_word_addr];
                    hd_read_ram_addr <= ram_word_addr;
                    hd_read_valid    <= 1'b1;

                    if (word_count == SECTOR_SZ - 1) begin
                        word_count <= {WORD_COUNT_W{1'b0}};
                        state      <= STATE_HD_DRAIN;
                    end else begin
                        word_count <= word_count + 1'b1;
                    end
                end

                STATE_HD_DRAIN: begin
                    // ram_we_b ainda estava ativo nesta borda, gravando a
                    // ultima palavra antes de encerrar a transferencia.
                    hd_read_valid <= 1'b0;
                    state         <= STATE_IDLE;
                    r_status      <= STATUS_DONE;
                end

                STATE_RAM_TO_HD: begin
                    // A leitura da porta B da RAM e combinacional; cada
                    // palavra, inclusive a ultima, e gravada nesta borda.
                    hd_read_valid <= 1'b0;
                    storage[hd_word_addr] <= ram_rdata_b;

                    if (word_count == SECTOR_SZ - 1) begin
                        word_count <= {WORD_COUNT_W{1'b0}};
                        state      <= STATE_IDLE;
                        r_status   <= STATUS_DONE;
                    end else begin
                        word_count <= word_count + 1'b1;
                    end
                end

                default: begin
                    state         <= STATE_IDLE;
                    r_status      <= STATUS_IDLE;
                    hd_read_valid <= 1'b0;
                end
            endcase
            // Estados nao-idle ignoram todas as escritas MMIO.
        end
    end
endmodule
