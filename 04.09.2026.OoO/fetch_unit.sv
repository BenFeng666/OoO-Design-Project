`timescale 1ns / 1ps




// ============================================================================
// fetch_unit.sv — Instruction Fetch Unit (Non-Pipelined)
// ============================================================================
// Manages the program counter and interfaces with the synchronous
// instruction ROM.  Uses a simple three-state machine to handle the
// one-cycle ROM read latency with a single-entry output buffer.
//
// Design choice: NON-PIPELINED fetch.
//   At most one ROM request in flight at a time, and at most one
//   buffered instruction.  These never overlap.  This guarantees no
//   instruction is ever dropped during stalls, at the cost of a
//   minimum two-cycle fetch latency (request cycle + capture cycle).
//   Sufficient for this educational single-issue OoO core.
//
// State machine:
//   IDLE    — No request in flight, output buffer empty.
//             Issue a ROM request and advance PC.
//   WAITING — ROM request in flight, output buffer empty.
//             Wait for ROM response next cycle.
//   VALID   — Output buffer holds a fetched instruction.
//             Hold until consumed (fetch_valid && !stall) or flushed.
//
//   Transitions:
//     IDLE    → WAITING  (issued ROM request)
//     WAITING → VALID    (ROM response arrived, stored in buffer)
//     WAITING → IDLE     (ROM response arrived but addr_valid=0)
//     VALID   → IDLE     (instruction consumed by downstream)
//     any     → IDLE     (flush or halt — discard everything)
//
// Output buffer contract (stable):
//   fetch_valid=1, stall=0 → downstream WILL consume this cycle
//   fetch_valid=1, stall=1 → downstream CANNOT accept, hold buffer
//   fetch_valid=0           → no instruction available
//   flush overrides everything: clears buffer and in-flight request
//
// PC policy:
//   Increment by 4 each time a ROM request is issued (predict not-taken).
//   On flush: load flush_target_pc.
//   On halt: stop.
// ============================================================================

module fetch_unit #(
    parameter int DATA_W   = 32,
    parameter int ADDR_W   = 32,
    parameter int RESET_PC = 32'h0000_0000
)(
    input  logic              clk,
    input  logic              rst_n,

    // --- ROM interface (top-level wires to instruction_rom) ---
    output logic [ADDR_W-1:0] rom_addr,
    output logic              rom_en,
    input  logic [DATA_W-1:0] rom_instr,
    input  logic              rom_addr_valid,     // Not used by fetch (decode handles
                                                  // illegality), kept for top-level wiring

    // --- Downstream interface (to decode) ---
    output logic [DATA_W-1:0] fetch_instr,
    output logic [ADDR_W-1:0] fetch_pc,
    output logic              fetch_valid,

    // --- Pipeline control ---
    input  logic              stall,
    input  logic              flush,
    input  logic [ADDR_W-1:0] flush_target_pc,
    input  logic              halt
);

    // ================================================================
    // State definition
    // ================================================================
    typedef enum logic [1:0] {
        S_IDLE    = 2'd0,
        S_WAITING = 2'd1,
        S_VALID   = 2'd2
    } fetch_state_t;

    fetch_state_t state;

    // ================================================================
    // Internal state
    // ================================================================
    logic [ADDR_W-1:0] pc;         // Next PC to fetch
    logic [ADDR_W-1:0] req_pc;     // PC of the in-flight ROM request

    // ================================================================
    // ROM request (combinational)
    // ================================================================
    // Only issue a request in IDLE state (no request in flight,
    // no buffered instruction) and not halted/flushing.
    // ================================================================
    logic do_request;
    assign do_request = (state == S_IDLE) && !halt && !flush;

    assign rom_addr = pc;
    assign rom_en   = do_request;

    // ================================================================
    // Sequential logic
    // ================================================================
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // ----- Reset -----
            state       <= S_IDLE;
            pc          <= RESET_PC;
            req_pc      <= '0;
            fetch_instr <= '0;
            fetch_pc    <= '0;
            fetch_valid <= 1'b0;

        end else if (flush) begin
            // ----- Flush: discard everything, redirect PC -----
            state       <= S_IDLE;
            pc          <= flush_target_pc;
            req_pc      <= '0;
            fetch_valid <= 1'b0;

        end else if (halt) begin
            // ----- Halt: stop fetching -----
            state       <= S_IDLE;
            fetch_valid <= 1'b0;

        end else begin
            case (state)
                // ------------------------------------------------
                // IDLE: issue ROM request, advance PC
                // ------------------------------------------------
                S_IDLE: begin
                    // do_request is true (combinationally drives rom_en)
                    // Record which PC we requested and advance
                    req_pc <= pc;
                    pc     <= pc + 32'd4;
                    state  <= S_WAITING;
                end

                // ------------------------------------------------
                // WAITING: ROM response arrives this cycle
                // ------------------------------------------------
                // Always capture the response into the output buffer,
                // regardless of rom_addr_valid.  For out-of-range
                // fetches, the ROM drives instr = 32'h0, which the
                // decode unit will flag as ITYPE_ILLEGAL.  This keeps
                // runaway PCs and bad redirects visible to the pipeline
                // instead of silently suppressing them.
                // ------------------------------------------------
                S_WAITING: begin
                    fetch_instr <= rom_instr;
                    fetch_pc    <= req_pc;
                    fetch_valid <= 1'b1;
                    state       <= S_VALID;
                end

                // ------------------------------------------------
                // VALID: output buffer holds an instruction
                // ------------------------------------------------
                S_VALID: begin
                    if (!stall) begin
                        // Downstream consumes the instruction
                        fetch_valid <= 1'b0;
                        state       <= S_IDLE;
                    end
                    // else: stall — hold buffer, stay in S_VALID
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule


