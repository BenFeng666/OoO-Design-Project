`timescale 1ns / 1ps

// ============================================================================
// tb_ooo_full.sv — Stronger self-checking TB for the RV32I OoO CPU core
// ============================================================================
//
// Key additions beyond the original TB:
//   1. True OoO proof via execute-completion order vs commit order
//   2. Functional coverage for ROB/RS pressure, flush/commit interplay, drain
//   3. Liveness bound for every fetched instruction (commit or flush <= MAX_LATENCY)
//   4. Sweep-ready ROB/RS parameters with configuration banner in every failure
//   5. Optional randomized mid-execution reset (+RANDOM_RESET)
//   6. 50-cycle post-halt silence check across fetch/issue/execute/commit
//   7. Rich failure diagnostics: commit log, occupancy snapshot, fetch history,
//      flush history, register dump
//   8. Multi-program expectation infrastructure with Program 2 TODO skeleton
//
// REQUIRED DUT ADDITION FOR TRUE OoO PROOF
// ----------------------------------------
// Add at least this new debug port to the DUT:
//   output logic [31:0] dbg_execute_pc;
// driven with the PC of the instruction completing execution / winning the CDB.
//
// Optional additional debug signals if you want tag-based proof/debug:
//   output logic                     dbg_alloc_valid;
//   output logic [31:0]              dbg_alloc_pc;
//   output logic [TAG_W-1:0]         dbg_alloc_tag;
//   output logic [TAG_W-1:0]         dbg_execute_tag;
//
// If your current DUT has not yet been updated, compile the old TB instead.
// This TB is intentionally strict: it will fail rather than claim it proved OoO
// without execute-side visibility.
//
// NOTE ABOUT OCCUPANCY DIAGNOSTICS
// --------------------------------
// If your DUT exposes exact occupancy counters, define these macros before
// compilation and point them at the correct hierarchical names:
//   `define TB_HAS_OCCUPANCY_REFS
//   `define TB_ROB_OCC u_dut.rob_count
//   `define TB_RS_OCC  u_dut.rs_count
// Otherwise the TB will still print rs_full / rob_full and mark exact occupancy
// as TODO in diagnostics.
// ============================================================================

module tb #(
    parameter int    CLK_PERIOD        = 10,
    parameter int    TIMEOUT_CYCLES    = 4000,
    parameter int    ROM_DEPTH         = 64,
    parameter int    ROB_DEPTH         = 4,
    parameter int    RS_DEPTH          = 4,
    parameter int    MAX_LATENCY       = 30,
    parameter int    POST_HALT_QUIET   = 50,
    parameter int    PROGRAM_SEL       = 1,
    parameter string MEM_FILE_P1       = "program.hex",
    parameter string MEM_FILE_P2       = "program2.hex",
    parameter int    MAX_EXPECTED_COMMITS = 32,
    parameter int    MAX_WRONGPATH_PCS    = 8,
    parameter int    NUM_CHECK_REGS       = 32
);

    localparam int TAG_W = (ROB_DEPTH <= 2) ? 1 : $clog2(ROB_DEPTH);

    // ================================================================
    // Clock / reset
    // ================================================================
    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ================================================================
    // DUT debug interface
    // ================================================================
    logic [31:0] dbg_pc;
    logic        dbg_fetch_valid;
    logic        dbg_decode_valid;
    logic        dbg_dispatch_valid;
    logic        dbg_issue_valid;
    logic        dbg_execute_valid;
    logic [31:0] dbg_execute_pc;   // NEW: add this to DUT
    logic [TAG_W-1:0] dbg_execute_tag; // optional / debug only
    logic        dbg_commit_valid;
    logic [31:0] dbg_commit_pc;
    logic [4:0]  dbg_commit_rd;
    logic [31:0] dbg_commit_value;
    logic        dbg_commit_uses_rd;
    logic        dbg_halt;

    // Optional tag-allocation debug (leave unconnected in DUT if unused)
    logic        dbg_alloc_valid;
    logic [31:0] dbg_alloc_pc;
    logic [TAG_W-1:0] dbg_alloc_tag;

    // ================================================================
    // DUT instantiation
    // ================================================================
    ooo_cpu_core #(
        .ROM_DEPTH (ROM_DEPTH),
        .ROB_DEPTH (ROB_DEPTH),
        .RS_DEPTH  (RS_DEPTH),
        .MEM_FILE  ((PROGRAM_SEL == 2) ? MEM_FILE_P2 : MEM_FILE_P1)
    ) u_dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .dbg_pc             (dbg_pc),
        .dbg_fetch_valid    (dbg_fetch_valid),
        .dbg_decode_valid   (dbg_decode_valid),
        .dbg_dispatch_valid (dbg_dispatch_valid),
        .dbg_issue_valid    (dbg_issue_valid),
        .dbg_execute_valid  (dbg_execute_valid),
        .dbg_execute_pc     (dbg_execute_pc),
        .dbg_execute_tag    (dbg_execute_tag),
        .dbg_alloc_valid    (dbg_alloc_valid),
        .dbg_alloc_pc       (dbg_alloc_pc),
        .dbg_alloc_tag      (dbg_alloc_tag),
        .dbg_commit_valid   (dbg_commit_valid),
        .dbg_commit_pc      (dbg_commit_pc),
        .dbg_commit_rd      (dbg_commit_rd),
        .dbg_commit_value   (dbg_commit_value),
        .dbg_commit_uses_rd (dbg_commit_uses_rd),
        .dbg_halt           (dbg_halt)
    );

    // ================================================================
    // Helper typedefs / tracking
    // ================================================================
    typedef struct {
        int unsigned run_id;
        int unsigned global_cycle;
        int unsigned run_cycle;
        logic [31:0] pc;
        logic [4:0]  rd;
        logic [31:0] value;
        bit          uses_rd;
    } commit_evt_t;

    typedef struct {
        logic [31:0] pc;
        int unsigned fetch_cycle;
        int unsigned run_id;
    } inflight_fetch_t;

    commit_evt_t      commit_log[$];
    string            commit_log_str[$];
    string            flush_history[$];
    logic [31:0]      last_fetch_pcs[$];
    inflight_fetch_t  inflight_fetch_q[$];
    logic [31:0]      exec_seq[$];
    logic [31:0]      commit_seq[$];

    // ================================================================
    // Expected sequences / values (selected by PROGRAM_SEL)
    // ================================================================
    int               active_expected_commits;
    int               active_num_wrongpath_pcs;
    int               active_num_check_regs;
    bit               program_expectations_ready;
    bit               expect_true_ooo_proof;
    bit               exp_wrongpath_seen    [0:MAX_WRONGPATH_PCS-1];
    bit               exp_wrongpath_require_fetch [0:MAX_WRONGPATH_PCS-1];
    logic [31:0]      exp_wrongpath_pcs     [0:MAX_WRONGPATH_PCS-1];
    logic [31:0]      exp_commit_pc         [0:MAX_EXPECTED_COMMITS-1];
    logic [4:0]       exp_commit_rd         [0:MAX_EXPECTED_COMMITS-1];
    logic [31:0]      exp_commit_value      [0:MAX_EXPECTED_COMMITS-1];
    bit               exp_commit_uses_rd    [0:MAX_EXPECTED_COMMITS-1];
    logic [31:0]      exp_regs              [0:NUM_CHECK_REGS-1];

    // Associative maps for execute/commit order proof
    int exec_order_by_pc [logic [31:0]];
    int commit_order_by_pc [logic [31:0]];

    // ================================================================
    // Counters / state
    // ================================================================
    int unsigned global_cycle;
    int unsigned run_cycle;
    int unsigned run_id;
    int unsigned commit_index;
    int unsigned flush_count;
    int unsigned fatal_errors;
    int unsigned rob_full_stall_hits;
    int unsigned rs_full_stall_hits;
    int unsigned b2b_commit_hits;
    int unsigned commit_and_flush_hits;
    int unsigned fetch_after_flush_hits;
    int unsigned drain_resume_hits;
    int unsigned random_reset_cycle;
    int unsigned random_reset_width;

    bit prev_commit_valid;
    bit prev_flush;
    bit prev_fetch_valid;
    bit saw_idle_window;
    bit random_reset_en;
    bit random_reset_done;
    bit stable_halt_seen;
    bit have_execute_pc_debug;

    logic [31:0] prev_fetch_pc;
    logic [31:0] last_flush_target;
    logic [31:0] last_flush_targets[$];

    // ================================================================
    // Configuration helpers
    // ================================================================
    function automatic string cfg_string();
        return $sformatf("[ROB=%0d RS=%0d MAX_LAT=%0d PROGRAM=%0d MEM=%s]",
                         ROB_DEPTH, RS_DEPTH, MAX_LATENCY, PROGRAM_SEL,
                         (PROGRAM_SEL == 2) ? MEM_FILE_P2 : MEM_FILE_P1);
    endfunction

    function automatic bit pc_is_expected_commit(input logic [31:0] pc);
        bit found;
        found = 1'b0;
        for (int i = 0; i < active_expected_commits; i++) begin
            if (exp_commit_pc[i] == pc)
                found = 1'b1;
        end
        return found;
    endfunction

    function automatic bit pc_is_wrongpath(input logic [31:0] pc);
        bit found;
        found = 1'b0;
        for (int i = 0; i < active_num_wrongpath_pcs; i++) begin
            if (exp_wrongpath_pcs[i] == pc)
                found = 1'b1;
        end
        return found;
    endfunction

    function automatic int find_oldest_inflight_by_pc(input logic [31:0] pc);
        for (int i = 0; i < inflight_fetch_q.size(); i++) begin
            if (inflight_fetch_q[i].pc == pc)
                return i;
        end
        return -1;
    endfunction

    function automatic bit any_activity_now();
        return (dbg_fetch_valid || dbg_decode_valid || dbg_dispatch_valid ||
                dbg_issue_valid || dbg_execute_valid || dbg_commit_valid);
    endfunction

    function automatic bit all_idle_now();
        return !any_activity_now();
    endfunction

    // ================================================================
    // Diagnostics helpers
    // ================================================================
    task automatic dump_commit_log();
        $display("--- Commit log so far (%0d entries) ---", commit_log_str.size());
        foreach (commit_log_str[i])
            $display("  %s", commit_log_str[i]);
        if (commit_log_str.size() == 0)
            $display("  <empty>");
        $display("--------------------------------------");
    endtask

    task automatic dump_fetch_history();
        $display("--- Last %0d fetch PCs ---", last_fetch_pcs.size());
        foreach (last_fetch_pcs[i])
            $display("  fetch_hist[%0d] = 0x%08X", i, last_fetch_pcs[i]);
        if (last_fetch_pcs.size() == 0)
            $display("  <empty>");
        $display("--------------------------");
    endtask

    task automatic dump_flush_history();
        $display("--- Flush history (%0d entries) ---", flush_history.size());
        foreach (flush_history[i])
            $display("  %s", flush_history[i]);
        if (flush_history.size() == 0)
            $display("  <empty>");
        $display("-------------------------------");
    endtask

    task automatic dump_occupancy();
`ifdef TB_HAS_OCCUPANCY_REFS
        $display("--- Occupancy snapshot ---");
        $display("  ROB occ = %0d / %0d", `TB_ROB_OCC, ROB_DEPTH);
        $display("  RS  occ = %0d / %0d", `TB_RS_OCC,  RS_DEPTH);
        $display("  ROB full=%0b  RS full=%0b", u_dut.rob_full, u_dut.rs_full);
        $display("--------------------------");
`else
        $display("--- Occupancy snapshot ---");
        $display("  TODO: define `TB_HAS_OCCUPANCY_REFS, `TB_ROB_OCC, `TB_RS_OCC");
        $display("  ROB full=%0b / depth=%0d", u_dut.rob_full, ROB_DEPTH);
        $display("  RS  full=%0b / depth=%0d", u_dut.rs_full,  RS_DEPTH);
        $display("--------------------------");
`endif
    endtask

    task automatic dump_registers();
        $display("--- Architectural Register Dump ---");
        for (int i = 0; i < NUM_CHECK_REGS; i++) begin
            if (i == 0)
                $display("  x%-2d = 0x%08X  (hardwired zero)", i, 32'h0);
            else
                $display("  x%-2d = 0x%08X", i, u_dut.u_rf.regs[i]);
        end
        $display("-----------------------------------");
    endtask

    task automatic tb_fatal(input string reason);
        $display("");
        $display("============================================================");
        $display("TB FATAL %s", cfg_string());
        $display("Reason: %s", reason);
        $display("Global cycle=%0d  Run cycle=%0d  Run id=%0d  Commit index=%0d  Flush count=%0d",
                 global_cycle, run_cycle, run_id, commit_index, flush_count);
        dump_commit_log();
        dump_occupancy();
        dump_fetch_history();
        dump_flush_history();
        dump_registers();
        $display("============================================================");
        $fatal(1, "%s %s", reason, cfg_string());
    endtask

    // ================================================================
    // Expectation loading
    // ================================================================
    task automatic clear_expectations();
        active_expected_commits   = 0;
        active_num_wrongpath_pcs  = 0;
        active_num_check_regs     = NUM_CHECK_REGS;
        program_expectations_ready = 1'b0;
        expect_true_ooo_proof     = 1'b1;

        for (int i = 0; i < MAX_EXPECTED_COMMITS; i++) begin
            exp_commit_pc[i]       = '0;
            exp_commit_rd[i]       = '0;
            exp_commit_value[i]    = '0;
            exp_commit_uses_rd[i]  = 1'b0;
        end
        for (int i = 0; i < MAX_WRONGPATH_PCS; i++) begin
            exp_wrongpath_pcs[i]           = '0;
            exp_wrongpath_seen[i]          = 1'b0;
            exp_wrongpath_require_fetch[i] = 1'b0;
        end
        for (int i = 0; i < NUM_CHECK_REGS; i++)
            exp_regs[i] = '0;
    endtask

    task automatic load_program1_expectations();
        clear_expectations();
        program_expectations_ready = 1'b1;
        active_expected_commits    = 14;
        active_num_wrongpath_pcs   = 1;
        active_num_check_regs      = 15;

        // Committed PC / rd / value sequence
        exp_commit_pc[0]  = 32'h00000000; exp_commit_rd[0]  = 5'd1;  exp_commit_value[0]  = 32'h00000005; exp_commit_uses_rd[0]  = 1'b1;
        exp_commit_pc[1]  = 32'h00000004; exp_commit_rd[1]  = 5'd2;  exp_commit_value[1]  = 32'h0000000A; exp_commit_uses_rd[1]  = 1'b1;
        exp_commit_pc[2]  = 32'h00000008; exp_commit_rd[2]  = 5'd3;  exp_commit_value[2]  = 32'h0000000F; exp_commit_uses_rd[2]  = 1'b1;
        exp_commit_pc[3]  = 32'h0000000C; exp_commit_rd[3]  = 5'd4;  exp_commit_value[3]  = 32'h00000003; exp_commit_uses_rd[3]  = 1'b1;
        exp_commit_pc[4]  = 32'h00000010; exp_commit_rd[4]  = 5'd5;  exp_commit_value[4]  = 32'h0000000C; exp_commit_uses_rd[4]  = 1'b1;
        exp_commit_pc[5]  = 32'h00000014; exp_commit_rd[5]  = 5'd6;  exp_commit_value[5]  = 32'h0000000C; exp_commit_uses_rd[5]  = 1'b1;
        exp_commit_pc[6]  = 32'h00000018; exp_commit_rd[6]  = 5'd0;  exp_commit_value[6]  = 32'h00000000; exp_commit_uses_rd[6]  = 1'b0;
        exp_commit_pc[7]  = 32'h00000020; exp_commit_rd[7]  = 5'd8;  exp_commit_value[7]  = 32'hDEADB000; exp_commit_uses_rd[7]  = 1'b1;
        exp_commit_pc[8]  = 32'h00000024; exp_commit_rd[8]  = 5'd9;  exp_commit_value[8]  = 32'h0000000F; exp_commit_uses_rd[8]  = 1'b1;
        exp_commit_pc[9]  = 32'h00000028; exp_commit_rd[9]  = 5'd10; exp_commit_value[9]  = 32'h00000000; exp_commit_uses_rd[9]  = 1'b1;
        exp_commit_pc[10] = 32'h0000002C; exp_commit_rd[10] = 5'd11; exp_commit_value[10] = 32'h00000001; exp_commit_uses_rd[10] = 1'b1;
        exp_commit_pc[11] = 32'h00000030; exp_commit_rd[11] = 5'd12; exp_commit_value[11] = 32'h00000028; exp_commit_uses_rd[11] = 1'b1;
        exp_commit_pc[12] = 32'h00000034; exp_commit_rd[12] = 5'd13; exp_commit_value[12] = 32'h000000FF; exp_commit_uses_rd[12] = 1'b1;
        exp_commit_pc[13] = 32'h00000038; exp_commit_rd[13] = 5'd14; exp_commit_value[13] = 32'h0000000F; exp_commit_uses_rd[13] = 1'b1;

        // Wrong-path fetch expectation
        exp_wrongpath_pcs[0]           = 32'h0000001C;
        exp_wrongpath_require_fetch[0] = 1'b1;

        // Final register values x0..x14
        exp_regs[0]  = 32'h00000000;
        exp_regs[1]  = 32'h00000005;
        exp_regs[2]  = 32'h0000000A;
        exp_regs[3]  = 32'h0000000F;
        exp_regs[4]  = 32'h00000003;
        exp_regs[5]  = 32'h0000000C;
        exp_regs[6]  = 32'h0000000C;
        exp_regs[7]  = 32'h00000000;
        exp_regs[8]  = 32'hDEADB000;
        exp_regs[9]  = 32'h0000000F;
        exp_regs[10] = 32'h00000000;
        exp_regs[11] = 32'h00000001;
        exp_regs[12] = 32'h00000028;
        exp_regs[13] = 32'h000000FF;
        exp_regs[14] = 32'h0000000F;
    endtask

    task automatic load_program2_expectations();
        clear_expectations();

        // -----------------------------------------------------------------
        // TODO(USER): Fill in Program 2 once program2.hex exists.
        // Suggested structure for program2.hex:
        //   - Branch A not taken (wrong-path PC_A should NOT be flushed)
        //   - Branch B taken     (wrong-path PC_B should be fetched then flushed)
        //   - At least one pair of independent younger instructions that can
        //     complete before an older long-latency instruction.
        //
        // Example fields to fill:
        //   active_expected_commits    = <N>;
        //   active_num_wrongpath_pcs   = 2;
        //   exp_wrongpath_pcs[0]       = <wrong path PC for taken branch>;
        //   exp_wrongpath_require_fetch[0] = 1'b1;
        //   exp_wrongpath_pcs[1]       = <other branch shadow PC if desired>;
        //   exp_commit_pc[k]           = <commit PC order>;
        //   exp_commit_rd[k]           = <rd>;
        //   exp_commit_value[k]        = <value>;
        //   exp_commit_uses_rd[k]      = <1/0>;
        //   exp_regs[r]                = <final architectural state>;
        //
        // Until these are filled, PROGRAM_SEL=2 will intentionally fail fast.
        // -----------------------------------------------------------------

        program_expectations_ready = 1'b0;
        active_expected_commits    = 0;
        active_num_wrongpath_pcs   = 0;
        active_num_check_regs      = 0;
        expect_true_ooo_proof      = 1'b1;
    endtask

    task automatic load_active_program_expectations();
        case (PROGRAM_SEL)
            1: load_program1_expectations();
            2: load_program2_expectations();
            default: begin
                clear_expectations();
                program_expectations_ready = 1'b0;
            end
        endcase
    endtask

    // ================================================================
    // Reset / run-state rearm
    // ================================================================
    task automatic clear_run_state();
        commit_index           = 0;
        flush_count            = 0;
        run_cycle              = 0;
        prev_commit_valid      = 1'b0;
        prev_flush             = 1'b0;
        prev_fetch_valid       = 1'b0;
        prev_fetch_pc          = '0;
        saw_idle_window        = 1'b0;
        stable_halt_seen       = 1'b0;
        last_flush_target      = '0;
        last_flush_targets.delete();
        inflight_fetch_q.delete();
        exec_seq.delete();
        commit_seq.delete();
        exec_order_by_pc.delete();
        commit_order_by_pc.delete();
        for (int i = 0; i < MAX_WRONGPATH_PCS; i++)
            exp_wrongpath_seen[i] = 1'b0;
    endtask

    always @(negedge rst_n) begin
        clear_run_state();
    end

    always_ff @(posedge clk) begin
        global_cycle <= global_cycle + 1;
        if (rst_n)
            run_cycle <= run_cycle + 1;
    end

    always @(posedge rst_n) begin
        run_id <= run_id + 1;
        $display("[global %0d] Reset released for run_id=%0d %s",
                 global_cycle, run_id + 1, cfg_string());
    end

    // ================================================================
    // Coverage events and covergroup
    // ================================================================
    bit rob_full_stall_ev;
    bit rs_full_stall_ev;
    bit b2b_commit_ev;
    bit commit_and_flush_ev;
    bit fetch_after_flush_ev;
    bit drain_resume_ev;

    covergroup cg_micro with function sample(
        bit rob_full_stall_ev_i,
        bit rs_full_stall_ev_i,
        bit b2b_commit_ev_i,
        bit commit_and_flush_ev_i,
        bit fetch_after_flush_ev_i,
        bit drain_resume_ev_i
    );
        option.per_instance = 1;
        rob_full_stall_cp   : coverpoint rob_full_stall_ev_i   { bins hit = {1'b1}; }
        rs_full_stall_cp    : coverpoint rs_full_stall_ev_i    { bins hit = {1'b1}; }
        b2b_commit_cp       : coverpoint b2b_commit_ev_i       { bins hit = {1'b1}; }
        commit_flush_cp     : coverpoint commit_and_flush_ev_i { bins hit = {1'b1}; }
        fetch_after_flush_cp: coverpoint fetch_after_flush_ev_i{ bins hit = {1'b1}; }
        drain_resume_cp     : coverpoint drain_resume_ev_i     { bins hit = {1'b1}; }
    endgroup

    cg_micro micro_cov = new();

    // ================================================================
    // Event derivation / coverage counters
    // ================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        bit flush_now;
        bit new_fetch_now;
        if (!rst_n) begin
            rob_full_stall_hits   <= 0;
            rs_full_stall_hits    <= 0;
            b2b_commit_hits       <= 0;
            commit_and_flush_hits <= 0;
            fetch_after_flush_hits<= 0;
            drain_resume_hits     <= 0;
            rob_full_stall_ev     <= 1'b0;
            rs_full_stall_ev      <= 1'b0;
            b2b_commit_ev         <= 1'b0;
            commit_and_flush_ev   <= 1'b0;
            fetch_after_flush_ev  <= 1'b0;
            drain_resume_ev       <= 1'b0;
        end else begin
            flush_now    = u_dut.rob_flush;
            new_fetch_now = dbg_fetch_valid && (!prev_fetch_valid || (dbg_pc != prev_fetch_pc) || prev_flush);

            rob_full_stall_ev    <= (u_dut.rob_full && dbg_decode_valid && !dbg_dispatch_valid);
            rs_full_stall_ev     <= (u_dut.rs_full  && dbg_decode_valid && !dbg_dispatch_valid);
            b2b_commit_ev        <= (prev_commit_valid && dbg_commit_valid);
            commit_and_flush_ev  <= (dbg_commit_valid && flush_now);
            fetch_after_flush_ev <= (prev_flush && new_fetch_now && (dbg_pc == last_flush_target));
            drain_resume_ev      <= (saw_idle_window && any_activity_now());

            if (u_dut.rob_full && dbg_decode_valid && !dbg_dispatch_valid)
                rob_full_stall_hits <= rob_full_stall_hits + 1;
            if (u_dut.rs_full && dbg_decode_valid && !dbg_dispatch_valid)
                rs_full_stall_hits <= rs_full_stall_hits + 1;
            if (prev_commit_valid && dbg_commit_valid)
                b2b_commit_hits <= b2b_commit_hits + 1;
            if (dbg_commit_valid && flush_now)
                commit_and_flush_hits <= commit_and_flush_hits + 1;
            if (prev_flush && new_fetch_now && (dbg_pc == last_flush_target))
                fetch_after_flush_hits <= fetch_after_flush_hits + 1;
            if (saw_idle_window && any_activity_now())
                drain_resume_hits <= drain_resume_hits + 1;

            micro_cov.sample(
                (u_dut.rob_full && dbg_decode_valid && !dbg_dispatch_valid),
                (u_dut.rs_full  && dbg_decode_valid && !dbg_dispatch_valid),
                (prev_commit_valid && dbg_commit_valid),
                (dbg_commit_valid && flush_now),
                (prev_flush && new_fetch_now && (dbg_pc == last_flush_target)),
                (saw_idle_window && any_activity_now())
            );

            if (all_idle_now())
                saw_idle_window <= 1'b1;
            else if (saw_idle_window && any_activity_now())
                saw_idle_window <= 1'b0;

            prev_commit_valid <= dbg_commit_valid;
            prev_flush        <= flush_now;
            prev_fetch_valid  <= dbg_fetch_valid;
            prev_fetch_pc     <= dbg_pc;
        end
    end

    // ================================================================
    // Fetch tracking / liveness window / wrong-path fetch evidence
    // ================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        bit new_fetch_now;
        if (!rst_n) begin
            last_fetch_pcs.delete();
        end else begin
            new_fetch_now = dbg_fetch_valid && (!prev_fetch_valid || (dbg_pc != prev_fetch_pc) || prev_flush);

            if (new_fetch_now) begin
                inflight_fetch_t f;
                f.pc         = dbg_pc;
                f.fetch_cycle = run_cycle;
                f.run_id     = run_id;
                inflight_fetch_q.push_back(f);

                last_fetch_pcs.push_back(dbg_pc);
                if (last_fetch_pcs.size() > 5)
                    void'(last_fetch_pcs.pop_front());

                for (int i = 0; i < active_num_wrongpath_pcs; i++) begin
                    if (dbg_pc == exp_wrongpath_pcs[i])
                        exp_wrongpath_seen[i] <= 1'b1;
                end
            end

            // Liveness timeout: every fetched instruction must either commit or
            // get flushed within MAX_LATENCY cycles.
            for (int i = 0; i < inflight_fetch_q.size(); i++) begin
                if ((run_cycle - inflight_fetch_q[i].fetch_cycle) > MAX_LATENCY) begin
                    tb_fatal($sformatf(
                        "Fetched instruction stuck beyond MAX_LATENCY: pc=0x%08X age=%0d cycles %s",
                        inflight_fetch_q[i].pc,
                        run_cycle - inflight_fetch_q[i].fetch_cycle,
                        cfg_string()
                    ));
                end
            end
        end
    end

    // ================================================================
    // Execute completion log (needed to prove true OoO)
    // ================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            have_execute_pc_debug <= 1'b0;
        end else begin
            if (dbg_execute_valid) begin
                have_execute_pc_debug <= 1'b1;
                if (!exec_order_by_pc.exists(dbg_execute_pc)) begin
                    exec_order_by_pc[dbg_execute_pc] = exec_seq.size();
                    exec_seq.push_back(dbg_execute_pc);
                end
            end
        end
    end

    // ================================================================
    // Flush tracking and wrong-path cleanup
    // ================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // cleared centrally
        end else if (u_dut.rob_flush) begin
            string s;
            flush_count      <= flush_count + 1;
            last_flush_target<= u_dut.rob_flush_target_pc;
            last_flush_targets.push_back(u_dut.rob_flush_target_pc);
            s = $sformatf("[g%0d r%0d] FLUSH #%0d target=0x%08X",
                          global_cycle, run_cycle, flush_count + 1,
                          u_dut.rob_flush_target_pc);
            flush_history.push_back(s);
            $display("%s", s);

            // Conservative wrong-path cleanup:
            // remove fetched entries whose PCs are not part of the expected
            // commit set for the selected program. This is sufficient for the
            // straight-line directed programs used here and intentionally marked
            // as TODO for looping / repeated-PC programs.
            for (int i = inflight_fetch_q.size()-1; i >= 0; i--) begin
                if (!pc_is_expected_commit(inflight_fetch_q[i].pc))
                    inflight_fetch_q.delete(i);
            end
        end
    end

    // ================================================================
    // Commit tracking, exact commit checks, and inflight retirement
    // ================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // cleared centrally
        end else if (dbg_commit_valid) begin
            commit_evt_t c;
            string s;
            int inflight_idx;

            if (commit_index >= active_expected_commits) begin
                tb_fatal($sformatf(
                    "Too many commits: commit_index=%0d got pc=0x%08X %s",
                    commit_index, dbg_commit_pc, cfg_string()));
            end

            if (dbg_commit_pc !== exp_commit_pc[commit_index]) begin
                tb_fatal($sformatf(
                    "Commit PC mismatch at commit #%0d: got 0x%08X expected 0x%08X %s",
                    commit_index, dbg_commit_pc, exp_commit_pc[commit_index], cfg_string()));
            end

            if (dbg_commit_uses_rd !== exp_commit_uses_rd[commit_index]) begin
                tb_fatal($sformatf(
                    "Commit uses_rd mismatch at pc=0x%08X: got %0b expected %0b %s",
                    dbg_commit_pc, dbg_commit_uses_rd,
                    exp_commit_uses_rd[commit_index], cfg_string()));
            end

            if (exp_commit_uses_rd[commit_index]) begin
                if (dbg_commit_rd !== exp_commit_rd[commit_index]) begin
                    tb_fatal($sformatf(
                        "Commit rd mismatch at pc=0x%08X: got x%0d expected x%0d %s",
                        dbg_commit_pc, dbg_commit_rd,
                        exp_commit_rd[commit_index], cfg_string()));
                end
                if (dbg_commit_value !== exp_commit_value[commit_index]) begin
                    tb_fatal($sformatf(
                        "Commit value mismatch at pc=0x%08X: got 0x%08X expected 0x%08X %s",
                        dbg_commit_pc, dbg_commit_value,
                        exp_commit_value[commit_index], cfg_string()));
                end
            end

            if (commit_order_by_pc.exists(dbg_commit_pc)) begin
                tb_fatal($sformatf(
                    "Duplicate commit seen for pc=0x%08X %s",
                    dbg_commit_pc, cfg_string()));
            end

            commit_order_by_pc[dbg_commit_pc] = commit_seq.size();
            commit_seq.push_back(dbg_commit_pc);

            inflight_idx = find_oldest_inflight_by_pc(dbg_commit_pc);
            if (inflight_idx >= 0)
                inflight_fetch_q.delete(inflight_idx);

            c.run_id       = run_id;
            c.global_cycle = global_cycle;
            c.run_cycle    = run_cycle;
            c.pc           = dbg_commit_pc;
            c.rd           = dbg_commit_rd;
            c.value        = dbg_commit_value;
            c.uses_rd      = dbg_commit_uses_rd;
            commit_log.push_back(c);

            if (dbg_commit_uses_rd)
                s = $sformatf("[g%0d r%0d run=%0d] COMMIT #%0d pc=0x%08X rd=x%0d val=0x%08X",
                              global_cycle, run_cycle, run_id, commit_index,
                              dbg_commit_pc, dbg_commit_rd, dbg_commit_value);
            else
                s = $sformatf("[g%0d r%0d run=%0d] COMMIT #%0d pc=0x%08X (no-rd)",
                              global_cycle, run_cycle, run_id, commit_index,
                              dbg_commit_pc);
            commit_log_str.push_back(s);

            commit_index <= commit_index + 1;
        end
    end

    // ================================================================
    // Optional cycle trace
    // ================================================================
    always @(posedge clk) begin
        if (rst_n) begin
            $write("[g%4d r%4d] ", global_cycle, run_cycle);
            if (dbg_fetch_valid)
                $write("F:0x%04X ", dbg_pc);
            else
                $write("F:---- ");
            if (dbg_decode_valid)
                $write("D:ok ");
            else if (dbg_fetch_valid)
                $write("D:IL ");
            else
                $write("D:-- ");
            if (dbg_dispatch_valid)
                $write("DISP ");
            else
                $write("---- ");
            if (dbg_issue_valid)
                $write("ISS ");
            else
                $write("--- ");
            if (dbg_execute_valid)
                $write("EX:pc=0x%04X tag=%0d ", dbg_execute_pc, dbg_execute_tag);
            else
                $write("EX:------      ");
            if (dbg_commit_valid) begin
                if (dbg_commit_uses_rd)
                    $write("CMT:#%0d pc=0x%04X x%0d=0x%08X ",
                           commit_index, dbg_commit_pc, dbg_commit_rd,
                           dbg_commit_value);
                else
                    $write("CMT:#%0d pc=0x%04X (no-rd) ",
                           commit_index, dbg_commit_pc);
            end else begin
                $write("CMT:--- ");
            end
            if (dbg_halt)
                $write("HALT ");
            $write("[RS_full=%0b ROB_full=%0b]", u_dut.rs_full, u_dut.rob_full);
            $display("");
        end
    end

    // ================================================================
    // Final check tasks
    // ================================================================
    task automatic check_halt_reason();
        $display("--- Check: Halt Reason ---");
        if (!u_dut.rob_halt)
            tb_fatal($sformatf("CPU did not halt due to ROB/ECALL %s", cfg_string()));
        if (u_dut.illegal_halt)
            tb_fatal($sformatf("CPU halted due to illegal instruction, not ECALL %s", cfg_string()));
        $display("  Halt reason OK (ROB halt asserted, illegal_halt deasserted)");
        $display("");
    endtask

    task automatic check_flush_behavior();
        $display("--- Check: Flush Behavior ---");
        if (PROGRAM_SEL == 1) begin
            if (flush_count == 0)
                tb_fatal($sformatf("No branch flush observed; expected taken branch to 0x20 %s", cfg_string()));
            if (last_flush_target !== 32'h00000020)
                tb_fatal($sformatf("Last flush target mismatch: got 0x%08X expected 0x00000020 %s",
                                   last_flush_target, cfg_string()));
            if (!exp_wrongpath_seen[0])
                tb_fatal($sformatf("Wrong-path PC 0x0000001C was never fetched before flush %s", cfg_string()));
        end else begin
            $display("  PROGRAM_SEL=%0d uses programmable flush expectations.", PROGRAM_SEL);
        end
        $display("  Flush count=%0d  last target=0x%08X", flush_count, last_flush_target);
        $display("");
    endtask

    task automatic check_commit_count();
        $display("--- Check: Commit Count ---");
        if (commit_index != active_expected_commits)
            tb_fatal($sformatf("Commit count mismatch: got %0d expected %0d %s",
                               commit_index, active_expected_commits, cfg_string()));
        $display("  Commit count OK: %0d", commit_index);
        $display("");
    endtask

    task automatic check_registers();
        logic [31:0] actual;
        $display("--- Check: Final Registers ---");
        for (int i = 0; i < active_num_check_regs; i++) begin
            if (i == 0)
                actual = 32'h0;
            else
                actual = u_dut.u_rf.regs[i];

            if (actual !== exp_regs[i]) begin
                tb_fatal($sformatf(
                    "Register mismatch x%0d: got 0x%08X expected 0x%08X %s",
                    i, actual, exp_regs[i], cfg_string()));
            end
            $display("  x%-2d = 0x%08X OK", i, actual);
        end
        $display("");
    endtask

    task automatic check_true_ooo();
        bit found_reordered_pair;
        logic [31:0] older_pc;
        logic [31:0] younger_pc;
        found_reordered_pair = 1'b0;

        $display("--- Check: True Out-of-Order Execution Proof ---");

        if (!have_execute_pc_debug)
            tb_fatal($sformatf(
                "No dbg_execute_pc activity observed; cannot prove true OoO completion order %s",
                cfg_string()));

        for (int i = 0; i < active_expected_commits; i++) begin
            if (!exec_order_by_pc.exists(exp_commit_pc[i])) begin
                tb_fatal($sformatf(
                    "Missing execute-completion record for committed pc=0x%08X %s",
                    exp_commit_pc[i], cfg_string()));
            end
        end

        for (int i = 0; i < active_expected_commits; i++) begin
            for (int j = i + 1; j < active_expected_commits; j++) begin
                older_pc   = exp_commit_pc[i];
                younger_pc = exp_commit_pc[j];
                if (exec_order_by_pc[older_pc] > exec_order_by_pc[younger_pc]) begin
                    found_reordered_pair = 1'b1;
                    $display("  Found reordered execute pair:");
                    $display("    Older committed first : PC=0x%08X commit_idx=%0d exec_idx=%0d",
                             older_pc, i, exec_order_by_pc[older_pc]);
                    $display("    Younger committed later: PC=0x%08X commit_idx=%0d exec_idx=%0d",
                             younger_pc, j, exec_order_by_pc[younger_pc]);
                    break;
                end
            end
            if (found_reordered_pair)
                break;
        end

        if (expect_true_ooo_proof && !found_reordered_pair)
            tb_fatal($sformatf(
                "No execute/commit inversion found. Commit order stayed in program order, but execute completion also appeared in program order, so true OoO is NOT proven %s",
                cfg_string()));

        $display("  True OoO proof OK");
        $display("");
    endtask

    task automatic check_coverage();
        real cov_pct;
        cov_pct = micro_cov.get_coverage();
        $display("--- Coverage Summary ---");
        $display("  Covergroup aggregate coverage: %0.2f%%", cov_pct);
        $display("  rob_full_stall_hits    = %0d", rob_full_stall_hits);
        $display("  rs_full_stall_hits     = %0d", rs_full_stall_hits);
        $display("  b2b_commit_hits        = %0d", b2b_commit_hits);
        $display("  commit_and_flush_hits  = %0d", commit_and_flush_hits);
        $display("  fetch_after_flush_hits = %0d", fetch_after_flush_hits);
        $display("  drain_resume_hits      = %0d", drain_resume_hits);

        if (rob_full_stall_hits    == 0) tb_fatal($sformatf("Coverage miss: ROB-full stall bin had zero hits %s", cfg_string()));
        if (rs_full_stall_hits     == 0) tb_fatal($sformatf("Coverage miss: RS-full stall bin had zero hits %s", cfg_string()));
        if (b2b_commit_hits        == 0) tb_fatal($sformatf("Coverage miss: back-to-back commit bin had zero hits %s", cfg_string()));
        if (commit_and_flush_hits  == 0) tb_fatal($sformatf("Coverage miss: commit+flush same-cycle bin had zero hits %s", cfg_string()));
        if (fetch_after_flush_hits == 0) tb_fatal($sformatf("Coverage miss: fetch-immediately-after-flush bin had zero hits %s", cfg_string()));
        if (drain_resume_hits      == 0) tb_fatal($sformatf("Coverage miss: pipeline-drain-then-resume bin had zero hits %s", cfg_string()));
        $display("");
    endtask

    task automatic check_post_halt_silence();
        $display("--- Check: Post-halt silence for %0d cycles ---", POST_HALT_QUIET);
        repeat (POST_HALT_QUIET) begin
            @(posedge clk);
            if (dbg_commit_valid)
                tb_fatal($sformatf("Commit occurred after halt during quiet window %s", cfg_string()));
            if (dbg_fetch_valid)
                tb_fatal($sformatf("Fetch remained active after halt during quiet window %s", cfg_string()));
            if (dbg_issue_valid)
                tb_fatal($sformatf("Issue remained active after halt during quiet window %s", cfg_string()));
            if (dbg_execute_valid)
                tb_fatal($sformatf("Execute remained active after halt during quiet window %s", cfg_string()));
        end
        $display("  Pipeline quiet window passed");
        $display("");
    endtask

    // ================================================================
    // Optional randomized reset injection
    // ================================================================
    initial begin
        random_reset_done = 1'b0;
        wait (random_reset_en !== 1'bx);
        if (random_reset_en) begin
            random_reset_cycle = $urandom_range(10, 50);
            random_reset_width = $urandom_range(1, 3);
            wait (rst_n === 1'b1);
            wait (run_cycle >= random_reset_cycle);
            @(posedge clk);
            if (!dbg_halt && !random_reset_done) begin
                $display("[global %0d] RANDOM_RESET asserting low for %0d cycles at run_cycle=%0d %s",
                         global_cycle, random_reset_width, run_cycle, cfg_string());
                rst_n = 1'b0;
                repeat (random_reset_width) @(posedge clk);
                rst_n = 1'b1;
                random_reset_done = 1'b1;
                $display("[global %0d] RANDOM_RESET released %s",
                         global_cycle, cfg_string());
            end
        end
    end

    // ================================================================
    // Main test sequence
    // ================================================================
    initial begin
        $dumpfile("tb_ooo_full.vcd");
        $dumpvars(0, tb);

        global_cycle            = 0;
        run_cycle               = 0;
        run_id                  = 0;
        fatal_errors            = 0;
        have_execute_pc_debug   = 1'b0;
        random_reset_en         = $test$plusargs("RANDOM_RESET");
        load_active_program_expectations();

        if (!program_expectations_ready)
            tb_fatal($sformatf("Selected program expectations are not populated. Fill TODOs for PROGRAM_SEL=%0d %s",
                               PROGRAM_SEL, cfg_string()));

        $display("============================================================");
        $display("RV32I OoO CPU — stronger self-checking TB");
        $display("%s", cfg_string());
        $display("Expected commits=%0d  Post-halt quiet=%0d  Random reset=%0b",
                 active_expected_commits, POST_HALT_QUIET, random_reset_en);
        $display("============================================================");

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // Wait for stable halt after the final run.
        while (global_cycle < TIMEOUT_CYCLES) begin
            @(posedge clk);
            if (dbg_halt === 1'b1) begin
                stable_halt_seen = 1'b1;
                $display("[global %0d run %0d] Stable halt observed %s",
                         global_cycle, run_cycle, cfg_string());
                break;
            end
        end

        if (!stable_halt_seen)
            tb_fatal($sformatf("Timeout after %0d global cycles without halt %s",
                               TIMEOUT_CYCLES, cfg_string()));

        check_post_halt_silence();
        check_halt_reason();
        check_flush_behavior();
        check_commit_count();
        check_registers();
        check_true_ooo();
        check_coverage();

        $display("============================================================");
        $display("ALL CHECKS PASSED %s", cfg_string());
        $display("============================================================");
        $finish;
    end

endmodule
