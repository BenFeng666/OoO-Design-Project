// Reorder Buffer (ROB) for RV32I Out-of-Order CPU Core
// 16-entry circular buffer maintaining program order
// Handles allocation, writeback, and in-order commit

module reorder_buffer #(
    parameter ROB_ENTRIES = 16,       // Number of ROB entries
    parameter ROB_ADDR_WIDTH = 4,     // log2(ROB_ENTRIES)
    parameter ARCH_REGS = 32          // Number of architectural registers (RV32I)
)(
    input  logic                        clock,
    input  logic                        reset,
    
    // Dispatch interface - allocate new ROB entry
    input  logic                        dispatch_valid,      // New instruction to allocate
    input  logic [4:0]                  dispatch_dest_reg,   // Destination register (0-31)
    input  logic                        dispatch_dest_valid, // Instruction writes to register
    output logic [ROB_ADDR_WIDTH-1:0]   dispatch_rob_tag,    // Allocated ROB tag
    output logic                        rob_full,            // ROB is full
    
    // Writeback interface - CDB updates ROB entries
    input  logic                        cdb_valid,           // Result on CDB
    input  logic [ROB_ADDR_WIDTH-1:0]   cdb_tag,             // ROB tag of result
    input  logic [31:0]                 cdb_data,            // Result value
    
    // Commit interface - retire completed instructions
    output logic                        commit_valid,        // Instruction committing
    output logic [4:0]                  commit_dest_reg,     // Destination register
    output logic [31:0]                 commit_value,        // Result value
    output logic                        commit_reg_write,    // Write to register file
    output logic [ROB_ADDR_WIDTH-1:0]   commit_rob_tag,      // ROB tag being committed (head pointer)
    
    // Query interface - check ROB entry status
    input  logic [ROB_ADDR_WIDTH-1:0]   query_tag,           // Tag to query
    output logic                        query_ready,         // Entry is ready
    output logic [31:0]                 query_value          // Entry value
);

    // ROB entry structure
    typedef struct packed {
        logic                valid;        // Entry is occupied
        logic                done;         // Execution completed
        logic [4:0]          dest_reg;     // Destination register
        logic                dest_valid;   // Writes to register
        logic [31:0]         value;        // Result value
    } rob_entry_t;
    
    // ROB storage array
    rob_entry_t [ROB_ENTRIES-1:0] rob_entries;
    
    // Head and tail pointers (circular buffer)
    logic [ROB_ADDR_WIDTH-1:0] head_ptr;  // Points to oldest instruction
    logic [ROB_ADDR_WIDTH-1:0] tail_ptr;  // Points to next free entry
    
    // ROB status tracking
    logic [ROB_ADDR_WIDTH:0] entry_count; // Number of valid entries (need extra bit)
    
    // Full and empty signals
    assign rob_full = (entry_count == ROB_ENTRIES);
    logic rob_empty;
    assign rob_empty = (entry_count == 0);
    
    // Dispatch - allocate new entry at tail
    assign dispatch_rob_tag = tail_ptr;
    
    // Commit - retire instruction at head if done
    assign commit_valid     = !rob_empty && rob_entries[head_ptr].done;
    assign commit_dest_reg  = rob_entries[head_ptr].dest_reg;
    assign commit_value     = rob_entries[head_ptr].value;
    assign commit_reg_write = rob_entries[head_ptr].dest_valid;
    assign commit_rob_tag   = head_ptr;
    
    // Query interface - check if specific ROB entry is ready
    assign query_ready = rob_entries[query_tag].valid && rob_entries[query_tag].done;
    assign query_value = rob_entries[query_tag].value;
    
    // Sequential logic - ROB management
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            // Initialize all entries
            for (int i = 0; i < ROB_ENTRIES; i++) begin
                rob_entries[i].valid      <= 1'b0;
                rob_entries[i].done       <= 1'b0;
                rob_entries[i].dest_reg   <= 5'b0;
                rob_entries[i].dest_valid <= 1'b0;
                rob_entries[i].value      <= 32'b0;
            end
            
            // Initialize pointers
            head_ptr    <= '0;
            tail_ptr    <= '0;
            entry_count <= '0;
            
        end else begin
            // Track changes to entry count
            logic increment, decrement;
            increment = 1'b0;
            decrement = 1'b0;
            
            // Writeback - update ROB entry when result arrives on CDB
            if (cdb_valid) begin
                rob_entries[cdb_tag].done  <= 1'b1;
                rob_entries[cdb_tag].value <= cdb_data;
            end
            
            // Commit - retire head instruction if done
            if (commit_valid) begin
                rob_entries[head_ptr].valid <= 1'b0;
                rob_entries[head_ptr].done  <= 1'b0;
                head_ptr <= head_ptr + 1'b1;
                decrement = 1'b1;
            end
            
            // Dispatch - allocate new entry at tail
            if (dispatch_valid && !rob_full) begin
                rob_entries[tail_ptr].valid      <= 1'b1;
                rob_entries[tail_ptr].done       <= 1'b0;
                rob_entries[tail_ptr].dest_reg   <= dispatch_dest_reg;
                rob_entries[tail_ptr].dest_valid <= dispatch_dest_valid;
                rob_entries[tail_ptr].value      <= 32'b0;
                tail_ptr <= tail_ptr + 1'b1;
                increment = 1'b1;
            end
            
            // Update entry count
            case ({increment, decrement})
                2'b10: entry_count <= entry_count + 1'b1;  // Dispatch only
                2'b01: entry_count <= entry_count - 1'b1;  // Commit only
                2'b11: entry_count <= entry_count;         // Both (no change)
                default: entry_count <= entry_count;       // Neither
            endcase
        end
    end

endmodule