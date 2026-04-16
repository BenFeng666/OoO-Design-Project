module CDB_buffer (
    input wire clk,
    input wire rst,

    input wire [31:0] ALU0_result,
    input wire [2:0]  ALU0_tag,
    input wire        ALU0_valid,

    input wire [31:0] ALU1_result,
    input wire [2:0]  ALU1_tag,
    input wire        ALU1_valid,

    output reg [31:0] cdb_value,
    output reg [2:0]  cdb_tag,
    output reg        cdb_valid
);

reg [31:0] pending_value;
reg [2:0]  pending_tag;
reg        pending_valid;

reg switch;   // 0 = prefer ALU0 first, 1 = prefer ALU1 first

always @(*) begin
    cdb_value = 32'b0;
    cdb_tag   = 3'b0;
    cdb_valid = 1'b0;

    // pending result has highest priority
    if (pending_valid) begin
        cdb_value = pending_value;
        cdb_tag   = pending_tag;
        cdb_valid = 1'b1;
    end
    else begin
        if (!switch) begin
            // prefer ALU0
            if (ALU0_valid) begin
                cdb_value = ALU0_result;
                cdb_tag   = ALU0_tag;
                cdb_valid = 1'b1;
            end
            else if (ALU1_valid) begin
                cdb_value = ALU1_result;
                cdb_tag   = ALU1_tag;
                cdb_valid = 1'b1;
            end
        end
        else begin
            // prefer ALU1
            if (ALU1_valid) begin
                cdb_value = ALU1_result;
                cdb_tag   = ALU1_tag;
                cdb_valid = 1'b1;
            end
            else if (ALU0_valid) begin
                cdb_value = ALU0_result;
                cdb_tag   = ALU0_tag;
                cdb_valid = 1'b1;
            end
        end
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        pending_value <= 32'b0;
        pending_tag   <= 3'b0;
        pending_valid <= 1'b0;
        switch        <= 1'b0;
    end
    else begin
        // default: if a pending entry was broadcast this cycle, clear it
        if (pending_valid) begin
            pending_valid <= 1'b0;
        end
        else begin
            // no pending entry, so maybe need to save the losing ALU result
            if (!switch) begin
                // ALU0 has priority, ALU1 may need buffering
                if (ALU0_valid && ALU1_valid) begin
                    pending_value <= ALU1_result;
                    pending_tag   <= ALU1_tag;
                    pending_valid <= 1'b1;
                    switch        <= 1'b1;
                end
                else if (ALU0_valid) begin
                    switch <= 1'b1;
                end
                else if (ALU1_valid) begin
                    switch <= 1'b0;
                end
            end
            else begin
                // ALU1 has priority, ALU0 may need buffering
                if (ALU0_valid && ALU1_valid) begin
                    pending_value <= ALU0_result;
                    pending_tag   <= ALU0_tag;
                    pending_valid <= 1'b1;
                    switch        <= 1'b0;
                end
                else if (ALU1_valid) begin
                    switch <= 1'b0;
                end
                else if (ALU0_valid) begin
                    switch <= 1'b1;
                end
            end
        end
    end
end

endmodule
