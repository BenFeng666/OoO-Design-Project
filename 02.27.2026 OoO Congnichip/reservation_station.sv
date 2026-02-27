// Reservation Station for RV32I Out-of-Order CPU Core
// 8-entry reservation station for ALU instructions
// Handles operand tracking, wakeup logic, and instruction issue

module reservation_station #(
    parameter RS_ENTRIES = 8,      // Number of reservation station entries
    parameter ROB_ENTRIES = 16,    // Number of ROB entries (for tag width)
    parameter RS_ADDR_WIDTH = 3,   // log2(RS_ENTRIES)
    parameter ROB_ADDR_WIDTH = 4   // log2(ROB_ENTRIES)
)(
    input  logic                        clock,
    input  logic                        reset,
    
    // Dispatch interface - new instruction allocation
    input  logic                        dispatch_valid,      // New instruction valid
    input  logic [3:0]                  dispatch_alu_op,     // ALU operation
    input  logic [31:0]                 dispatch_src1_value, // Source 1 value (if ready)
    input  logic                        dispatch_src1_ready, // Source 1 is ready
    input  logic [ROB_ADDR_WIDTH-1:0]   dispatch_src1_tag,   // Source 1 ROB tag (if not ready)
    input  logic [31:0]                 dispatch_src2_value, // Source 2 value (if ready)
    input  logic                        dispatch_src2_ready, // Source 2 is ready
    input  logic [ROB_ADDR_WIDTH-1:0]   dispatch_src2_tag,   // Source 2 ROB tag (if not ready)
    input  logic [ROB_ADDR_WIDTH-1:0]   dispatch_dest_tag,   // Destination ROB tag
    output logic                        rs_full,             // RS is full, cannot accept
    
    // Broadcast interface - result forwarding/wakeup
    input  logic                        cdb_valid,           // Common Data Bus valid
    input  logic [ROB_ADDR_WIDTH-1:0]   cdb_tag,             // CDB result tag
    input  logic [31:0]                 cdb_data,            // CDB result data
    
    // Issue interface - send instruction to execution
    output logic                        issue_valid,         // Instruction issued
    output logic [3:0]                  issue_alu_op,        // ALU operation
    output logic [31:0]                 issue_src1_value,    // Source 1 value
    output logic [31:0]                 issue_src2_value,    // Source 2 value
    output logic [ROB_ADDR_WIDTH-1:0]   issue_dest_tag,      // Destination ROB tag
    input  logic                        issue_ready          // Execution unit ready
);

    // Reservation station entry structure
    typedef struct packed {
        logic                       valid;          // Entry is occupied
        logic [3:0]                 alu_op;         // ALU operation
        logic [31:0]                src1_value;     // Source 1 value
        logic                       src1_ready;     // Source 1 is ready
        logic [ROB_ADDR_WIDTH-1:0]  src1_tag;       // Source 1 tag (if waiting)
        logic [31:0]                src2_value;     // Source 2 value
        logic                       src2_ready;     // Source 2 is ready
        logic [ROB_ADDR_WIDTH-1:0]  src2_tag;       // Source 2 tag (if waiting)
        logic [ROB_ADDR_WIDTH-1:0]  dest_tag;       // Destination ROB tag
    } rs_entry_t;
    
    // Reservation station array
    rs_entry_t [RS_ENTRIES-1:0] rs_entries;
    
    // Ready status for each entry
    logic [RS_ENTRIES-1:0] entry_ready;
    
    // Find first free entry for allocation
    logic [RS_ADDR_WIDTH-1:0] free_entry_idx;
    logic                      has_free_entry;
    
    // Find ready entry for issue
    logic [RS_ADDR_WIDTH-1:0] ready_entry_idx;
    logic                      has_ready_entry;
    
    // Check if RS is full
    assign rs_full = !has_free_entry;
    
    // Determine ready entries (both operands ready)
    always_comb begin
        for (int i = 0; i < RS_ENTRIES; i++) begin
            entry_ready[i] = rs_entries[i].valid && 
                            rs_entries[i].src1_ready && 
                            rs_entries[i].src2_ready;
        end
    end
    
    // Find first free entry (priority encoder)
    always_comb begin
        has_free_entry = 1'b0;
        free_entry_idx = '0;
        
        for (int i = 0; i < RS_ENTRIES; i++) begin
            if (!rs_entries[i].valid && !has_free_entry) begin
                has_free_entry = 1'b1;
                free_entry_idx = i[RS_ADDR_WIDTH-1:0];
            end
        end
    end
    
    // Find first ready entry for issue (priority encoder)
    always_comb begin
        has_ready_entry = 1'b0;
        ready_entry_idx = '0;
        
        for (int i = 0; i < RS_ENTRIES; i++) begin
            if (entry_ready[i] && !has_ready_entry) begin
                has_ready_entry = 1'b1;
                ready_entry_idx = i[RS_ADDR_WIDTH-1:0];
            end
        end
    end
    
    // Issue logic - send ready instruction to execution
    assign issue_valid     = has_ready_entry && issue_ready;
    assign issue_alu_op    = rs_entries[ready_entry_idx].alu_op;
    assign issue_src1_value = rs_entries[ready_entry_idx].src1_value;
    assign issue_src2_value = rs_entries[ready_entry_idx].src2_value;
    assign issue_dest_tag  = rs_entries[ready_entry_idx].dest_tag;
    
    // Sequential logic - RS entry management
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            // Clear all entries on reset
            for (int i = 0; i < RS_ENTRIES; i++) begin
                rs_entries[i].valid <= 1'b0;
                rs_entries[i].alu_op <= 4'b0;
                rs_entries[i].src1_value <= 32'b0;
                rs_entries[i].src1_ready <= 1'b0;
                rs_entries[i].src1_tag <= '0;
                rs_entries[i].src2_value <= 32'b0;
                rs_entries[i].src2_ready <= 1'b0;
                rs_entries[i].src2_tag <= '0;
                rs_entries[i].dest_tag <= '0;
            end
        end else begin
            // Wakeup logic - monitor CDB and capture results
            if (cdb_valid) begin
                for (int i = 0; i < RS_ENTRIES; i++) begin
                    if (rs_entries[i].valid) begin
                        // Check source 1
                        if (!rs_entries[i].src1_ready && rs_entries[i].src1_tag == cdb_tag) begin
                            rs_entries[i].src1_value <= cdb_data;
                            rs_entries[i].src1_ready <= 1'b1;
                        end
                        // Check source 2
                        if (!rs_entries[i].src2_ready && rs_entries[i].src2_tag == cdb_tag) begin
                            rs_entries[i].src2_value <= cdb_data;
                            rs_entries[i].src2_ready <= 1'b1;
                        end
                    end
                end
            end
            
            // Issue logic - clear issued entry
            if (issue_valid && issue_ready) begin
                rs_entries[ready_entry_idx].valid <= 1'b0;
            end
            
            // Allocation logic - allocate new instruction
            if (dispatch_valid && has_free_entry) begin
                rs_entries[free_entry_idx].valid      <= 1'b1;
                rs_entries[free_entry_idx].alu_op     <= dispatch_alu_op;
                rs_entries[free_entry_idx].src1_value <= dispatch_src1_value;
                rs_entries[free_entry_idx].src1_ready <= dispatch_src1_ready;
                rs_entries[free_entry_idx].src1_tag   <= dispatch_src1_tag;
                rs_entries[free_entry_idx].src2_value <= dispatch_src2_value;
                rs_entries[free_entry_idx].src2_ready <= dispatch_src2_ready;
                rs_entries[free_entry_idx].src2_tag   <= dispatch_src2_tag;
                rs_entries[free_entry_idx].dest_tag   <= dispatch_dest_tag;
                
                // Handle immediate wakeup if CDB matches
                if (cdb_valid) begin
                    if (!dispatch_src1_ready && dispatch_src1_tag == cdb_tag) begin
                        rs_entries[free_entry_idx].src1_value <= cdb_data;
                        rs_entries[free_entry_idx].src1_ready <= 1'b1;
                    end
                    if (!dispatch_src2_ready && dispatch_src2_tag == cdb_tag) begin
                        rs_entries[free_entry_idx].src2_value <= cdb_data;
                        rs_entries[free_entry_idx].src2_ready <= 1'b1;
                    end
                end
            end
        end
    end

endmodule