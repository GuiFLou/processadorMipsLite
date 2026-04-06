module Debounce
#( parameter STABLE_CNT = 1_000_000 )  // ~10 ms @ 50 MHz
(
    input  wire clk, btn_in,
    output reg  btn_out = 1'b0
);
    reg [19:0] cnt = 20'd0, sync_0 = 1'b0, sync_1 = 1'b0;

    always @(posedge clk) begin
        sync_0 <= btn_in;
        sync_1 <= sync_0;           // dupla sincronia

        if (btn_out != sync_1) begin
            if (cnt == STABLE_CNT) begin
                btn_out <= sync_1;
                cnt     <= 20'd0;
            end else
                cnt <= cnt + 1'd1;
        end else
            cnt <= 20'd0;
    end
endmodule