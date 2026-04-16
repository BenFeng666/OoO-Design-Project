module CDB_buffer (
    input wire clk,
    input wire rst,

    input wire [31:0] ALU0_result,
    input wire [2:0]  ALU0_tag,
    input wire        ALU0_valid,
    input wire        ALU0_branch_taken,
    input wire [31:0] ALU0_target,
    input wire [31:0] ALU0_store_data,

    input wire [31:0] ALU1_result,
    input wire [2:0]  ALU1_tag,
    input wire        ALU1_valid,
    input wire        ALU1_branch_taken,
    input wire [31:0] ALU1_target,
    input wire [31:0] ALU1_store_data,

    output reg [31:0] cdb_value,
    output reg [2:0]  cdb_tag,
    output reg        cdb_valid,
    output reg        cdb_branch_taken,
    output reg [31:0] cdb_target,
    output reg [31:0] cdb_store_data
);

reg [31:0] pending_value;
reg [2:0]  pending_tag;
reg        pending_valid;
reg        pending_branch_taken;
reg [31:0] pending_target;
reg [31:0] pending_store_data;

reg prefer_alu1;   // 0 => ALU0 wins ties, 1 => ALU1 wins ties

// -----------------------------
// Current cycle CDB output
// -----------------------------
always @(*) begin
    cdb_value        = 32'b0;
    cdb_tag          = 3'b0;
    cdb_valid        = 1'b0;
    cdb_branch_taken = 1'b0;
    cdb_target       = 32'b0;
    cdb_store_data   = 32'b0;

    // pending entry always has priority on the bus
    if (pending_valid) begin
        cdb_value        = pending_value;
        cdb_tag          = pending_tag;
        cdb_valid        = 1'b1;
        cdb_branch_taken = pending_branch_taken;
        cdb_target       = pending_target;
        cdb_store_data   = pending_store_data;
    end
    else begin
        if (!prefer_alu1) begin
            if (ALU0_valid) begin
                cdb_value        = ALU0_result;
                cdb_tag          = ALU0_tag;
                cdb_valid        = 1'b1;
                cdb_branch_taken = ALU0_branch_taken;
                cdb_target       = ALU0_target;
                cdb_store_data   = ALU0_store_data;
            end
            else if (ALU1_valid) begin
                cdb_value        = ALU1_result;
                cdb_tag          = ALU1_tag;
                cdb_valid        = 1'b1;
                cdb_branch_taken = ALU1_branch_taken;
                cdb_target       = ALU1_target;
                cdb_store_data   = ALU1_store_data;
            end
        end
        else begin
            if (ALU1_valid) begin
                cdb_value        = ALU1_result;
                cdb_tag          = ALU1_tag;
                cdb_valid        = 1'b1;
                cdb_branch_taken = ALU1_branch_taken;
                cdb_target       = ALU1_target;
                cdb_store_data   = ALU1_store_data;
            end
            else if (ALU0_valid) begin
                cdb_value        = ALU0_result;
                cdb_tag          = ALU0_tag;
                cdb_valid        = 1'b1;
                cdb_branch_taken = ALU0_branch_taken;
                cdb_target       = ALU0_target;
                cdb_store_data   = ALU0_store_data;
            end
        end
    end
end

// -----------------------------
// Pending-entry update
// -----------------------------
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        pending_value        <= 32'b0;
        pending_tag          <= 3'b0;
        pending_valid        <= 1'b0;
        pending_branch_taken <= 1'b0;
        pending_target       <= 32'b0;
        pending_store_data   <= 32'b0;
        prefer_alu1          <= 1'b0;
    end
    else begin
        // default: no pending for next cycle unless we save one below
        pending_valid <= 1'b0;

        // Case 1:
        // bus is used this cycle by the old pending entry
        // if a NEW ALU result also arrives now, save it for next cycle
        if (pending_valid) begin
            if (ALU0_valid && !ALU1_valid) begin
                pending_value        <= ALU0_result;
                pending_tag          <= ALU0_tag;
                pending_valid        <= 1'b1;
                pending_branch_taken <= ALU0_branch_taken;
                pending_target       <= ALU0_target;
                pending_store_data   <= ALU0_store_data;
            end
            else if (!ALU0_valid && ALU1_valid) begin
                pending_value        <= ALU1_result;
                pending_tag          <= ALU1_tag;
                pending_valid        <= 1'b1;
                pending_branch_taken <= ALU1_branch_taken;
                pending_target       <= ALU1_target;
                pending_store_data   <= ALU1_store_data;
            end
            else if (ALU0_valid && ALU1_valid) begin
                // one-entry buffer can only save one
                // save one according to round-robin preference
                if (!prefer_alu1) begin
                    pending_value        <= ALU0_result;
                    pending_tag          <= ALU0_tag;
                    pending_valid        <= 1'b1;
                    pending_branch_taken <= ALU0_branch_taken;
                    pending_target       <= ALU0_target;
                    pending_store_data   <= ALU0_store_data;
                    prefer_alu1          <= 1'b1;
                end
                else begin
                    pending_value        <= ALU1_result;
                    pending_tag          <= ALU1_tag;
                    pending_valid        <= 1'b1;
                    pending_branch_taken <= ALU1_branch_taken;
                    pending_target       <= ALU1_target;
                    pending_store_data   <= ALU1_store_data;
                    prefer_alu1          <= 1'b0;
                end
            end
        end

        // Case 2:
        // no old pending entry, but both ALUs finished together
        // one goes on CDB now, the loser is saved
        else begin
            if (ALU0_valid && ALU1_valid) begin
                if (!prefer_alu1) begin
                    // ALU0 wins current cycle, ALU1 saved
                    pending_value        <= ALU1_result;
                    pending_tag          <= ALU1_tag;
                    pending_valid        <= 1'b1;
                    pending_branch_taken <= ALU1_branch_taken;
                    pending_target       <= ALU1_target;
                    pending_store_data   <= ALU1_store_data;
                    prefer_alu1          <= 1'b1;
                end
                else begin
                    // ALU1 wins current cycle, ALU0 saved
                    pending_value        <= ALU0_result;
                    pending_tag          <= ALU0_tag;
                    pending_valid        <= 1'b1;
                    pending_branch_taken <= ALU0_branch_taken;
                    pending_target       <= ALU0_target;
                    pending_store_data   <= ALU0_store_data;
                    prefer_alu1          <= 1'b0;
                end
            end
            else if (ALU0_valid) begin
                prefer_alu1 <= 1'b1;
            end
            else if (ALU1_valid) begin
                prefer_alu1 <= 1'b0;
            end
        end
    end
end

endmodule
