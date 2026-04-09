`timescale 1ns / 1ps




// ============================================================================
// ooo_cpu_core.sv — Top-Level RV32I Out-of-Order CPU Core
// ============================================================================
// Instantiates and wires all sub-modules:
//   - fetch_unit         (PC management, ROM interface)
//   - instruction_rom    (synchronous read instruction memory)
//   - decode_unit        (combinational instruction decoder)
//   - register_file      (committed architectural state)
//   - reservation_station (operand waiting / issue)
//   - reorder_buffer     (in-order commit, in-flight rename map)
//   - execution_unit     (ALU + branch/jump + CDB broadcast)
//
// Contains dispatch logic: reads register file, queries ROB in-flight
// map, and determines operand readiness for RS entries.
//
// Package dependencies:
//   - alu_pkg    (from alu.sv)         — provides alu_op_t
//   - decode_pkg (from decode_unit.sv) — provides instr_type_t
// ============================================================================

module ooo_cpu_core
    import alu_pkg::*;
    import decode_pkg::*;
#(
    parameter int ROM_DEPTH = 256,
    parameter int ROB_DEPTH = 4,        // Must be power of two
    parameter int RS_DEPTH  = 4,
    parameter int DATA_W    = 32,
    parameter int TAG_W     = $clog2(ROB_DEPTH),
    parameter     MEM_FILE  = "program.hex"
)(
    input  logic        clk,
    input  logic        rst_n,

    // --- Debug outputs ---
    output logic [31:0] dbg_pc,
    output logic        dbg_fetch_valid,
    output logic        dbg_decode_valid,
    output logic        dbg_dispatch_valid,
    output logic        dbg_issue_valid,
    output logic        dbg_execute_valid,      // CDB valid
    output logic        dbg_commit_valid,
    output logic [31:0] dbg_commit_pc,
    output logic [4:0]  dbg_commit_rd,
    output logic [31:0] dbg_commit_value,
    output logic        dbg_commit_uses_rd,
    output logic        dbg_halt
);

    // ================================================================
    // Internal wires
    // ================================================================

    // --- Fetch ↔ ROM ---
    logic [31:0] rom_addr;
    logic        rom_en;
    logic [31:0] rom_instr;
    logic        rom_addr_valid;

    // --- Fetch → Decode ---
    logic [31:0] fetch_instr;
    logic [31:0] fetch_pc;
    logic        fetch_valid;

    // --- Decode outputs ---
    logic [4:0]       dec_rs1_addr;
    logic [4:0]       dec_rs2_addr;
    logic [4:0]       dec_rd_addr;
    logic             dec_uses_rs1;
    logic             dec_uses_rs2;
    logic             dec_uses_rd;
    logic [31:0]      dec_imm;
    logic             dec_uses_imm;
    alu_op_t          dec_alu_op;
    instr_type_t      dec_instr_type;
    logic             dec_is_branch;
    logic             dec_is_jump;
    logic             dec_is_jalr;
    logic [2:0]       dec_funct3;
    logic [31:0]      dec_pc_out;
    logic             dec_valid;

    // --- Register file read ---
    logic [31:0] rf_rs1_data;
    logic [31:0] rf_rs2_data;

    // --- ROB signals ---
    logic [TAG_W-1:0] rob_dispatch_tag;
    logic             rob_full;
    logic             rob_commit_valid;
    logic [4:0]       rob_commit_rd_addr;
    logic [31:0]      rob_commit_value;
    logic             rob_commit_uses_rd;
    logic             rob_flush;
    logic [31:0]      rob_flush_target_pc;
    logic             rob_halt;
    logic             rob_commit_is_branch;
    logic             rob_commit_is_jump;
    instr_type_t      rob_commit_instr_type;
    logic [31:0]      rob_commit_pc;

    // ROB lookup
    logic             rob_rs1_inflight;
    logic [TAG_W-1:0] rob_rs1_tag;
    logic             rob_rs1_ready;
    logic [31:0]      rob_rs1_value;
    logic             rob_rs2_inflight;
    logic [TAG_W-1:0] rob_rs2_tag;
    logic             rob_rs2_ready;
    logic [31:0]      rob_rs2_value;

    // --- RS signals ---
    logic        rs_full;
    logic        rs_issue_valid;
    alu_op_t     rs_issue_alu_op;
    instr_type_t rs_issue_instr_type;
    logic [2:0]  rs_issue_funct3;
    logic [31:0] rs_issue_pc;
    logic [31:0] rs_issue_imm;
    logic        rs_issue_uses_imm;
    logic [4:0]  rs_issue_rd_addr;
    logic        rs_issue_uses_rd;
    logic        rs_issue_is_branch;
    logic        rs_issue_is_jump;
    logic        rs_issue_is_jalr;
    logic [31:0] rs_issue_src1_value;
    logic [31:0] rs_issue_src2_value;
    logic [TAG_W-1:0] rs_issue_rob_tag;

    // --- Execution / CDB ---
    logic             exec_issue_accept;
    logic             cdb_valid;
    logic [TAG_W-1:0] cdb_tag;
    logic [31:0]      cdb_value;
    logic             cdb_branch_taken;
    logic [31:0]      cdb_branch_target;

    // ================================================================
    // Pipeline control
    // ================================================================
    logic stall;
    logic dispatch_en;
    logic illegal_halt;

    // Illegal instruction detection: if the fetch unit delivers a
    // valid instruction word but the decode unit cannot decode it
    // (dec_valid = 0), the instruction is illegal.  For this
    // educational core, illegal instructions halt the CPU immediately.
    // This makes end-of-ROM zero words, bad encodings, and runaway
    // PCs visible and terminal rather than silently ignored.
    assign illegal_halt = fetch_valid && !dec_valid;

    // Combined halt signal: either ECALL committed or illegal fetched
    logic halt_any;
    assign halt_any = rob_halt || illegal_halt;

    // Stall fetch when RS or ROB is full.  Halt is handled separately
    // via the fetch unit's halt input (which stops fetching entirely).
    assign stall = rs_full || rob_full;

    // Dispatch when we have a valid decoded instruction, RS and ROB
    // have space, and we are not halted (ECALL or illegal) or flushing
    assign dispatch_en = fetch_valid && dec_valid
                       && !rs_full && !rob_full
                       && !halt_any && !rob_flush;

    // ================================================================
    // Instruction ROM
    // ================================================================
    instruction_rom #(
        .ROM_DEPTH (ROM_DEPTH),
        .MEM_FILE  (MEM_FILE)
    ) u_irom (
        .clk        (clk),
        .en         (rom_en),
        .addr       (rom_addr),
        .instr      (rom_instr),
        .addr_valid (rom_addr_valid)
    );

    // ================================================================
    // Fetch Unit
    // ================================================================
    fetch_unit #(
        .RESET_PC (32'h0000_0000)
    ) u_fetch (
        .clk            (clk),
        .rst_n          (rst_n),
        .rom_addr       (rom_addr),
        .rom_en         (rom_en),
        .rom_instr      (rom_instr),
        .rom_addr_valid (rom_addr_valid),
        .fetch_instr    (fetch_instr),
        .fetch_pc       (fetch_pc),
        .fetch_valid    (fetch_valid),
        .stall          (stall),
        .flush          (rob_flush),
        .flush_target_pc(rob_flush_target_pc),
        .halt           (halt_any)
    );

    // ================================================================
    // Decode Unit (combinational)
    // ================================================================
    decode_unit u_decode (
        .instr       (fetch_instr),
        .pc          (fetch_pc),
        .instr_valid (fetch_valid),
        .rs1_addr    (dec_rs1_addr),
        .rs2_addr    (dec_rs2_addr),
        .rd_addr     (dec_rd_addr),
        .uses_rs1    (dec_uses_rs1),
        .uses_rs2    (dec_uses_rs2),
        .uses_rd     (dec_uses_rd),
        .imm         (dec_imm),
        .uses_imm    (dec_uses_imm),
        .alu_op      (dec_alu_op),
        .instr_type  (dec_instr_type),
        .is_branch   (dec_is_branch),
        .is_jump     (dec_is_jump),
        .is_jalr     (dec_is_jalr),
        .funct3_out  (dec_funct3),
        .pc_out      (dec_pc_out),
        .decode_valid(dec_valid)
    );

    // ================================================================
    // Register File
    // ================================================================
    register_file u_rf (
        .clk      (clk),
        .rst_n    (rst_n),
        .rd_addr1 (dec_rs1_addr),
        .rd_data1 (rf_rs1_data),
        .rd_addr2 (dec_rs2_addr),
        .rd_data2 (rf_rs2_data),
        .wr_en    (rob_commit_valid && rob_commit_uses_rd),
        .wr_addr  (rob_commit_rd_addr),
        .wr_data  (rob_commit_value)
    );

    // ================================================================
    // Dispatch logic: determine operand readiness
    // ================================================================
    // For each source operand:
    //   1. Does the ROB in-flight map have an entry for this register?
    //   2. If yes, is the producing ROB entry already complete?
    //      → ready, use the ROB entry's result value
    //   3. If no in-flight producer → ready, use register file value
    //   4. If in-flight but not complete → not ready, pass the ROB tag
    //
    // Special case: CDB forwarding.  If the CDB is broadcasting a
    // result this cycle for the tag we would wait on, we can grab
    // the value directly.  This is handled by the RS at dispatch time
    // (dispatch-side CDB snoop), so we don't duplicate it here.
    // We pass the tag and let the RS handle forwarding.
    // ================================================================

    logic             disp_src1_ready;
    logic [31:0]      disp_src1_value;
    logic [TAG_W-1:0] disp_src1_tag;

    logic             disp_src2_ready;
    logic [31:0]      disp_src2_value;
    logic [TAG_W-1:0] disp_src2_tag;

    always_comb begin
        // --- Source 1 ---
        if (!dec_uses_rs1 || dec_rs1_addr == 5'b0) begin
            // Instruction doesn't use rs1, or rs1 is x0
            disp_src1_ready = 1'b1;
            disp_src1_value = 32'b0;
            disp_src1_tag   = '0;
        end else if (!rob_rs1_inflight) begin
            // No in-flight producer — use register file value
            disp_src1_ready = 1'b1;
            disp_src1_value = rf_rs1_data;
            disp_src1_tag   = '0;
        end else if (rob_rs1_ready) begin
            // In-flight producer exists and is already complete
            disp_src1_ready = 1'b1;
            disp_src1_value = rob_rs1_value;
            disp_src1_tag   = '0;
        end else begin
            // In-flight, not yet complete — wait on tag
            disp_src1_ready = 1'b0;
            disp_src1_value = '0;
            disp_src1_tag   = rob_rs1_tag;
        end

        // --- Source 2 ---
        if (!dec_uses_rs2 || dec_rs2_addr == 5'b0) begin
            disp_src2_ready = 1'b1;
            disp_src2_value = 32'b0;
            disp_src2_tag   = '0;
        end else if (!rob_rs2_inflight) begin
            disp_src2_ready = 1'b1;
            disp_src2_value = rf_rs2_data;
            disp_src2_tag   = '0;
        end else if (rob_rs2_ready) begin
            disp_src2_ready = 1'b1;
            disp_src2_value = rob_rs2_value;
            disp_src2_tag   = '0;
        end else begin
            disp_src2_ready = 1'b0;
            disp_src2_value = '0;
            disp_src2_tag   = rob_rs2_tag;
        end
    end

    // ================================================================
    // Reservation Station
    // ================================================================
    reservation_station #(
        .RS_DEPTH  (RS_DEPTH),
        .ROB_DEPTH (ROB_DEPTH)
    ) u_rs (
        .clk                 (clk),
        .rst_n               (rst_n),
        .flush               (rob_flush),

        .dispatch_en         (dispatch_en),
        .dispatch_alu_op     (dec_alu_op),
        .dispatch_instr_type (dec_instr_type),
        .dispatch_funct3     (dec_funct3),
        .dispatch_pc         (dec_pc_out),
        .dispatch_imm        (dec_imm),
        .dispatch_uses_imm   (dec_uses_imm),
        .dispatch_rd_addr    (dec_rd_addr),
        .dispatch_uses_rd    (dec_uses_rd),
        .dispatch_is_branch  (dec_is_branch),
        .dispatch_is_jump    (dec_is_jump),
        .dispatch_is_jalr    (dec_is_jalr),
        .dispatch_src1_ready (disp_src1_ready),
        .dispatch_src1_value (disp_src1_value),
        .dispatch_src1_tag   (disp_src1_tag),
        .dispatch_src2_ready (disp_src2_ready),
        .dispatch_src2_value (disp_src2_value),
        .dispatch_src2_tag   (disp_src2_tag),
        .dispatch_rob_tag    (rob_dispatch_tag),

        .cdb_valid           (cdb_valid),
        .cdb_tag             (cdb_tag),
        .cdb_value           (cdb_value),

        .issue_valid         (rs_issue_valid),
        .issue_alu_op        (rs_issue_alu_op),
        .issue_instr_type    (rs_issue_instr_type),
        .issue_funct3        (rs_issue_funct3),
        .issue_pc            (rs_issue_pc),
        .issue_imm           (rs_issue_imm),
        .issue_uses_imm      (rs_issue_uses_imm),
        .issue_rd_addr       (rs_issue_rd_addr),
        .issue_uses_rd       (rs_issue_uses_rd),
        .issue_is_branch     (rs_issue_is_branch),
        .issue_is_jump       (rs_issue_is_jump),
        .issue_is_jalr       (rs_issue_is_jalr),
        .issue_src1_value    (rs_issue_src1_value),
        .issue_src2_value    (rs_issue_src2_value),
        .issue_rob_tag       (rs_issue_rob_tag),
        .issue_accept        (exec_issue_accept),

        .rs_full             (rs_full)
    );

    // ================================================================
    // Reorder Buffer
    // ================================================================
    reorder_buffer #(
        .ROB_DEPTH (ROB_DEPTH)
    ) u_rob (
        .clk                 (clk),
        .rst_n               (rst_n),

        .dispatch_en         (dispatch_en),
        .dispatch_instr_type (dec_instr_type),
        .dispatch_rd_addr    (dec_rd_addr),
        .dispatch_uses_rd    (dec_uses_rd),
        .dispatch_is_branch  (dec_is_branch),
        .dispatch_is_jump    (dec_is_jump),
        .dispatch_pc         (dec_pc_out),
        .dispatch_imm        (dec_imm),
        .dispatch_tag        (rob_dispatch_tag),
        .rob_full            (rob_full),

        .cdb_valid           (cdb_valid),
        .cdb_tag             (cdb_tag),
        .cdb_value           (cdb_value),
        .cdb_branch_taken    (cdb_branch_taken),
        .cdb_branch_target   (cdb_branch_target),

        .commit_valid        (rob_commit_valid),
        .commit_rd_addr      (rob_commit_rd_addr),
        .commit_value        (rob_commit_value),
        .commit_uses_rd      (rob_commit_uses_rd),

        .lookup_rs1_addr     (dec_rs1_addr),
        .lookup_rs2_addr     (dec_rs2_addr),
        .lookup_rs1_inflight (rob_rs1_inflight),
        .lookup_rs1_tag      (rob_rs1_tag),
        .lookup_rs1_ready    (rob_rs1_ready),
        .lookup_rs1_value    (rob_rs1_value),
        .lookup_rs2_inflight (rob_rs2_inflight),
        .lookup_rs2_tag      (rob_rs2_tag),
        .lookup_rs2_ready    (rob_rs2_ready),
        .lookup_rs2_value    (rob_rs2_value),

        .flush               (rob_flush),
        .flush_target_pc     (rob_flush_target_pc),
        .halt                (rob_halt),

        .commit_is_branch    (rob_commit_is_branch),
        .commit_is_jump      (rob_commit_is_jump),
        .commit_instr_type   (rob_commit_instr_type),
        .commit_pc           (rob_commit_pc)
    );

    // ================================================================
    // Execution Unit
    // ================================================================
    execution_unit #(
        .ROB_DEPTH (ROB_DEPTH)
    ) u_exec (
        .clk              (clk),
        .rst_n            (rst_n),
        .flush            (rob_flush),

        .issue_valid      (rs_issue_valid),
        .issue_alu_op     (rs_issue_alu_op),
        .issue_instr_type (rs_issue_instr_type),
        .issue_funct3     (rs_issue_funct3),
        .issue_pc         (rs_issue_pc),
        .issue_imm        (rs_issue_imm),
        .issue_uses_imm   (rs_issue_uses_imm),
        .issue_rd_addr    (rs_issue_rd_addr),
        .issue_uses_rd    (rs_issue_uses_rd),
        .issue_is_branch  (rs_issue_is_branch),
        .issue_is_jump    (rs_issue_is_jump),
        .issue_is_jalr    (rs_issue_is_jalr),
        .issue_src1_value (rs_issue_src1_value),
        .issue_src2_value (rs_issue_src2_value),
        .issue_rob_tag    (rs_issue_rob_tag),
        .issue_accept     (exec_issue_accept),

        .cdb_valid         (cdb_valid),
        .cdb_tag           (cdb_tag),
        .cdb_value         (cdb_value),
        .cdb_branch_taken  (cdb_branch_taken),
        .cdb_branch_target (cdb_branch_target)
    );

    // ================================================================
    // Debug outputs
    // ================================================================
    assign dbg_pc             = fetch_pc;
    assign dbg_fetch_valid    = fetch_valid;
    assign dbg_decode_valid   = fetch_valid && dec_valid;
    assign dbg_dispatch_valid = dispatch_en;
    assign dbg_issue_valid    = rs_issue_valid && exec_issue_accept;
    assign dbg_execute_valid  = cdb_valid;
    assign dbg_commit_valid   = rob_commit_valid;
    assign dbg_commit_pc      = rob_commit_pc;
    assign dbg_commit_rd      = rob_commit_rd_addr;
    assign dbg_commit_value   = rob_commit_value;
    assign dbg_commit_uses_rd = rob_commit_uses_rd;
    assign dbg_halt           = halt_any;

endmodule


