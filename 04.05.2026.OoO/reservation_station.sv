// ============================================================================
// reservation_station.sv — Tomasulo Reservation Station
// ============================================================================
// Holds dispatched instructions waiting for operands.  Monitors the CDB
// to capture results for pending source operands.  Issues a ready
// instruction to the execution unit each cycle.
//
// Tag convention:
//   The ROB entry index IS the rename tag.  There is no separate rename
//   table or physical register file.  Tag width is derived from ROB_DEPTH.
//
// Package dependencies:
//   - alu_pkg    (from alu.sv)         — provides alu_op_t
//   - decode_pkg (from decode_unit.sv) — provides instr_type_t
//
// Dispatch-side CDB snoop:
//   If the CDB is broadcasting a result in the same cycle as dispatch,
//   and the dispatched instruction's source tag matches the CDB tag,
//   the RS captures the CDB value directly instead of storing the tag.
//
// Issue policy:
//   Single-issue, first-ready by slot index (linear scan from slot 0).
//   The RS does NOT attempt to enforce age ordering — any ready
//   instruction may issue.  The ROB is solely responsible for in-order
//   commit.  This is correct for a Tomasulo-style OoO design: the RS
//   feeds the execution unit opportunistically, and the ROB serializes
//   retirement.
//
// Issue handshake:
//   The RS presents a ready instruction on the issue outputs and asserts
//   issue_valid.  The execution unit asserts issue_accept to consume it.
//   The RS entry is only cleared when both issue_valid && issue_accept
//   are high on the same rising edge.  If the execution unit is busy,
//   it holds issue_accept low and the RS re-presents the same entry
//   next cycle (or a different ready entry if the first is no longer
//   the scan winner — but in practice with single-issue the same entry
//   will win again).
//
// Slot reuse limitation:
//   A slot freed by issue in cycle N is not available for dispatch until
//   cycle N+1.  The free-slot scan is combinational on pre-edge state,
//   so a simultaneously issued slot still appears busy to the dispatch
//   logic in the same cycle.  This is a simplification that costs at
//   most one cycle of dispatch throughput when the RS is full.
// ============================================================================

module reservation_station
    import alu_pkg::*;
    import decode_pkg::*;
#(
    parameter int RS_DEPTH  = 4,
    parameter int ROB_DEPTH = 4,
    parameter int DATA_W    = 32,
    parameter int TAG_W     = $clog2(ROB_DEPTH)
)(
    input  logic              clk,
    input  logic              rst_n,
    input  logic              flush,          // Clear all entries

    // --- Dispatch interface (from top-level) ---
    input  logic              dispatch_en,    // New instruction being dispatched
    input  alu_op_t           dispatch_alu_op,
    input  instr_type_t       dispatch_instr_type,
    input  logic [2:0]        dispatch_funct3,
    input  logic [DATA_W-1:0] dispatch_pc,
    input  logic [DATA_W-1:0] dispatch_imm,
    input  logic              dispatch_uses_imm,  // Op B is immediate
    input  logic [4:0]        dispatch_rd_addr,
    input  logic              dispatch_uses_rd,
    input  logic              dispatch_is_branch,
    input  logic              dispatch_is_jump,
    input  logic              dispatch_is_jalr,

    // Source 1: either a ready value or a tag to wait on
    input  logic              dispatch_src1_ready,
    input  logic [DATA_W-1:0] dispatch_src1_value,
    input  logic [TAG_W-1:0]  dispatch_src1_tag,

    // Source 2: either a ready value or a tag to wait on
    // (ignored if dispatch_uses_imm — immediate is used instead)
    input  logic              dispatch_src2_ready,
    input  logic [DATA_W-1:0] dispatch_src2_value,
    input  logic [TAG_W-1:0]  dispatch_src2_tag,

    // ROB tag assigned to this instruction
    input  logic [TAG_W-1:0]  dispatch_rob_tag,

    // --- CDB snoop interface (from execution unit) ---
    input  logic              cdb_valid,
    input  logic [TAG_W-1:0]  cdb_tag,
    input  logic [DATA_W-1:0] cdb_value,

    // --- Issue interface (to execution unit) ---
    output logic              issue_valid,
    output alu_op_t           issue_alu_op,
    output instr_type_t       issue_instr_type,
    output logic [2:0]        issue_funct3,
    output logic [DATA_W-1:0] issue_pc,
    output logic [DATA_W-1:0] issue_imm,
    output logic              issue_uses_imm,
    output logic [4:0]        issue_rd_addr,
    output logic              issue_uses_rd,
    output logic              issue_is_branch,
    output logic              issue_is_jump,
    output logic              issue_is_jalr,
    output logic [DATA_W-1:0] issue_src1_value,
    output logic [DATA_W-1:0] issue_src2_value,
    output logic [TAG_W-1:0]  issue_rob_tag,

    input  logic              issue_accept,   // Execution unit consumed the issue

    // --- Status ---
    output logic              rs_full         // No free entry — stall dispatch
);

    // ================================================================
    // RS entry storage
    // ================================================================
    typedef struct packed {
        logic              busy;
        alu_op_t           alu_op;
        instr_type_t       instr_type;
        logic [2:0]        funct3;
        logic [DATA_W-1:0] pc;
        logic [DATA_W-1:0] imm;
        logic              uses_imm;
        logic [4:0]        rd_addr;
        logic              uses_rd;
        logic              is_branch;
        logic              is_jump;
        logic              is_jalr;
        // Source 1
        logic              src1_ready;
        logic [DATA_W-1:0] src1_value;
        logic [TAG_W-1:0]  src1_tag;
        // Source 2
        logic              src2_ready;
        logic [DATA_W-1:0] src2_value;
        logic [TAG_W-1:0]  src2_tag;
        // ROB tag for this instruction
        logic [TAG_W-1:0]  rob_tag;
    } rs_entry_t;

    rs_entry_t entries [0:RS_DEPTH-1];

    // ================================================================
    // Free-entry detection (priority encoder — first free slot)
    // ================================================================
    logic [RS_DEPTH-1:0] entry_free;
    logic [RS_DEPTH-1:0] entry_ready;
    logic                has_free;
    logic [$clog2(RS_DEPTH)-1:0] free_idx;

    always_comb begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            entry_free[i] = !entries[i].busy;
        end
        has_free = 1'b0;
        free_idx = '0;
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (entry_free[i] && !has_free) begin
                has_free = 1'b1;
                free_idx = i[$clog2(RS_DEPTH)-1:0];
            end
        end
    end

    assign rs_full = !has_free;

    // ================================================================
    // Ready-to-issue detection
    // ================================================================
    // An entry is ready when it is busy and both sources are ready.
    // For entries with uses_imm, src2_ready was set at dispatch time,
    // so the check is uniform.
    // ================================================================
    always_comb begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            entry_ready[i] = entries[i].busy
                           & entries[i].src1_ready
                           & entries[i].src2_ready;
        end
    end

    // ================================================================
    // Issue selection: first-ready by linear scan from slot 0
    // ================================================================
    // No age ordering — any ready instruction may issue.  The ROB
    // is solely responsible for in-order commit.
    // ================================================================
    logic                         has_ready;
    logic [$clog2(RS_DEPTH)-1:0]  issue_idx;

    always_comb begin
        has_ready = 1'b0;
        issue_idx = '0;
        for (int i = 0; i < RS_DEPTH; i++) begin
            if (entry_ready[i] && !has_ready) begin
                has_ready = 1'b1;
                issue_idx = i[$clog2(RS_DEPTH)-1:0];
            end
        end
    end

    // ================================================================
    // Issue outputs (combinational from selected entry)
    // ================================================================
    always_comb begin
        issue_valid = has_ready;
        if (has_ready) begin
            issue_alu_op     = entries[issue_idx].alu_op;
            issue_instr_type = entries[issue_idx].instr_type;
            issue_funct3     = entries[issue_idx].funct3;
            issue_pc         = entries[issue_idx].pc;
            issue_imm        = entries[issue_idx].imm;
            issue_uses_imm   = entries[issue_idx].uses_imm;
            issue_rd_addr    = entries[issue_idx].rd_addr;
            issue_uses_rd    = entries[issue_idx].uses_rd;
            issue_is_branch  = entries[issue_idx].is_branch;
            issue_is_jump    = entries[issue_idx].is_jump;
            issue_is_jalr    = entries[issue_idx].is_jalr;
            issue_src1_value = entries[issue_idx].src1_value;
            issue_src2_value = entries[issue_idx].src2_value;
            issue_rob_tag    = entries[issue_idx].rob_tag;
        end else begin
            issue_alu_op     = ALU_ADD;
            issue_instr_type = ITYPE_ILLEGAL;
            issue_funct3     = 3'b0;
            issue_pc         = '0;
            issue_imm        = '0;
            issue_uses_imm   = 1'b0;
            issue_rd_addr    = 5'b0;
            issue_uses_rd    = 1'b0;
            issue_is_branch  = 1'b0;
            issue_is_jump    = 1'b0;
            issue_is_jalr    = 1'b0;
            issue_src1_value = '0;
            issue_src2_value = '0;
            issue_rob_tag    = '0;
        end
    end

    // ================================================================
    // Sequential logic: dispatch, CDB snoop, issue removal, flush
    // ================================================================
    always_ff @(posedge clk) begin
        if (!rst_n || flush) begin
            for (int i = 0; i < RS_DEPTH; i++) begin
                entries[i].busy <= 1'b0;
            end
        end else begin
            // --------------------------------------------------
            // 1. CDB snoop: update waiting operands in all entries
            // --------------------------------------------------
            if (cdb_valid) begin
                for (int i = 0; i < RS_DEPTH; i++) begin
                    if (entries[i].busy) begin
                        if (!entries[i].src1_ready &&
                            (entries[i].src1_tag == cdb_tag)) begin
                            entries[i].src1_ready <= 1'b1;
                            entries[i].src1_value <= cdb_value;
                        end
                        if (!entries[i].src2_ready &&
                            (entries[i].src2_tag == cdb_tag)) begin
                            entries[i].src2_ready <= 1'b1;
                            entries[i].src2_value <= cdb_value;
                        end
                    end
                end
            end

            // --------------------------------------------------
            // 2. Issue removal: clear entry only when execution
            //    unit accepts the issue (issue_valid && issue_accept)
            // --------------------------------------------------
            if (has_ready && issue_accept) begin
                entries[issue_idx].busy <= 1'b0;
            end

            // --------------------------------------------------
            // 3. Dispatch: write new entry into first free slot
            //    Includes CDB forwarding at dispatch time.
            // --------------------------------------------------
            if (dispatch_en && has_free) begin
                entries[free_idx].busy       <= 1'b1;
                entries[free_idx].alu_op     <= dispatch_alu_op;
                entries[free_idx].instr_type <= dispatch_instr_type;
                entries[free_idx].funct3     <= dispatch_funct3;
                entries[free_idx].pc         <= dispatch_pc;
                entries[free_idx].imm        <= dispatch_imm;
                entries[free_idx].uses_imm   <= dispatch_uses_imm;
                entries[free_idx].rd_addr    <= dispatch_rd_addr;
                entries[free_idx].uses_rd    <= dispatch_uses_rd;
                entries[free_idx].is_branch  <= dispatch_is_branch;
                entries[free_idx].is_jump    <= dispatch_is_jump;
                entries[free_idx].is_jalr    <= dispatch_is_jalr;
                entries[free_idx].rob_tag    <= dispatch_rob_tag;

                // Source 1: CDB forwarding at dispatch
                if (dispatch_src1_ready) begin
                    entries[free_idx].src1_ready <= 1'b1;
                    entries[free_idx].src1_value <= dispatch_src1_value;
                    entries[free_idx].src1_tag   <= '0;
                end else if (cdb_valid && (dispatch_src1_tag == cdb_tag)) begin
                    entries[free_idx].src1_ready <= 1'b1;
                    entries[free_idx].src1_value <= cdb_value;
                    entries[free_idx].src1_tag   <= '0;
                end else begin
                    entries[free_idx].src1_ready <= 1'b0;
                    entries[free_idx].src1_value <= dispatch_src1_value;
                    entries[free_idx].src1_tag   <= dispatch_src1_tag;
                end

                // Source 2: immediate or register
                if (dispatch_uses_imm) begin
                    entries[free_idx].src2_ready <= 1'b1;
                    entries[free_idx].src2_value <= dispatch_imm;
                    entries[free_idx].src2_tag   <= '0;
                end else if (dispatch_src2_ready) begin
                    entries[free_idx].src2_ready <= 1'b1;
                    entries[free_idx].src2_value <= dispatch_src2_value;
                    entries[free_idx].src2_tag   <= '0;
                end else if (cdb_valid && (dispatch_src2_tag == cdb_tag)) begin
                    entries[free_idx].src2_ready <= 1'b1;
                    entries[free_idx].src2_value <= cdb_value;
                    entries[free_idx].src2_tag   <= '0;
                end else begin
                    entries[free_idx].src2_ready <= 1'b0;
                    entries[free_idx].src2_value <= dispatch_src2_value;
                    entries[free_idx].src2_tag   <= dispatch_src2_tag;
                end
            end
        end
    end

endmodule
