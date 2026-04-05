// ============================================================================
// tb.sv — Self-Checking Testbench for the RV32I Out-of-Order CPU Core
// ============================================================================
//
// Verification strategy:
//   1. Run a 16-instruction demo program (14 committed + 1 skipped + ECALL)
//   2. Verify every commit happens in the exact expected PC order
//   3. Verify a branch flush occurs with the correct target
//   4. Verify halt is caused by ECALL (ROB halt), not illegal decode
//   5. Verify all final architectural register values
//   6. Fail immediately if any wrong-path instruction commits
//   7. Fail fatally on any mismatch — no warnings-only
//
// Demo program:
//
//   Addr  Hex         Assembly            Effect
//   0x00  00500093    ADDI x1, x0, 5      x1  = 5
//   0x04  00A00113    ADDI x2, x0, 10     x2  = 10
//   0x08  002081B3    ADD  x3, x1, x2     x3  = 15
//   0x0C  00300213    ADDI x4, x0, 3      x4  = 3
//   0x10  404182B3    SUB  x5, x3, x4     x5  = 12
//   0x14  00C00313    ADDI x6, x0, 12     x6  = 12
//   0x18  00628463    BEQ  x5, x6, +8     taken → 0x20
//   0x1C  06300393    ADDI x7, x0, 99     SKIPPED (wrong path)
//   0x20  DEADB437    LUI  x8, 0xDEADB    x8  = 0xDEADB000
//   0x24  0020C4B3    XOR  x9, x1, x2     x9  = 15
//   0x28  00112533    SLT  x10, x2, x1    x10 = 0
//   0x2C  0020B5B3    SLTU x11, x1, x2    x11 = 1
//   0x30  00309613    SLLI x12, x1, 3     x12 = 40
//   0x34  0FF06693    ORI  x13, x0, 255   x13 = 255
//   0x38  00F6F713    ANDI x14, x13, 15   x14 = 15
//   0x3C  00000073    ECALL               halt (not committed)
//
// Expected committed PC sequence (14 commits):
//   0x00, 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18,
//   0x20, 0x24, 0x28, 0x2C, 0x30, 0x34, 0x38
//   (0x1C skipped by taken branch; 0x3C = ECALL halts without committing)
//
// Expected final registers:
//   x0=0  x1=5  x2=10  x3=15  x4=3  x5=12  x6=12  x7=0
//   x8=0xDEADB000  x9=15  x10=0  x11=1  x12=40  x13=255  x14=15
// ============================================================================

`timescale 1ns / 1ps

module tb;

    // ================================================================
    // Parameters
    // ================================================================
    localparam int CLK_PERIOD       = 10;
    localparam int TIMEOUT          = 2000;
    localparam int ROM_DEPTH        = 64;
    localparam int ROB_DEPTH        = 4;
    localparam int RS_DEPTH         = 4;
    localparam int EXPECTED_COMMITS = 14;
    localparam int NUM_CHECK_REGS   = 15;   // x0..x14

    // ================================================================
    // Clock and reset
    // ================================================================
    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ================================================================
    // DUT signals
    // ================================================================
    logic [31:0] dbg_pc;
    logic        dbg_fetch_valid;
    logic        dbg_decode_valid;
    logic        dbg_dispatch_valid;
    logic        dbg_issue_valid;
    logic        dbg_execute_valid;
    logic        dbg_commit_valid;
    logic [31:0] dbg_commit_pc;
    logic [4:0]  dbg_commit_rd;
    logic [31:0] dbg_commit_value;
    logic        dbg_commit_uses_rd;
    logic        dbg_halt;

    // ================================================================
    // DUT instantiation
    // ================================================================
    ooo_cpu_core #(
        .ROM_DEPTH (ROM_DEPTH),
        .ROB_DEPTH (ROB_DEPTH),
        .RS_DEPTH  (RS_DEPTH),
        .MEM_FILE  ("program.hex")
    ) u_dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .dbg_pc             (dbg_pc),
        .dbg_fetch_valid    (dbg_fetch_valid),
        .dbg_decode_valid   (dbg_decode_valid),
        .dbg_dispatch_valid (dbg_dispatch_valid),
        .dbg_issue_valid    (dbg_issue_valid),
        .dbg_execute_valid  (dbg_execute_valid),
        .dbg_commit_valid   (dbg_commit_valid),
        .dbg_commit_pc      (dbg_commit_pc),
        .dbg_commit_rd      (dbg_commit_rd),
        .dbg_commit_value   (dbg_commit_value),
        .dbg_commit_uses_rd (dbg_commit_uses_rd),
        .dbg_halt           (dbg_halt)
    );

    // ================================================================
    // Cycle counter — single authoritative source
    // ================================================================
    int cycle_count;

    always_ff @(posedge clk) begin
        if (!rst_n)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end

    // ================================================================
    // Expected committed PC sequence
    // ================================================================
    logic [31:0] expected_commit_pcs [0:EXPECTED_COMMITS-1];

    initial begin
        expected_commit_pcs[0]  = 32'h00000000;
        expected_commit_pcs[1]  = 32'h00000004;
        expected_commit_pcs[2]  = 32'h00000008;
        expected_commit_pcs[3]  = 32'h0000000C;
        expected_commit_pcs[4]  = 32'h00000010;
        expected_commit_pcs[5]  = 32'h00000014;
        expected_commit_pcs[6]  = 32'h00000018;
        expected_commit_pcs[7]  = 32'h00000020;
        expected_commit_pcs[8]  = 32'h00000024;
        expected_commit_pcs[9]  = 32'h00000028;
        expected_commit_pcs[10] = 32'h0000002C;
        expected_commit_pcs[11] = 32'h00000030;
        expected_commit_pcs[12] = 32'h00000034;
        expected_commit_pcs[13] = 32'h00000038;
    end

    // ================================================================
    // Expected final register values
    // ================================================================
    logic [31:0] expected_regs [0:NUM_CHECK_REGS-1];

    initial begin
        expected_regs[0]  = 32'h00000000;
        expected_regs[1]  = 32'h00000005;
        expected_regs[2]  = 32'h0000000A;
        expected_regs[3]  = 32'h0000000F;
        expected_regs[4]  = 32'h00000003;
        expected_regs[5]  = 32'h0000000C;
        expected_regs[6]  = 32'h0000000C;
        expected_regs[7]  = 32'h00000000;
        expected_regs[8]  = 32'hDEADB000;
        expected_regs[9]  = 32'h0000000F;
        expected_regs[10] = 32'h00000000;
        expected_regs[11] = 32'h00000001;
        expected_regs[12] = 32'h00000028;
        expected_regs[13] = 32'h000000FF;
        expected_regs[14] = 32'h0000000F;
    end

    // ================================================================
    // Runtime tracking state
    // ================================================================
    int  commit_index;       // Index into expected_commit_pcs
    int  flush_count;        // Number of flushes observed
    logic [31:0] flush_target_seen;  // Last flush target PC
    int  fatal_errors;       // Accumulated fatal error count

    // ================================================================
    // Commit order verification (clocked)
    // ================================================================
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // Nothing — main initial block handles reset of tracking vars
        end else if (dbg_commit_valid) begin
            // --- Wrong-path check: fail immediately if x7 is written ---
            if (dbg_commit_uses_rd && dbg_commit_rd == 5'd7) begin
                $display("");
                $display("FATAL [cycle %0d]: Wrong-path commit detected!",
                         cycle_count);
                $display("  Committed write to x7 = 0x%08X at PC=0x%08X",
                         dbg_commit_value, dbg_commit_pc);
                $display("  The BEQ branch should have skipped PC=0x1C.");
                $fatal(1, "Wrong-path instruction committed to x7");
            end

            // --- In-order commit check ---
            if (commit_index < EXPECTED_COMMITS) begin
                if (dbg_commit_pc !== expected_commit_pcs[commit_index]) begin
                    $display("");
                    $display("FATAL [cycle %0d]: Out-of-order or wrong commit!",
                             cycle_count);
                    $display("  Commit #%0d: got PC=0x%08X, expected PC=0x%08X",
                             commit_index, dbg_commit_pc,
                             expected_commit_pcs[commit_index]);
                    $fatal(1, "Commit PC sequence mismatch");
                end
            end else begin
                $display("");
                $display("FATAL [cycle %0d]: Too many commits!", cycle_count);
                $display("  Commit #%0d at PC=0x%08X (expected only %0d commits)",
                         commit_index, dbg_commit_pc, EXPECTED_COMMITS);
                $fatal(1, "Excess commits beyond expected count");
            end
        end
    end

    // commit_index must be updated in a separate block to avoid
    // reading the incremented value in the same always_ff
    always_ff @(posedge clk) begin
        if (!rst_n)
            commit_index <= 0;
        else if (dbg_commit_valid)
            commit_index <= commit_index + 1;
    end

    // ================================================================
    // Flush monitor (clocked)
    // ================================================================
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            flush_count <= 0;
            flush_target_seen <= '0;
        end else if (u_dut.rob_flush) begin
            flush_count <= flush_count + 1;
            flush_target_seen <= u_dut.rob_flush_target_pc;
            $display("[cycle %4d] *** FLUSH #%0d *** target_pc=0x%08X",
                     cycle_count, flush_count + 1,
                     u_dut.rob_flush_target_pc);
        end
    end

    // ================================================================
    // Cycle-by-cycle trace (clocked, after reset)
    // ================================================================
    always @(posedge clk) begin
        if (rst_n) begin
            $write("[cycle %4d] ", cycle_count);

            // Fetch
            if (dbg_fetch_valid)
                $write("F:0x%04X ", dbg_pc);
            else
                $write("F:-------- ");

            // Decode
            if (dbg_decode_valid)
                $write("D:ok ");
            else if (dbg_fetch_valid)
                $write("D:IL ");
            else
                $write("D:-- ");

            // Dispatch
            if (dbg_dispatch_valid)
                $write("DISP ");
            else
                $write("---- ");

            // Issue
            if (dbg_issue_valid)
                $write("ISS ");
            else
                $write("--- ");

            // Execute / CDB
            if (dbg_execute_valid)
                $write("EX:tag=%0d val=0x%08X ",
                       u_dut.cdb_tag, u_dut.cdb_value);
            else
                $write("EX:---                ");

            // Commit
            if (dbg_commit_valid) begin
                if (dbg_commit_uses_rd)
                    $write("CMT:#%0d PC=0x%04X x%0d=0x%08X",
                           commit_index, dbg_commit_pc,
                           dbg_commit_rd, dbg_commit_value);
                else
                    $write("CMT:#%0d PC=0x%04X (no rd)       ",
                           commit_index, dbg_commit_pc);
            end else begin
                $write("CMT:---                         ");
            end

            // Halt
            if (dbg_halt)
                $write(" HALT");

            // RS/ROB status
            $write("  [RS_full=%b ROB_full=%b]",
                   u_dut.rs_full, u_dut.rob_full);

            $display("");
        end
    end

    // ================================================================
    // Main test sequence
    // ================================================================
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);

        fatal_errors = 0;

        $display("============================================================");
        $display("  RV32I Out-of-Order CPU — Self-Checking Testbench");
        $display("============================================================");
        $display("  ROM_DEPTH=%0d  ROB_DEPTH=%0d  RS_DEPTH=%0d",
                 ROM_DEPTH, ROB_DEPTH, RS_DEPTH);
        $display("  Expected commits: %0d", EXPECTED_COMMITS);
        $display("============================================================");
        $display("");

        // ----- Reset -----
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        $display("[cycle    0] Reset released");
        $display("");

        // ----- Wait for halt -----
        fork
            begin
                wait (dbg_halt);
            end
            begin
                repeat (TIMEOUT) @(posedge clk);
                $display("");
                $display("FATAL: Timeout after %0d cycles — CPU never halted.",
                         TIMEOUT);
                $display("  Commits so far: %0d / %0d",
                         commit_index, EXPECTED_COMMITS);
                dump_registers();
                $fatal(1, "Timeout — CPU never halted");
            end
        join_any
        disable fork;

        // Let pipeline drain
        repeat (10) @(posedge clk);

        $display("");
        $display("============================================================");
        $display("  CPU halted at cycle %0d", cycle_count);
        $display("  Total commits: %0d (expected: %0d)",
                 commit_index, EXPECTED_COMMITS);
        $display("============================================================");
        $display("");

        // ----- Post-halt checks -----
        check_halt_reason();
        check_flush_behavior();
        check_commit_count();
        check_registers();

        // ----- Final verdict -----
        $display("");
        $display("============================================================");
        if (fatal_errors == 0) begin
            $display("  =====         ALL CHECKS PASSED          =====");
        end else begin
            $display("  =====         FAIL  (%0d errors)          =====",
                     fatal_errors);
        end
        $display("============================================================");
        $display("");

        if (fatal_errors > 0)
            $fatal(1, "Testbench failed with %0d errors", fatal_errors);

        $finish;
    end

    // ================================================================
    // Check: halt reason is ECALL (ROB halt), not illegal decode
    // ================================================================
    task check_halt_reason();
        $display("--- Check: Halt Reason ---");
        if (u_dut.rob_halt) begin
            $display("  ROB halt (ECALL): YES — correct");
        end else begin
            $display("  ROB halt (ECALL): NO");
            fatal_errors = fatal_errors + 1;
        end
        if (u_dut.illegal_halt) begin
            $display("  Illegal halt:     YES — *** WRONG ***");
            $display("  CPU halted due to illegal instruction, not ECALL.");
            fatal_errors = fatal_errors + 1;
        end else begin
            $display("  Illegal halt:     NO — correct");
        end
        $display("");
    endtask

    // ================================================================
    // Check: branch flush occurred with correct target
    // ================================================================
    task check_flush_behavior();
        $display("--- Check: Branch Flush ---");
        if (flush_count == 0) begin
            $display("  No flush observed — *** FAIL ***");
            $display("  The BEQ at 0x18 should have caused a flush to 0x20.");
            fatal_errors = fatal_errors + 1;
        end else begin
            $display("  Flush count: %0d", flush_count);
            if (flush_target_seen == 32'h00000020) begin
                $display("  Last flush target: 0x%08X — correct",
                         flush_target_seen);
            end else begin
                $display("  Last flush target: 0x%08X — *** WRONG ***",
                         flush_target_seen);
                $display("  Expected: 0x00000020");
                fatal_errors = fatal_errors + 1;
            end
        end
        $display("");
    endtask

    // ================================================================
    // Check: commit count
    // ================================================================
    task check_commit_count();
        $display("--- Check: Commit Count ---");
        $display("  Commits: %0d (expected: %0d)",
                 commit_index, EXPECTED_COMMITS);
        if (commit_index != EXPECTED_COMMITS) begin
            $display("  *** FAIL: wrong commit count ***");
            fatal_errors = fatal_errors + 1;
        end else begin
            $display("  OK");
        end
        $display("");
    endtask

    // ================================================================
    // Check: final architectural register values
    // ================================================================
    task check_registers();
        logic [31:0] actual;
        int reg_errors;

        reg_errors = 0;
        $display("--- Check: Final Register Values ---");

        for (int i = 0; i < NUM_CHECK_REGS; i++) begin
            if (i == 0)
                actual = 32'h0;
            else
                actual = u_dut.u_rf.regs[i];

            if (actual !== expected_regs[i]) begin
                $display("  x%-2d = 0x%08X  expected 0x%08X  *** MISMATCH ***",
                         i, actual, expected_regs[i]);
                reg_errors = reg_errors + 1;
            end else begin
                $display("  x%-2d = 0x%08X  OK", i, actual);
            end
        end

        // Explicit x7 wrong-path check (redundant with runtime check,
        // but catches cases where the runtime check was not triggered)
        if (u_dut.u_rf.regs[7] !== 32'h0) begin
            $display("");
            $display("  *** x7 = 0x%08X — wrong-path ADDI committed! ***",
                     u_dut.u_rf.regs[7]);
            reg_errors = reg_errors + 1;
        end

        fatal_errors = fatal_errors + reg_errors;

        $display("  Register errors: %0d", reg_errors);
        $display("");
    endtask

    // ================================================================
    // Register dump (for debug on failure)
    // ================================================================
    task dump_registers();
        $display("--- Architectural Register Dump ---");
        for (int i = 0; i < 16; i++) begin
            if (i == 0)
                $display("  x%-2d = 0x%08X  (hardwired zero)", i, 32'h0);
            else
                $display("  x%-2d = 0x%08X", i, u_dut.u_rf.regs[i]);
        end
        $display("-----------------------------------");
    endtask

endmodule
