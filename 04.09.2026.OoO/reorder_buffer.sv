`timescale 1ns / 1ps




// ============================================================================
// reorder_buffer.sv — Reorder Buffer (ROB)
// ============================================================================
// Circular queue that restores in-order commit from out-of-order execution.
//
// Every dispatched instruction is allocated an entry in program order.
// The execution unit writes results back (via CDB), and the ROB commits
// the oldest completed entry each cycle — writing the result to the
// architectural register file.
//
// The ROB entry index IS the rename tag used throughout the pipeline.
//
// In-flight register map:
//   The ROB tracks which ROB tag will produce each architectural register's
//   next value.  Dispatch logic queries this to determine whether a source
//   operand is ready (from the register file) or must wait (on a tag).
//
// Branch handling:
//   All branches are predicted not-taken.  The ROB stores branch outcome
//   from the execution unit.  At commit, if a branch was actually taken,
//   the ROB asserts flush and provides the correct target PC.
//
// HALT handling:
//   When ECALL reaches the ROB head and is complete, halt is asserted.
//
// Package dependencies:
//   - alu_pkg    (from alu.sv)         — provides alu_op_t
//   - decode_pkg (from decode_unit.sv) — provides instr_type_t
// ============================================================================

module reorder_buffer
    import alu_pkg::*;
    import decode_pkg::*;
#(
    // ROB_DEPTH MUST be a power of two.  Head and tail pointers are TAG_W
    // bits wide and rely on natural binary wraparound (e.g. 3 → 0 for
    // depth 4).  Non-power-of-two depths would require explicit modulo
    // logic on pointer updates.
    parameter int ROB_DEPTH = 4,
    parameter int DATA_W    = 32,
    parameter int TAG_W     = $clog2(ROB_DEPTH)
)(
    input  logic              clk,
    input  logic              rst_n,

    // --- Dispatch interface (from top-level) ---
    input  logic              dispatch_en,
    input  instr_type_t       dispatch_instr_type,
    input  logic [4:0]        dispatch_rd_addr,
    input  logic              dispatch_uses_rd,
    input  logic              dispatch_is_branch,
    input  logic              dispatch_is_jump,
    input  logic [DATA_W-1:0] dispatch_pc,
    input  logic [DATA_W-1:0] dispatch_imm,       // Branch/jump offset

    output logic [TAG_W-1:0]  dispatch_tag,        // Allocated ROB tag (= tail)
    output logic              rob_full,            // Cannot allocate — stall

    // --- CDB writeback interface (from execution unit) ---
    input  logic              cdb_valid,
    input  logic [TAG_W-1:0]  cdb_tag,
    input  logic [DATA_W-1:0] cdb_value,
    input  logic              cdb_branch_taken,    // Branch was taken
    input  logic [DATA_W-1:0] cdb_branch_target,   // Correct branch target

    // --- Commit interface (to register file) ---
    output logic              commit_valid,
    output logic [4:0]        commit_rd_addr,
    output logic [DATA_W-1:0] commit_value,
    output logic              commit_uses_rd,

    // --- In-flight register map (queried by dispatch logic) ---
    // For a given architectural register, returns whether an in-flight
    // instruction will produce it and, if so, which ROB tag.
    input  logic [4:0]        lookup_rs1_addr,
    input  logic [4:0]        lookup_rs2_addr,
    output logic              lookup_rs1_inflight,
    output logic [TAG_W-1:0]  lookup_rs1_tag,
    output logic              lookup_rs1_ready,     // CDB result already in ROB
    output logic [DATA_W-1:0] lookup_rs1_value,     // Value if ready
    output logic              lookup_rs2_inflight,
    output logic [TAG_W-1:0]  lookup_rs2_tag,
    output logic              lookup_rs2_ready,
    output logic [DATA_W-1:0] lookup_rs2_value,

    // --- Flush interface (to RS, fetch) ---
    output logic              flush,
    output logic [DATA_W-1:0] flush_target_pc,

    // --- Halt ---
    output logic              halt,

    // --- Debug ---
    output logic              commit_is_branch,
    output logic              commit_is_jump,
    output instr_type_t       commit_instr_type,
    output logic [DATA_W-1:0] commit_pc
);

    // ================================================================
    // ROB entry definition
    // ================================================================
    typedef struct {
        logic              valid;          // Entry is allocated
        logic              complete;       // Execution has written back
        instr_type_t       instr_type;
        logic [4:0]        rd_addr;
        logic              uses_rd;
        logic              is_branch;
        logic              is_jump;
        logic [DATA_W-1:0] pc;
        logic [DATA_W-1:0] imm;           // Branch/jump offset
        logic [DATA_W-1:0] result;         // Execution result
        logic              branch_taken;   // Actual branch outcome
        logic [DATA_W-1:0] branch_target;  // Actual branch target
    } rob_entry_t;

    rob_entry_t entries [0:ROB_DEPTH-1];

    // Power-of-two check (elaboration-time error if violated)
    initial begin
        if ((ROB_DEPTH & (ROB_DEPTH - 1)) != 0) begin
            $fatal(1, "ROB_DEPTH must be a power of two (got %0d)", ROB_DEPTH);
        end
    end

    // ================================================================
    // Head / tail pointers and count
    // ================================================================
    logic [TAG_W-1:0] head;
    logic [TAG_W-1:0] tail;
    logic [TAG_W:0]   count;    // One extra bit to distinguish full vs empty

    wire  rob_empty = (count == '0);
    assign rob_full = (count == ROB_DEPTH[TAG_W:0]);
    assign dispatch_tag = tail;

    // ================================================================
    // In-flight register map
    // ================================================================
    // For each architectural register (0–31), tracks whether an in-flight
    // ROB entry will produce it, and which tag.
    // x0 is never mapped (writes to x0 are ignored).
    // ================================================================
    logic              inflight_valid [0:31];
    logic [TAG_W-1:0]  inflight_tag   [0:31];

    // ================================================================
    // Lookup logic: query the in-flight map for rs1 and rs2
    // ================================================================
    // If an in-flight entry exists for the queried register:
    //   - inflight = 1, tag = producing ROB entry
    //   - If that ROB entry is already complete, also return the value
    //     (so the dispatch logic can grab it directly instead of waiting)
    // ================================================================
    always_comb begin
        // RS1 lookup
        if (lookup_rs1_addr != 5'b0 && inflight_valid[lookup_rs1_addr]) begin
            lookup_rs1_inflight = 1'b1;
            lookup_rs1_tag      = inflight_tag[lookup_rs1_addr];
            // Check if the producing entry is already complete
            lookup_rs1_ready    = entries[inflight_tag[lookup_rs1_addr]].complete;
            lookup_rs1_value    = entries[inflight_tag[lookup_rs1_addr]].result;
        end else begin
            lookup_rs1_inflight = 1'b0;
            lookup_rs1_tag      = '0;
            lookup_rs1_ready    = 1'b0;
            lookup_rs1_value    = '0;
        end

        // RS2 lookup
        if (lookup_rs2_addr != 5'b0 && inflight_valid[lookup_rs2_addr]) begin
            lookup_rs2_inflight = 1'b1;
            lookup_rs2_tag      = inflight_tag[lookup_rs2_addr];
            lookup_rs2_ready    = entries[inflight_tag[lookup_rs2_addr]].complete;
            lookup_rs2_value    = entries[inflight_tag[lookup_rs2_addr]].result;
        end else begin
            lookup_rs2_inflight = 1'b0;
            lookup_rs2_tag      = '0;
            lookup_rs2_ready    = 1'b0;
            lookup_rs2_value    = '0;
        end
    end

    // ================================================================
    // Commit logic (combinational outputs)
    // ================================================================
    // The head entry commits if it is valid and complete.
    // Branches: if actually taken but predicted not-taken → flush.
    // HALT: assert halt, do not advance head.
    // ================================================================
    logic              head_can_commit;
    rob_entry_t        head_entry;

    assign head_entry      = entries[head];
    assign head_can_commit = !rob_empty && head_entry.valid && head_entry.complete;

    always_comb begin
        commit_valid      = 1'b0;
        commit_rd_addr    = head_entry.rd_addr;
        commit_value      = head_entry.result;
        commit_uses_rd    = head_entry.uses_rd;
        commit_is_branch  = head_entry.is_branch;
        commit_is_jump    = head_entry.is_jump;
        commit_instr_type = head_entry.instr_type;
        commit_pc         = head_entry.pc;
        flush             = 1'b0;
        flush_target_pc   = '0;
        halt              = 1'b0;

        if (head_can_commit) begin
            case (head_entry.instr_type)
                ITYPE_HALT: begin
                    // Program termination — assert halt, do not commit
                    halt = 1'b1;
                end

                ITYPE_BRANCH: begin
                    // Predicted not-taken.  If actually taken → flush.
                    commit_valid = 1'b1;
                    if (head_entry.branch_taken) begin
                        flush           = 1'b1;
                        flush_target_pc = head_entry.branch_target;
                    end
                end

                ITYPE_JUMP: begin
                    // Jumps always redirect — flush to the computed target.
                    // The link value (PC+4) is written to rd via normal commit.
                    commit_valid    = 1'b1;
                    flush           = 1'b1;
                    flush_target_pc = head_entry.branch_target;
                end

                default: begin
                    // ALU, LUI, AUIPC, etc. — normal commit
                    commit_valid = 1'b1;
                end
            endcase
        end
    end

    // ================================================================
    // Sequential logic: dispatch, CDB writeback, commit, flush
    // ================================================================
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            head  <= '0;
            tail  <= '0;
            count <= '0;
            for (int i = 0; i < ROB_DEPTH; i++) begin
                entries[i].valid    <= 1'b0;
                entries[i].complete <= 1'b0;
            end
            for (int i = 0; i < 32; i++) begin
                inflight_valid[i] <= 1'b0;
                inflight_tag[i]   <= '0;
            end
        end else if (flush) begin
            // ----- Flush: clear everything, restart from flush_target_pc -----
            head  <= '0;
            tail  <= '0;
            count <= '0;
            for (int i = 0; i < ROB_DEPTH; i++) begin
                entries[i].valid    <= 1'b0;
                entries[i].complete <= 1'b0;
            end
            for (int i = 0; i < 32; i++) begin
                inflight_valid[i] <= 1'b0;
                inflight_tag[i]   <= '0;
            end
        end else begin
            // --------------------------------------------------
            // 1. CDB writeback: mark entry complete, store result
            // --------------------------------------------------
            if (cdb_valid) begin
                entries[cdb_tag].complete      <= 1'b1;
                entries[cdb_tag].result        <= cdb_value;
                entries[cdb_tag].branch_taken  <= cdb_branch_taken;
                entries[cdb_tag].branch_target <= cdb_branch_target;
            end

            // --------------------------------------------------
            // 2. Commit: advance head, update in-flight map
            // --------------------------------------------------
            if (commit_valid) begin
                entries[head].valid <= 1'b0;
                entries[head].complete <= 1'b0;
                head  <= head + 1'b1;
                count <= count - 1'b1;

                // Clear in-flight mapping if this was the latest producer
                if (head_entry.uses_rd &&
                    head_entry.rd_addr != 5'b0 &&
                    inflight_valid[head_entry.rd_addr] &&
                    inflight_tag[head_entry.rd_addr] == head) begin
                    inflight_valid[head_entry.rd_addr] <= 1'b0;
                end
            end

            // --------------------------------------------------
            // 3. Dispatch: allocate entry at tail
            // --------------------------------------------------
            if (dispatch_en && !rob_full) begin
                entries[tail].valid       <= 1'b1;
                entries[tail].complete    <= 1'b0;
                entries[tail].instr_type  <= dispatch_instr_type;
                entries[tail].rd_addr     <= dispatch_rd_addr;
                entries[tail].uses_rd     <= dispatch_uses_rd;
                entries[tail].is_branch   <= dispatch_is_branch;
                entries[tail].is_jump     <= dispatch_is_jump;
                entries[tail].pc          <= dispatch_pc;
                entries[tail].imm         <= dispatch_imm;
                entries[tail].result      <= '0;
                entries[tail].branch_taken  <= 1'b0;
                entries[tail].branch_target <= '0;
                tail  <= tail + 1'b1;

                // Adjust count: handle simultaneous commit + dispatch
                if (commit_valid) begin
                    // count already decremented above; re-increment
                    // Net effect: count stays the same
                    count <= count;
                end else begin
                    count <= count + 1'b1;
                end

                // Update in-flight map (latest writer wins)
                if (dispatch_uses_rd && dispatch_rd_addr != 5'b0) begin
                    inflight_valid[dispatch_rd_addr] <= 1'b1;
                    inflight_tag[dispatch_rd_addr]   <= tail;
                end
            end else begin
                // No dispatch this cycle — if commit happened, count
                // was already decremented above, nothing more to do.
            end
        end
    end

endmodule



