module CDB_buffer (
    input wire clk,
    input wire rst,
    input wire [31:0] ALU0_result,
    input wire [31:0] ALU1_result,
    input wire ALU0_valid,
    input wire ALU1_valid,
    output reg [31:0] cdb_value
);

reg [31:0] store_buffer [7:0];
integer i;
integer k;          // next free slot
integer last_idx;   // most recently stored entry
reg switch;         // 0 = prefer ALU0, 1 = prefer ALU1
reg first;          // first accepted result decides initial switch

always @(*) begin
    if (k == 0) begin
        cdb_value = 32'b0;
    end
    else begin
        cdb_value = store_buffer[last_idx];
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        switch   <= 1'b0;
        first    <= 1'b1;
        k        <= 0;
        last_idx <= 0;

        for (i = 0; i < 8; i = i + 1) begin
            store_buffer[i] <= 32'b0;
        end
    end
    else begin
        // first accepted result decides switch
        if (first) begin
            if (ALU0_valid && !ALU1_valid && k < 8) begin
                store_buffer[k] <= ALU0_result;
                last_idx <= k;
                k <= k + 1;
                first <= 1'b0;
                switch <= 1'b1;   // next prefer ALU1
            end
            else if (ALU1_valid && !ALU0_valid && k < 8) begin
                store_buffer[k] <= ALU1_result;
                last_idx <= k;
                k <= k + 1;
                first <= 1'b0;
                switch <= 1'b0;   // next prefer ALU0
            end
            else if (ALU0_valid && ALU1_valid && (k < 8)) begin
                // if both arrive first cycle, choose ALU0 first
                store_buffer[k] <= ALU0_result;
                last_idx <= k;
                k <= k + 1;
                first <= 1'b0;
                switch <= 1'b1;   // next prefer ALU1
            end
        end
        else begin
            if (k < 8) begin
                if (!switch) begin
                    // prefer ALU0
                    if (ALU0_valid) begin
                        store_buffer[k] <= ALU0_result;
                        last_idx <= k;
                        k <= k + 1;
                        switch <= 1'b1;
                    end
                    else if (ALU1_valid) begin
                        store_buffer[k] <= ALU1_result;
                        last_idx <= k;
                        k <= k + 1;
                        switch <= 1'b0;
                    end
                end
                else begin
                    // prefer ALU1
                    if (ALU1_valid) begin
                        store_buffer[k] <= ALU1_result;
                        last_idx <= k;
                        k <= k + 1;
                        switch <= 1'b0;
                    end
                    else if (ALU0_valid) begin
                        store_buffer[k] <= ALU0_result;
                        last_idx <= k;
                        k <= k + 1;
                        switch <= 1'b1;
                    end
                end
            end
        end
    end
end

endmodule
