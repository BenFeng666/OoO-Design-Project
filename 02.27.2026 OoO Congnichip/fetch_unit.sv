// Fetch Unit for RV32I Out-of-Order CPU Core
// Manages program counter and fetches instructions from ROM
// Simple sequential fetch with stall capability

module fetch_unit #(
    parameter ROM_ADDR_WIDTH = 4      // ROM address width (16 entries)
)(
    input  logic                        clock,
    input  logic                        reset,
    
    // Instruction ROM interface
    output logic [ROM_ADDR_WIDTH-1:0]   rom_addr,           // ROM address (PC)
    input  logic [31:0]                 rom_instruction,    // Instruction from ROM
    
    // Output to decode stage
    output logic [31:0]                 fetch_instruction,  // Fetched instruction
    output logic                        fetch_valid,        // Fetch output valid
    
    // Stall control
    input  logic                        stall,              // Stall fetch (decode busy)
    
    // Flush control (for branch misprediction)
    input  logic                        flush,              // Flush pipeline
    input  logic [ROM_ADDR_WIDTH-1:0]   flush_pc            // New PC on flush
);

    // Program Counter
    logic [ROM_ADDR_WIDTH-1:0] pc;
    logic [ROM_ADDR_WIDTH-1:0] next_pc;
    
    // ROM has 1-cycle latency, so we need to pipeline
    logic [31:0]               fetched_instr;
    logic                      fetched_valid;
    
    // Track ROM initialization state (need 2 cycles: 1 for PC to ROM, 1 for ROM latency)
    logic [1:0]                init_cycles;
    logic                      rom_initialized;
    
    // ROM is ready after 2 cycles: first cycle PC->ROM, second cycle ROM->output
    assign rom_initialized = (init_cycles == 2'd2);
    
    // PC update logic
    always_comb begin
        if (flush) begin
            // Branch misprediction: use flush PC
            next_pc = flush_pc;
        end else if (stall) begin
            // Stall: keep current PC
            next_pc = pc;
        end else begin
            // Normal operation: increment PC
            next_pc = pc + 1'b1;
        end
    end
    
    // Send current PC to ROM
    assign rom_addr = pc;
    
    // Sequential PC update
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            pc <= '0;  // Start at address 0
            init_cycles <= 2'd0;
        end else begin
            pc <= next_pc;
            // Count initialization cycles (saturate at 2)
            if (init_cycles < 2'd2) begin
                init_cycles <= init_cycles + 2'd1;
            end
        end
    end
    
    // Pipeline ROM output (1-cycle delay)
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            fetched_instr <= 32'b0;
            fetched_valid <= 1'b0;
        end else begin
            if (flush) begin
                // Flush: invalidate fetched instruction
                fetched_valid <= 1'b0;
            end else if (!stall && rom_initialized) begin
                // Normal fetch: capture ROM output (only after ROM is initialized)
                fetched_instr <= rom_instruction;
                fetched_valid <= 1'b1;
            end else if (!rom_initialized) begin
                // Still initializing: keep valid low
                fetched_valid <= 1'b0;
            end
            // If stalled, keep current values
        end
    end
    
    // Output to decode stage
    assign fetch_instruction = fetched_instr;
    assign fetch_valid       = fetched_valid && !flush;

endmodule