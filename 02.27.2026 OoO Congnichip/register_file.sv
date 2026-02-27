// Register File with Renaming for RV32I Out-of-Order CPU Core
// 32 architectural registers (x0-x31)
// Register Alias Table (RAT) for register renaming
// Supports speculative execution with ROB integration

module register_file #(
    parameter ARCH_REGS = 32,         // Number of architectural registers
    parameter ROB_ADDR_WIDTH = 4      // ROB tag width
)(
    input  logic                        clock,
    input  logic                        reset,
    
    // Read port 1 - source operand 1
    input  logic [4:0]                  rs1_addr,           // Source register 1 address
    output logic [31:0]                 rs1_value,          // Source register 1 value
    output logic                        rs1_valid,          // Value is valid (not renamed)
    output logic [ROB_ADDR_WIDTH-1:0]   rs1_tag,            // ROB tag if renamed
    
    // Read port 2 - source operand 2
    input  logic [4:0]                  rs2_addr,           // Source register 2 address
    output logic [31:0]                 rs2_value,          // Source register 2 value
    output logic                        rs2_valid,          // Value is valid (not renamed)
    output logic [ROB_ADDR_WIDTH-1:0]   rs2_tag,            // ROB tag if renamed
    
    // Write port - commit stage updates architectural state
    input  logic                        commit_valid,       // Commit write enable
    input  logic [4:0]                  commit_dest_reg,    // Destination register
    input  logic [31:0]                 commit_value,       // Value to write
    input  logic [ROB_ADDR_WIDTH-1:0]   commit_rob_tag,     // ROB tag being committed
    
    // Rename interface - dispatch stage allocates new mappings
    input  logic                        rename_valid,       // New instruction being renamed
    input  logic [4:0]                  rename_dest_reg,    // Destination register to rename
    input  logic [ROB_ADDR_WIDTH-1:0]   rename_rob_tag,     // ROB tag for new mapping
    
    // Recovery interface - flush on misprediction or exception
    input  logic                        flush               // Clear all renaming
);

    // Architectural Register File - committed state
    logic [31:0] arch_regs [ARCH_REGS-1:0];
    
    // Register Alias Table (RAT) - speculative renaming
    typedef struct packed {
        logic                       valid;    // Register is renamed (waiting for ROB)
        logic [ROB_ADDR_WIDTH-1:0]  rob_tag;  // ROB tag for pending result
    } rat_entry_t;
    
    rat_entry_t rat [ARCH_REGS-1:0];
    
    // Read port 1 logic
    always_comb begin
        if (rs1_addr == 5'b0) begin
            // x0 is always zero in RISC-V
            rs1_value = 32'b0;
            rs1_valid = 1'b1;
            rs1_tag   = '0;
        end else if (rat[rs1_addr].valid) begin
            // Register is renamed - need to wait for ROB
            rs1_value = 32'b0;  // Will be filled by ROB lookup
            rs1_valid = 1'b0;
            rs1_tag   = rat[rs1_addr].rob_tag;
        end else begin
            // Use architectural register value
            rs1_value = arch_regs[rs1_addr];
            rs1_valid = 1'b1;
            rs1_tag   = '0;
        end
    end
    
    // Read port 2 logic
    always_comb begin
        if (rs2_addr == 5'b0) begin
            // x0 is always zero in RISC-V
            rs2_value = 32'b0;
            rs2_valid = 1'b1;
            rs2_tag   = '0;
        end else if (rat[rs2_addr].valid) begin
            // Register is renamed - need to wait for ROB
            rs2_value = 32'b0;  // Will be filled by ROB lookup
            rs2_valid = 1'b0;
            rs2_tag   = rat[rs2_addr].rob_tag;
        end else begin
            // Use architectural register value
            rs2_value = arch_regs[rs2_addr];
            rs2_valid = 1'b1;
            rs2_tag   = '0;
        end
    end
    
    // Sequential logic - register updates and renaming
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            // Initialize all architectural registers to zero
            for (int i = 0; i < ARCH_REGS; i++) begin
                arch_regs[i] <= 32'b0;
            end
            
            // Clear all RAT entries
            for (int i = 0; i < ARCH_REGS; i++) begin
                rat[i].valid   <= 1'b0;
                rat[i].rob_tag <= '0;
            end
            
        end else begin
            // Flush - clear all renaming (on misprediction/exception)
            if (flush) begin
                for (int i = 0; i < ARCH_REGS; i++) begin
                    rat[i].valid <= 1'b0;
                end
            end else begin
                // Commit - update architectural state
                if (commit_valid && commit_dest_reg != 5'b0) begin
                    arch_regs[commit_dest_reg] <= commit_value;
                    
                    // Clear RAT entry only if this commit matches the current RAT mapping
                    // (prevent clearing if a newer rename has occurred)
                    if (rat[commit_dest_reg].valid && 
                        rat[commit_dest_reg].rob_tag == commit_rob_tag) begin
                        rat[commit_dest_reg].valid <= 1'b0;
                    end
                end
                
                // Rename - create new mapping for destination register
                if (rename_valid && rename_dest_reg != 5'b0) begin
                    rat[rename_dest_reg].valid   <= 1'b1;
                    rat[rename_dest_reg].rob_tag <= rename_rob_tag;
                end
            end
        end
    end

endmodule