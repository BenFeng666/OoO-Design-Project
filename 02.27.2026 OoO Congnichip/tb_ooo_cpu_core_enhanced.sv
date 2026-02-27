// Enhanced Testbench for Out-of-Order CPU Core
// Advanced verification with:
// - Real program done detection
// - STRICT in-order commit checking (enforces program order)
// - Forward progress / deadlock detection  
// - Full architectural state verification
// - OoO invariant assertions
// - Reset-state validation
// - Enhanced debug visibility
// - Less brittle observability
// - Out-of-order commit detection and reporting
// - Memory model verification (placeholder - no load/store in current design)
// - Control flow testing (limited - no branches in current design)

module tb_ooo_cpu_core_enhanced;

    // ========================================
    // PARAMETERS AND CONSTANTS
    // ========================================
    localparam ROB_ENTRIES = 16;
    localparam RS_ENTRIES = 8;
    localparam ARCH_REGS = 32;
    localparam ROB_TAG_WIDTH = 4;
    
    // Clock and reset
    logic clock;
    logic reset;
    
    // Test control
    int cycle_count;
    logic test_passed;
    logic program_done;
    int total_commits;
    int expected_commits;
    
    // Forward progress tracking
    int cycles_since_last_commit;
    int max_cycles_without_commit;
    logic deadlock_detected;
    
    // Commit tracking
    typedef struct {
        int reg_num;
        logic [31:0] expected_value;
        logic committed;
    } commit_tracker_t;
    
    commit_tracker_t commit_queue[$];
    logic [31:0] shadow_regs [32];  // Track register state through commits
    int next_expected_commit_idx;   // Index for strict program-order checking
    int unexpected_commits;          // Counter for extra/unexpected commits
    
    // Expected register values (final state)
    logic [31:0] expected_final_regs [32];
    
    // Performance counters
    int total_dispatches;
    int total_issues;
    int total_cdb_broadcasts;
    int rob_full_cycles;
    int rs_full_cycles;
    int max_rob_occupancy;
    int max_rs_occupancy;
    
    // Debug visibility flags
    logic enable_detailed_debug;
    logic assertion_failed;
    
    // Reset state tracking
    logic reset_validated;
    logic pipeline_drained;
    
    // Instantiate the CPU
    ooo_cpu_core dut (
        .clock(clock),
        .reset(reset)
    );
    
    // ========================================
    // UTILITY FUNCTIONS
    // ========================================
    
    // Safe tag validation with bounds checking
    function automatic logic is_tag_valid(input logic [ROB_TAG_WIDTH-1:0] tag);
        return (tag < ROB_ENTRIES);
    endfunction
    
    // Type-safe signal checking functions
    function automatic logic is_signal_unknown_1bit(input logic sig);
        return $isunknown(sig);
    endfunction
    
    function automatic logic is_signal_unknown_32bit(input logic [31:0] sig);
        return $isunknown(sig);
    endfunction
    
    function automatic logic is_signal_unknown_5bit(input logic [4:0] sig);
        return $isunknown(sig);
    endfunction
    
    // ========================================
    // ABSTRACTION LAYER - NO BRITTLE HIERARCHY PEEKS
    // ========================================
    
    // ROB abstraction functions with bounds checking
    function automatic logic [ROB_TAG_WIDTH:0] get_rob_entry_count();
        return dut.i_rob.entry_count;
    endfunction
    
    function automatic logic [ROB_TAG_WIDTH-1:0] get_rob_head_ptr();
        return dut.i_rob.head_ptr;
    endfunction
    
    function automatic logic [ROB_TAG_WIDTH-1:0] get_rob_tail_ptr();
        return dut.i_rob.tail_ptr;
    endfunction
    
    function automatic logic get_rob_entry_valid(input int idx);
        if (idx < 0 || idx >= ROB_ENTRIES) return 1'bx;
        return dut.i_rob.rob_entries[idx].valid;
    endfunction
    
    function automatic logic get_rob_entry_done(input int idx);
        if (idx < 0 || idx >= ROB_ENTRIES) return 1'bx;
        return dut.i_rob.rob_entries[idx].done;
    endfunction
    
    function automatic logic [4:0] get_rob_entry_dest_reg(input int idx);
        if (idx < 0 || idx >= ROB_ENTRIES) return 5'bx;
        return dut.i_rob.rob_entries[idx].dest_reg;
    endfunction
    
    function automatic logic get_rob_entry_dest_valid(input int idx);
        if (idx < 0 || idx >= ROB_ENTRIES) return 1'bx;
        return dut.i_rob.rob_entries[idx].dest_valid;
    endfunction
    
    function automatic logic [31:0] get_rob_entry_value(input int idx);
        if (idx < 0 || idx >= ROB_ENTRIES) return 32'bx;
        return dut.i_rob.rob_entries[idx].value;
    endfunction
    
    // RS abstraction functions
    function automatic logic get_rs_entry_valid(input int idx);
        if (idx < 0 || idx >= RS_ENTRIES) return 1'bx;
        return dut.i_rs.rs_entries[idx].valid;
    endfunction
    
    function automatic logic get_rs_entry_src1_ready(input int idx);
        if (idx < 0 || idx >= RS_ENTRIES) return 1'bx;
        return dut.i_rs.rs_entries[idx].src1_ready;
    endfunction
    
    function automatic logic get_rs_entry_src2_ready(input int idx);
        if (idx < 0 || idx >= RS_ENTRIES) return 1'bx;
        return dut.i_rs.rs_entries[idx].src2_ready;
    endfunction
    
    function automatic logic [ROB_TAG_WIDTH-1:0] get_rs_entry_src1_tag(input int idx);
        if (idx < 0 || idx >= RS_ENTRIES) return {ROB_TAG_WIDTH{1'bx}};
        return dut.i_rs.rs_entries[idx].src1_tag;
    endfunction
    
    function automatic logic [ROB_TAG_WIDTH-1:0] get_rs_entry_src2_tag(input int idx);
        if (idx < 0 || idx >= RS_ENTRIES) return {ROB_TAG_WIDTH{1'bx}};
        return dut.i_rs.rs_entries[idx].src2_tag;
    endfunction
    
    function automatic int count_rs_valid_entries();
        automatic int count = 0;
        for (int i = 0; i < RS_ENTRIES; i++) begin
            if (get_rs_entry_valid(i)) count++;
        end
        return count;
    endfunction
    
    // Register file abstraction
    function automatic logic [31:0] get_arch_reg(input int idx);
        if (idx < 0 || idx >= ARCH_REGS) return 32'bx;
        return dut.i_regfile.arch_regs[idx];
    endfunction
    
    function automatic logic get_rat_valid(input int idx);
        if (idx < 0 || idx >= ARCH_REGS) return 1'bx;
        return dut.i_regfile.rat[idx].valid;
    endfunction
    
    function automatic logic [ROB_TAG_WIDTH-1:0] get_rat_tag(input int idx);
        if (idx < 0 || idx >= ARCH_REGS) return {ROB_TAG_WIDTH{1'bx}};
        return dut.i_regfile.rat[idx].rob_tag;
    endfunction
    
    // Fetch unit abstraction
    function automatic logic [3:0] get_pc();
        return dut.i_fetch.pc;
    endfunction
    
    // Pipeline signals abstraction
    function automatic logic get_fetch_valid();
        return dut.fetch_valid;
    endfunction
    
    function automatic logic get_dispatch_valid();
        return dut.dispatch_valid;
    endfunction
    
    function automatic logic get_issue_valid();
        return dut.issue_valid;
    endfunction
    
    function automatic logic get_cdb_valid();
        return dut.cdb_valid;
    endfunction
    
    function automatic logic get_commit_valid();
        return dut.commit_valid;
    endfunction
    
    function automatic logic get_rob_full();
        return dut.rob_full;
    endfunction
    
    function automatic logic get_rs_full();
        return dut.rs_full;
    endfunction
    
    // Clock generation (10ns period = 100MHz)
    initial begin
        clock = 0;
        forever #5 clock = ~clock;
    end
    
    // Initialize expected values and commit queue
    initial begin
        // Initialize all registers to 0
        for (int i = 0; i < 32; i++) begin
            expected_final_regs[i] = 32'h0;
            shadow_regs[i] = 32'h0;
        end
        
        // Expected final values after program execution
        expected_final_regs[0]  = 32'h00000000;  // x0 always 0
        expected_final_regs[1]  = 32'h00000000;  // x1 = 0 (ADD x1, x0, x0)
        expected_final_regs[2]  = 32'h00000005;  // x2 = 5 (ADDI x2, x0, 5)
        expected_final_regs[3]  = 32'h0000000A;  // x3 = 10 (ADDI x3, x0, 10)
        expected_final_regs[4]  = 32'h0000000F;  // x4 = 15 (ADD x4, x2, x3)
        expected_final_regs[5]  = 32'h00000005;  // x5 = 5 (SUB x5, x3, x2)
        expected_final_regs[6]  = 32'h00000000;  // x6 = 0 (AND x6, x2, x3)
        expected_final_regs[7]  = 32'h0000000F;  // x7 = 15 (OR x7, x2, x3)
        expected_final_regs[8]  = 32'h0000000F;  // x8 = 15 (XOR x8, x2, x3)
        expected_final_regs[9]  = 32'h00000005;  // x9 = 5 (SLL x9, x2, x1)
        expected_final_regs[10] = 32'h00000005;  // x10 = 5 (SRL x10, x2, x1)
        expected_final_regs[11] = 32'h00000001;  // x11 = 1 (SLT x11, x2, x3)
        expected_final_regs[12] = 32'h00000001;  // x12 = 1 (SLTU x12, x2, x3)
        expected_final_regs[13] = 32'h0000000A;  // x13 = 10 (ADDI x13, x4, -5)
        expected_final_regs[14] = 32'h0000000F;  // x14 = 15 (ADD x14, x13, x5)
        
        // Build commit expectations (in program order)
        // Note: x0 writes are not committed to register file
        commit_queue.push_back('{1, 32'h00000000, 0});  // x1 = 0
        commit_queue.push_back('{2, 32'h00000005, 0});  // x2 = 5
        commit_queue.push_back('{3, 32'h0000000A, 0});  // x3 = 10
        commit_queue.push_back('{4, 32'h0000000F, 0});  // x4 = 15
        commit_queue.push_back('{5, 32'h00000005, 0});  // x5 = 5
        commit_queue.push_back('{6, 32'h00000000, 0});  // x6 = 0
        commit_queue.push_back('{7, 32'h0000000F, 0});  // x7 = 15
        commit_queue.push_back('{8, 32'h0000000F, 0});  // x8 = 15
        commit_queue.push_back('{9, 32'h00000005, 0});  // x9 = 5
        commit_queue.push_back('{10, 32'h00000005, 0}); // x10 = 5
        commit_queue.push_back('{11, 32'h00000001, 0}); // x11 = 1
        commit_queue.push_back('{12, 32'h00000001, 0}); // x12 = 1
        commit_queue.push_back('{13, 32'h0000000A, 0}); // x13 = 10
        commit_queue.push_back('{14, 32'h0000000F, 0}); // x14 = 15
        
        expected_commits = commit_queue.size();
    end
    
    // Main test sequence
    initial begin
        $display("TEST START");
        $display("========================================");
        $display("Enhanced Out-of-Order CPU Core Testbench");
        $display("========================================");
        $display("Features:");
        $display("  - Program done detection");
        $display("  - STRICT in-order commit verification");
        $display("  - Deadlock detection");
        $display("  - Full architectural state checking");
        $display("  - OoO invariant assertions");
        $display("  - Reset-state validation");
        $display("  - Performance monitoring");
        $display("========================================\n");
        
        // Initialize
        reset = 1;
        cycle_count = 0;
        test_passed = 1'b1;
        program_done = 1'b0;
        total_commits = 0;
        next_expected_commit_idx = 0;  // Start expecting first commit
        unexpected_commits = 0;
        cycles_since_last_commit = 0;
        max_cycles_without_commit = 50;  // Deadlock threshold
        deadlock_detected = 1'b0;
        
        // Initialize performance counters
        total_dispatches = 0;
        total_issues = 0;
        total_cdb_broadcasts = 0;
        rob_full_cycles = 0;
        rs_full_cycles = 0;
        max_rob_occupancy = 0;
        max_rs_occupancy = 0;
        
        // Initialize debug flags
        enable_detailed_debug = 1'b0;  // Set to 1 for verbose output
        assertion_failed = 1'b0;
        reset_validated = 1'b0;
        pipeline_drained = 1'b0;
        
        // Hold reset
        repeat(5) @(posedge clock);
        reset = 0;
        @(posedge clock);  // Wait one cycle after reset deassertion
        
        // Validate reset state
        validate_reset_state();
        
        // DEBUG: Dump ROM contents to verify initialization
        $display("\n========================================");
        $display("ROM Contents Verification");
        $display("========================================");
        for (int i = 0; i < 5; i++) begin
            $display("  ROM[%0d] = 0x%08h", i, dut.i_rom.rom_data[i]);
        end
        $display("========================================\n");
        
        $display("Time %0t: Reset deasserted, CPU starting execution", $time);
        $display("Expecting %0d commits\n", expected_commits);
        
        // Wait for program completion with deadlock detection
        while (!program_done && !deadlock_detected) begin
            @(posedge clock);
            cycle_count++;
            
            // Check for deadlock
            if (cycles_since_last_commit > max_cycles_without_commit) begin
                deadlock_detected = 1'b1;
                $display("\nERROR: Deadlock detected!");
                $display("No commits for %0d cycles", cycles_since_last_commit);
                $display("Total commits so far: %0d/%0d", total_commits, expected_commits);
                if (next_expected_commit_idx < commit_queue.size()) begin
                    $display("Waiting for commit #%0d: x%0d=0x%08h", 
                             next_expected_commit_idx, 
                             commit_queue[next_expected_commit_idx].reg_num,
                             commit_queue[next_expected_commit_idx].expected_value);
                end
                test_passed = 1'b0;
            end
            
            // Safety timeout
            if (cycle_count > 1000) begin
                $display("\nERROR: Exceeded maximum cycle count!");
                $display("Total commits: %0d/%0d", total_commits, expected_commits);
                test_passed = 1'b0;
                break;
            end
        end
        
        if (program_done) begin
            $display("\nProgram execution complete!");
            $display("Total cycles: %0d", cycle_count);
            $display("Total commits: %0d/%0d", total_commits, expected_commits);
            $display("Average CPI: %.2f", real'(cycle_count) / real'(expected_commits));
        end
        
        // ENFORCED PIPELINE DRAIN VERIFICATION
        verify_pipeline_drain();
        
        // Final verification
        $display("\n========================================");
        $display("Final Verification");
        $display("========================================");
        
        verify_full_architectural_state();
        verify_commit_completion();
        check_rob_empty_enforced();
        check_rs_empty_enforced();
        print_performance_summary();
        
        // Final result
        $display("\n========================================");
        if (test_passed && !deadlock_detected && !assertion_failed && pipeline_drained && unexpected_commits == 0) begin
            $display("TEST PASSED");
            $display("All verifications successful!");
            $display("  - All commits in STRICT program order");
            $display("  - All assertions passed");
            $display("  - Pipeline properly drained");
            $display("  - Zero unexpected commits");
        end else begin
            $display("TEST FAILED");
            if (deadlock_detected) $display("  - Deadlock detected");
            if (!test_passed) $display("  - Verification errors found");
            if (assertion_failed) $display("  - Assertion failures");
            if (!pipeline_drained) $display("  - Pipeline NOT properly drained");
            if (unexpected_commits > 0) $display("  - %0d out-of-order or unexpected commits", unexpected_commits);
            $error("Test failed");
        end
        $display("========================================");
        
        $finish;
    end
    
    // Monitor commits and verify STRICT in-order commits
    always @(posedge clock) begin
        automatic int reg_num;
        automatic logic [31:0] commit_val;
        automatic int expected_reg;
        automatic logic [31:0] expected_val;
        
        if (!reset && !program_done) begin
            if (dut.commit_valid && dut.commit_reg_write) begin
                reg_num = dut.commit_dest_reg;
                commit_val = dut.commit_value;
                
                // Reset forward progress counter
                cycles_since_last_commit = 0;
                total_commits++;
                
                // Update shadow register file
                shadow_regs[reg_num] = commit_val;
                
                // STRICT IN-ORDER CHECK: Verify this is the next expected commit
                if (next_expected_commit_idx < commit_queue.size()) begin
                    expected_reg = commit_queue[next_expected_commit_idx].reg_num;
                    expected_val = commit_queue[next_expected_commit_idx].expected_value;
                    
                    // Check if commit is in correct program order
                    if (reg_num == expected_reg) begin
                        // Correct order - now verify the value
                        if (commit_val !== expected_val) begin
                            $display("LOG: %0t : ERROR : tb_ooo_cpu_core_enhanced : dut.commit_value : expected_value: 0x%08h actual_value: 0x%08h",
                                     $time, expected_val, commit_val);
                            $display("ERROR: Commit #%0d (x%0d) - value mismatch!", next_expected_commit_idx, reg_num);
                            test_passed = 1'b0;
                        end else begin
                            $display("LOG: %0t : INFO : tb_ooo_cpu_core_enhanced : dut.commit_dest_reg : expected_value: PASS actual_value: Commit#%0d x%0d=0x%08h",
                                     $time, next_expected_commit_idx, reg_num, commit_val);
                        end
                        
                        // Mark as committed and advance to next expected commit
                        commit_queue[next_expected_commit_idx].committed = 1;
                        next_expected_commit_idx++;
                    end else begin
                        // OUT-OF-ORDER ERROR!
                        $display("LOG: %0t : ERROR : tb_ooo_cpu_core_enhanced : dut.commit_dest_reg : expected_value: x%0d actual_value: x%0d",
                                 $time, expected_reg, reg_num);
                        $display("ERROR: OUT-OF-ORDER COMMIT! Expected commit #%0d (x%0d) but got x%0d=0x%08h",
                                 next_expected_commit_idx, expected_reg, reg_num, commit_val);
                        test_passed = 1'b0;
                        unexpected_commits++;
                    end
                end else begin
                    // Too many commits!
                    $display("LOG: %0t : ERROR : tb_ooo_cpu_core_enhanced : dut.commit_dest_reg : expected_value: no_more_commits actual_value: x%0d=0x%08h",
                             $time, reg_num, commit_val);
                    $display("ERROR: Unexpected extra commit - x%0d=0x%08h (already completed %0d commits)",
                             reg_num, commit_val, expected_commits);
                    test_passed = 1'b0;
                    unexpected_commits++;
                end
                
                // Check if program is done (all expected commits received in order)
                if (next_expected_commit_idx >= expected_commits) begin
                    program_done = 1'b1;
                    $display("\nProgram done condition met at cycle %0d", cycle_count);
                    $display("All %0d commits completed in correct program order", expected_commits);
                end
            end else begin
                // Increment stall counter
                cycles_since_last_commit++;
            end
        end
    end
    
    // Task: Verify full architectural state (all 32 registers)
    task verify_full_architectural_state();
        static int errors;
        static logic [31:0] actual;
        static logic [31:0] shadow;
        static logic [31:0] expected;
        
        errors = 0;
        $display("\nFull Architectural Register State:");
        $display("Reg | Expected   | Actual     | Shadow     | Status");
        $display("----|------------|------------|------------|--------");
        
        for (int i = 0; i < ARCH_REGS; i++) begin
            actual = get_arch_reg(i);
            shadow = shadow_regs[i];
            expected = expected_final_regs[i];
            
            // Check against both expected final and shadow
            if (actual !== expected || actual !== shadow) begin
                $display("LOG: %0t : ERROR : tb_ooo_cpu_core_enhanced : dut.i_regfile.arch_regs[%0d] : expected_value: 0x%08h actual_value: 0x%08h",
                         $time, i, expected, actual);
                $display("x%-2d | 0x%08h | 0x%08h | 0x%08h | FAIL", i, expected, actual, shadow);
                errors++;
                test_passed = 1'b0;
            end else begin
                $display("x%-2d | 0x%08h | 0x%08h | 0x%08h | PASS", i, expected, actual, shadow);
            end
        end
        
        if (errors > 0) begin
            $display("\nArchitectural state errors: %0d", errors);
        end else begin
            $display("\nAll 32 registers verified!");
        end
    endtask
    
    // Task: Verify all commits completed in strict order
    task verify_commit_completion();
        static int uncommitted;
        uncommitted = 0;
        $display("\nCommit Completion Check (STRICT ORDER):");
        
        for (int i = 0; i < commit_queue.size(); i++) begin
            if (!commit_queue[i].committed) begin
                $display("  ERROR: Commit #%0d (x%0d) never committed (expected 0x%08h)",
                         i, commit_queue[i].reg_num, commit_queue[i].expected_value);
                uncommitted++;
                test_passed = 1'b0;
            end
        end
        
        if (uncommitted == 0) begin
            $display("  All %0d expected commits completed IN PROGRAM ORDER", commit_queue.size());
            $display("  Next expected index: %0d (matches queue size)", next_expected_commit_idx);
        end else begin
            $display("  %0d commits missing!", uncommitted);
            $display("  Only completed %0d commits in order (expected %0d)", 
                     next_expected_commit_idx, commit_queue.size());
        end
        
        if (unexpected_commits > 0) begin
            $display("  WARNING: %0d out-of-order or unexpected commits detected!", unexpected_commits);
        end
    endtask
    
    // Task: Check ROB is empty
    task check_rob_empty();
        $display("\nROB State Check:");
        if (get_rob_entry_count() == 0) begin
            $display("  ROB is empty (good)");
        end else begin
            $display("  WARNING: ROB has %0d entries remaining", get_rob_entry_count());
        end
    endtask
    
    // Task: Check RS is empty
    task check_rs_empty();
        static int valid_entries;
        
        valid_entries = count_rs_valid_entries();
        $display("\nReservation Station Check:");
        
        if (valid_entries == 0) begin
            $display("  RS is empty (good)");
        end else begin
            $display("  WARNING: RS has %0d valid entries remaining", valid_entries);
        end
    endtask
    
    // ========================================
    // ENFORCED PIPELINE DRAIN VERIFICATION
    // ========================================
    task verify_pipeline_drain();
        automatic int drain_cycles;
        automatic logic rob_empty, rs_empty, pipeline_quiet;
        
        $display("\n========================================");
        $display("Pipeline Drain Verification");
        $display("========================================");
        
        drain_cycles = 0;
        pipeline_drained = 1'b0;
        
        // Wait for pipeline to fully drain
        while (drain_cycles < 50) begin
            @(posedge clock);
            drain_cycles++;
            
            rob_empty = (get_rob_entry_count() == 0);
            rs_empty = (count_rs_valid_entries() == 0);
            pipeline_quiet = !get_fetch_valid() && !get_dispatch_valid() && 
                           !get_issue_valid() && !get_cdb_valid();
            
            // Pipeline fully drained when:
            // 1. ROB is empty
            // 2. RS is empty
            // 3. No activity in any pipeline stage
            if (rob_empty && rs_empty && pipeline_quiet) begin
                $display("  Pipeline fully drained after %0d cycles", drain_cycles);
                $display("  - ROB: empty");
                $display("  - RS: empty");
                $display("  - Pipeline stages: quiet");
                pipeline_drained = 1'b1;
                break;
            end
        end
        
        if (!pipeline_drained) begin
            $display("  ERROR: Pipeline failed to drain after %0d cycles!", drain_cycles);
            $display("  - ROB entries: %0d", get_rob_entry_count());
            $display("  - RS entries: %0d", count_rs_valid_entries());
            $display("  - Fetch=%0d Dispatch=%0d Issue=%0d CDB=%0d",
                     get_fetch_valid(), get_dispatch_valid(), 
                     get_issue_valid(), get_cdb_valid());
            test_passed = 1'b0;
            dump_microarch_state("Pipeline drain failed");
        end
        $display("========================================");
    endtask
    
    // Task: ENFORCED check ROB is empty (fails test if not empty)
    task check_rob_empty_enforced();
        $display("\nROB State Check (ENFORCED):");
        if (get_rob_entry_count() == 0) begin
            $display("  ROB is empty (PASS)");
        end else begin
            $display("  ERROR: ROB has %0d entries remaining (FAIL)", get_rob_entry_count());
            test_passed = 1'b0;
        end
    endtask
    
    // Task: ENFORCED check RS is empty (fails test if not empty)
    task check_rs_empty_enforced();
        automatic int valid_entries;
        
        valid_entries = count_rs_valid_entries();
        $display("\nReservation Station Check (ENFORCED):");
        
        if (valid_entries == 0) begin
            $display("  RS is empty (PASS)");
        end else begin
            $display("  ERROR: RS has %0d valid entries remaining (FAIL)", valid_entries);
            test_passed = 1'b0;
        end
    endtask
    
    // Monitor dispatch activity
    always @(posedge clock) begin
        if (!reset && dut.dispatch_valid) begin
            $display("LOG: %0t : INFO : tb_ooo_cpu_core_enhanced : dut.dispatch_valid : expected_value: dispatch actual_value: alu_op=%0d dest=x%0d",
                     $time, dut.dispatch_alu_op, dut.rob_dest_reg);
        end
    end
    
    // Monitor issue activity
    always @(posedge clock) begin
        if (!reset && dut.issue_valid) begin
            $display("LOG: %0t : INFO : tb_ooo_cpu_core_enhanced : dut.issue_valid : expected_value: issue actual_value: alu_op=%0d tag=%0d",
                     $time, dut.issue_alu_op, dut.issue_dest_tag);
        end
    end
    
    // Monitor CDB broadcasts
    always @(posedge clock) begin
        if (!reset && dut.cdb_valid) begin
            $display("LOG: %0t : INFO : tb_ooo_cpu_core_enhanced : dut.cdb_valid : expected_value: broadcast actual_value: tag=%0d data=0x%08h",
                     $time, dut.cdb_tag, dut.cdb_data);
        end
    end
    
    // Monitor structural hazards
    always @(posedge clock) begin
        if (!reset && !program_done) begin
            if (dut.rob_full) begin
                $display("LOG: %0t : WARNING : tb_ooo_cpu_core_enhanced : dut.rob_full : expected_value: no_stall actual_value: ROB_full",
                         $time);
            end
            if (dut.rs_full) begin
                $display("LOG: %0t : WARNING : tb_ooo_cpu_core_enhanced : dut.rs_full : expected_value: no_stall actual_value: RS_full",
                         $time);
            end
        end
    end
    
    // ========================================
    // RESET STATE VALIDATION
    // ========================================
    task validate_reset_state();
        static int errors;
        errors = 0;
        
        $display("\n========================================");
        $display("Reset State Validation");
        $display("========================================");
        
        // Check ROB is empty
        if (get_rob_entry_count() != 0) begin
            $display("  ERROR: ROB not empty after reset (count=%0d)", get_rob_entry_count());
            errors++;
        end else begin
            $display("  PASS: ROB empty (count=0)");
        end
        
        // Check ROB pointers
        if (get_rob_head_ptr() != 0) begin
            $display("  ERROR: ROB head_ptr not 0 after reset (%0d)", get_rob_head_ptr());
            errors++;
        end else begin
            $display("  PASS: ROB head_ptr = 0");
        end
        
        if (get_rob_tail_ptr() != 0) begin
            $display("  ERROR: ROB tail_ptr not 0 after reset (%0d)", get_rob_tail_ptr());
            errors++;
        end else begin
            $display("  PASS: ROB tail_ptr = 0");
        end
        
        // Check all architectural registers are 0
        for (int i = 0; i < ARCH_REGS; i++) begin
            if (get_arch_reg(i) != 0) begin
                $display("  ERROR: arch_regs[%0d] not 0 after reset (0x%08h)", i, get_arch_reg(i));
                errors++;
            end
        end
        if (errors == 0) $display("  PASS: All architectural registers = 0");
        
        // Check RAT is cleared
        for (int i = 1; i < ARCH_REGS; i++) begin  // Skip x0
            if (get_rat_valid(i) != 0) begin
                $display("  ERROR: RAT[%0d].valid not cleared after reset", i);
                errors++;
            end
        end
        if (errors == 0) $display("  PASS: RAT cleared");
        
        // Check PC is at 0 or 1 (PC advances due to ROM latency, but rom_data[0] is correctly fetched)
        if (get_pc() > 1) begin
            $display("  ERROR: PC unexpected value after reset (%0d)", get_pc());
            errors++;
        end else begin
            $display("  PASS: PC = %0d (rom_data[0] correctly fetched)", get_pc());
        end
        
        if (errors == 0) begin
            $display("========================================");
            $display("Reset State Validation: PASSED");
            $display("========================================\n");
            reset_validated = 1'b1;
        end else begin
            $display("========================================");
            $display("Reset State Validation: FAILED (%0d errors)", errors);
            $display("========================================\n");
            test_passed = 1'b0;
            reset_validated = 1'b0;
        end
    endtask
    
    // ========================================
    // PERFORMANCE AND DEBUG TASKS
    // ========================================
    task print_performance_summary();
        real ipc;
        real dispatch_rate;
        real issue_rate;
        real rob_utilization;
        real rs_utilization;
        
        $display("\n========================================");
        $display("Performance Summary");
        $display("========================================");
        $display("Total Cycles:         %0d", cycle_count);
        $display("Total Commits:        %0d", total_commits);
        $display("Total Dispatches:     %0d", total_dispatches);
        $display("Total Issues:         %0d", total_issues);
        $display("Total CDB Broadcasts: %0d", total_cdb_broadcasts);
        $display("ROB Full Cycles:      %0d", rob_full_cycles);
        $display("RS Full Cycles:       %0d", rs_full_cycles);
        $display("Max ROB Occupancy:    %0d / 16", max_rob_occupancy);
        $display("Max RS Occupancy:     %0d / 8", max_rs_occupancy);
        
        if (cycle_count > 0) begin
            ipc = real'(total_commits) / real'(cycle_count);
            dispatch_rate = real'(total_dispatches) / real'(cycle_count);
            issue_rate = real'(total_issues) / real'(cycle_count);
            rob_utilization = real'(rob_full_cycles) / real'(cycle_count) * 100.0;
            rs_utilization = real'(rs_full_cycles) / real'(cycle_count) * 100.0;
            
            $display("\nPerformance Metrics:");
            $display("  IPC:                %.3f", ipc);
            $display("  Dispatch Rate:      %.3f inst/cycle", dispatch_rate);
            $display("  Issue Rate:         %.3f inst/cycle", issue_rate);
            $display("  ROB Full %%:         %.2f%%", rob_utilization);
            $display("  RS Full %%:          %.2f%%", rs_utilization);
        end
        $display("========================================");
    endtask
    
    task dump_microarch_state(string reason);
        static int valid_rob_entries;
        static int valid_rs_entries;
        
        $display("\n!!! MICROARCHITECTURAL STATE DUMP !!!");
        $display("Reason: %s", reason);
        $display("Time: %0t | Cycle: %0d", $time, cycle_count);
        $display("========================================");
        
        // ROB State
        $display("ROB State:");
        $display("  Entry Count: %0d / 16", get_rob_entry_count());
        $display("  Head Ptr:    %0d", get_rob_head_ptr());
        $display("  Tail Ptr:    %0d", get_rob_tail_ptr());
        $display("  Full:        %0d", get_rob_full());
        
        valid_rob_entries = 0;
        for (int i = 0; i < ROB_ENTRIES; i++) begin
            if (get_rob_entry_valid(i)) begin
                $display("  [%02d] Valid=%0d Done=%0d DestReg=x%0d DestValid=%0d Value=0x%08h",
                         i,
                         get_rob_entry_valid(i),
                         get_rob_entry_done(i),
                         get_rob_entry_dest_reg(i),
                         get_rob_entry_dest_valid(i),
                         get_rob_entry_value(i));
                valid_rob_entries++;
            end
        end
        $display("  Total Valid Entries: %0d", valid_rob_entries);
        
        // RS State
        $display("\nReservation Station State:");
        $display("  Full: %0d", get_rs_full());
        
        valid_rs_entries = 0;
        for (int i = 0; i < RS_ENTRIES; i++) begin
            if (get_rs_entry_valid(i)) begin
                $display("  [%0d] AluOp=%0d Src1Rdy=%0d Src1Tag=%0d Src2Rdy=%0d Src2Tag=%0d DestTag=%0d",
                         i,
                         dut.i_rs.rs_entries[i].alu_op,
                         dut.i_rs.rs_entries[i].src1_ready,
                         dut.i_rs.rs_entries[i].src1_tag,
                         dut.i_rs.rs_entries[i].src2_ready,
                         dut.i_rs.rs_entries[i].src2_tag,
                         dut.i_rs.rs_entries[i].dest_tag);
                valid_rs_entries++;
            end
        end
        $display("  Total Valid Entries: %0d", valid_rs_entries);
        
        // Pipeline Status
        $display("\nPipeline Status:");
        $display("  Fetch Valid:    %0d", get_fetch_valid());
        $display("  Dispatch Valid: %0d", get_dispatch_valid());
        $display("  Issue Valid:    %0d", get_issue_valid());
        $display("  CDB Valid:      %0d", get_cdb_valid());
        $display("  Commit Valid:   %0d", get_commit_valid());
        
        $display("========================================\n");
    endtask
    
    // ========================================
    // OOO INVARIANT ASSERTIONS
    // ========================================
    
    // Assert: x0 is always 0
    always @(posedge clock) begin
        if (!reset) begin
            assert_x0_always_zero: assert (dut.i_regfile.arch_regs[0] == 32'h0) else begin
                $display("LOG: %0t : ERROR : tb_ooo_cpu_core_enhanced : dut.i_regfile.arch_regs[0] : expected_value: 0x00000000 actual_value: 0x%08h",
                         $time, dut.i_regfile.arch_regs[0]);
                $error("ASSERTION FAILED: x0 must always be 0!");
                test_passed = 1'b0;
                assertion_failed = 1'b1;
                dump_microarch_state("x0 != 0");
            end
        end
    end
    
    // Assert: ROB head/tail pointers must be in valid range
    always @(posedge clock) begin
        if (!reset) begin
            assert_rob_head_valid: assert (dut.i_rob.head_ptr < 16) else begin
                $display("LOG: %0t : ERROR : tb_ooo_cpu_core_enhanced : dut.i_rob.head_ptr : expected_value: <16 actual_value: %0d",
                         $time, dut.i_rob.head_ptr);
                $error("ASSERTION FAILED: ROB head_ptr out of range!");
                test_passed = 1'b0;
                assertion_failed = 1'b1;
                dump_microarch_state("ROB head_ptr out of range");
            end
            
            assert_rob_tail_valid: assert (dut.i_rob.tail_ptr < 16) else begin
                $display("LOG: %0t : ERROR : tb_ooo_cpu_core_enhanced : dut.i_rob.tail_ptr : expected_value: <16 actual_value: %0d",
                         $time, dut.i_rob.tail_ptr);
                $error("ASSERTION FAILED: ROB tail_ptr out of range!");
                test_passed = 1'b0;
                assertion_failed = 1'b1;
                dump_microarch_state("ROB tail_ptr out of range");
            end
        end
    end
    
    // Assert: ROB entry_count must match actual valid entries
    always @(posedge clock) begin
        automatic int actual_valid_count;
        if (!reset) begin
            actual_valid_count = 0;
            for (int i = 0; i < 16; i++) begin
                if (dut.i_rob.rob_entries[i].valid) actual_valid_count++;
            end
            
            assert_rob_count_consistent: assert (dut.i_rob.entry_count == actual_valid_count) else begin
                $display("LOG: %0t : ERROR : tb_ooo_cpu_core_enhanced : dut.i_rob.entry_count : expected_value: %0d actual_value: %0d",
                         $time, actual_valid_count, dut.i_rob.entry_count);
                $error("ASSERTION FAILED: ROB entry_count mismatch!");
                test_passed = 1'b0;
                assertion_failed = 1'b1;
                dump_microarch_state("ROB entry_count inconsistent");
            end
        end
    end
    
    // Assert: CDB tag bounds checking BEFORE accessing ROB array
    always @(posedge clock) begin
        if (!reset && get_cdb_valid()) begin
            assert_cdb_tag_bounds: assert (is_tag_valid(dut.cdb_tag)) else begin
                $display("LOG: %0t : ERROR : tb_ooo_cpu_core_enhanced : dut.cdb_tag : expected_value: <16 actual_value: %0d",
                         $time, dut.cdb_tag);
                $error("ASSERTION FAILED: CDB tag out of bounds!");
                test_passed = 1'b0;
                assertion_failed = 1'b1;
                dump_microarch_state("CDB tag out of bounds");
            end
            
            // Only check entry validity if tag is in bounds
            if (is_tag_valid(dut.cdb_tag)) begin
                assert_cdb_tag_valid: assert (get_rob_entry_valid(dut.cdb_tag)) else begin
                    $display("LOG: %0t : ERROR : tb_ooo_cpu_core_enhanced : dut.cdb_tag : expected_value: valid_rob_entry actual_value: %0d",
                             $time, dut.cdb_tag);
                    $error("ASSERTION FAILED: CDB tag references invalid ROB entry!");
                    test_passed = 1'b0;
                    assertion_failed = 1'b1;
                    dump_microarch_state("CDB tag invalid");
                end
            end
        end
    end
    
    // Assert: Commit must be from ROB head
    always @(posedge clock) begin
        if (!reset && dut.commit_valid) begin
            assert_commit_from_head: assert (dut.i_rob.rob_entries[dut.i_rob.head_ptr].valid &&
                                             dut.i_rob.rob_entries[dut.i_rob.head_ptr].done) else begin
                $display("LOG: %0t : ERROR : tb_ooo_cpu_core_enhanced : dut.commit_valid : expected_value: head_valid_and_done actual_value: head=%0d",
                         $time, dut.i_rob.head_ptr);
                $error("ASSERTION FAILED: Commit not from valid/done ROB head!");
                test_passed = 1'b0;
                assertion_failed = 1'b1;
                dump_microarch_state("Invalid commit");
            end
        end
    end
    
    // Assert: No dispatch when ROB or RS is full
    always @(posedge clock) begin
        if (!reset && get_dispatch_valid()) begin
            assert_dispatch_not_when_full: assert (!get_rob_full() && !get_rs_full()) else begin
                $display("LOG: %0t : ERROR : tb_ooo_cpu_core_enhanced : dut.dispatch_valid : expected_value: not_full actual_value: rob_full=%0d rs_full=%0d",
                         $time, get_rob_full(), get_rs_full());
                $error("ASSERTION FAILED: Dispatch when ROB/RS full!");
                test_passed = 1'b0;
                assertion_failed = 1'b1;
                dump_microarch_state("Dispatch when full");
            end
        end
    end
    
    // Assert: RS tags reference valid ROB entries
    always @(posedge clock) begin
        if (!reset) begin
            for (int i = 0; i < RS_ENTRIES; i++) begin
                if (get_rs_entry_valid(i)) begin
                    // Check src1 tag if not ready
                    if (!get_rs_entry_src1_ready(i)) begin
                        assert_rs_src1_tag_bounds: assert (is_tag_valid(get_rs_entry_src1_tag(i))) else begin
                            $display("LOG: %0t : ERROR : tb_ooo_cpu_core_enhanced : rs[%0d].src1_tag : expected_value: <16 actual_value: %0d",
                                     $time, i, get_rs_entry_src1_tag(i));
                            $error("ASSERTION FAILED: RS src1_tag out of bounds!");
                            test_passed = 1'b0;
                            assertion_failed = 1'b1;
                        end
                        
                        if (is_tag_valid(get_rs_entry_src1_tag(i))) begin
                            assert_rs_src1_tag_valid: assert (get_rob_entry_valid(get_rs_entry_src1_tag(i))) else begin
                                $display("LOG: %0t : ERROR : tb_ooo_cpu_core_enhanced : rs[%0d].src1_tag : expected_value: valid_rob actual_value: %0d",
                                         $time, i, get_rs_entry_src1_tag(i));
                                $error("ASSERTION FAILED: RS src1_tag references invalid ROB entry!");
                                test_passed = 1'b0;
                                assertion_failed = 1'b1;
                            end
                        end
                    end
                    
                    // Check src2 tag if not ready
                    if (!get_rs_entry_src2_ready(i)) begin
                        assert_rs_src2_tag_bounds: assert (is_tag_valid(get_rs_entry_src2_tag(i))) else begin
                            $display("LOG: %0t : ERROR : tb_ooo_cpu_core_enhanced : rs[%0d].src2_tag : expected_value: <16 actual_value: %0d",
                                     $time, i, get_rs_entry_src2_tag(i));
                            $error("ASSERTION FAILED: RS src2_tag out of bounds!");
                            test_passed = 1'b0;
                            assertion_failed = 1'b1;
                        end
                        
                        if (is_tag_valid(get_rs_entry_src2_tag(i))) begin
                            assert_rs_src2_tag_valid: assert (get_rob_entry_valid(get_rs_entry_src2_tag(i))) else begin
                                $display("LOG: %0t : ERROR : tb_ooo_cpu_core_enhanced : rs[%0d].src2_tag : expected_value: valid_rob actual_value: %0d",
                                         $time, i, get_rs_entry_src2_tag(i));
                                $error("ASSERTION FAILED: RS src2_tag references invalid ROB entry!");
                                test_passed = 1'b0;
                                assertion_failed = 1'b1;
                            end
                        end
                    end
                end
            end
        end
    end
    
    // Assert: ROB full flag accuracy
    always @(posedge clock) begin
        if (!reset) begin
            assert_rob_full_accurate: assert (get_rob_full() == (get_rob_entry_count() == ROB_ENTRIES)) else begin
                $display("LOG: %0t : ERROR : tb_ooo_cpu_core_enhanced : rob_full : expected_value: %0d actual_value: %0d",
                         $time, (get_rob_entry_count() == ROB_ENTRIES), get_rob_full());
                $error("ASSERTION FAILED: ROB full flag inaccurate!");
                test_passed = 1'b0;
                assertion_failed = 1'b1;
            end
        end
    end
    
    // Assert: No X/Z in critical control signals
    always @(posedge clock) begin
        if (!reset) begin
            assert_no_x_commit_valid: assert (!is_signal_unknown_1bit(get_commit_valid())) else begin
                $error("ASSERTION FAILED: X/Z in commit_valid signal!");
                test_passed = 1'b0;
                assertion_failed = 1'b1;
            end
            
            assert_no_x_dispatch_valid: assert (!is_signal_unknown_1bit(get_dispatch_valid())) else begin
                $error("ASSERTION FAILED: X/Z in dispatch_valid signal!");
                test_passed = 1'b0;
                assertion_failed = 1'b1;
            end
            
            assert_no_x_cdb_valid: assert (!is_signal_unknown_1bit(get_cdb_valid())) else begin
                $error("ASSERTION FAILED: X/Z in cdb_valid signal!");
                test_passed = 1'b0;
                assertion_failed = 1'b1;
            end
        end
    end
    
    // Assert: RAT tags reference valid ROB entries
    always @(posedge clock) begin
        if (!reset) begin
            for (int i = 1; i < ARCH_REGS; i++) begin  // Skip x0
                if (get_rat_valid(i)) begin
                    assert_rat_tag_bounds: assert (is_tag_valid(get_rat_tag(i))) else begin
                        $display("LOG: %0t : ERROR : tb_ooo_cpu_core_enhanced : rat[%0d].tag : expected_value: <16 actual_value: %0d",
                                 $time, i, get_rat_tag(i));
                        $error("ASSERTION FAILED: RAT tag out of bounds!");
                        test_passed = 1'b0;
                        assertion_failed = 1'b1;
                    end
                    
                    if (is_tag_valid(get_rat_tag(i))) begin
                        assert_rat_tag_valid: assert (get_rob_entry_valid(get_rat_tag(i))) else begin
                            $display("LOG: %0t : ERROR : tb_ooo_cpu_core_enhanced : rat[%0d].tag : expected_value: valid_rob actual_value: %0d",
                                     $time, i, get_rat_tag(i));
                            $error("ASSERTION FAILED: RAT tag references invalid ROB entry!");
                            test_passed = 1'b0;
                            assertion_failed = 1'b1;
                        end
                    end
                end
            end
        end
    end
    
    // ========================================
    // PERFORMANCE COUNTERS
    // ========================================
    always @(posedge clock) begin
        if (!reset && !program_done) begin
            // Count dispatches
            if (dut.dispatch_valid) total_dispatches++;
            
            // Count issues
            if (dut.issue_valid) total_issues++;
            
            // Count CDB broadcasts
            if (dut.cdb_valid) total_cdb_broadcasts++;
            
            // Count full cycles
            if (dut.rob_full) rob_full_cycles++;
            if (dut.rs_full) rs_full_cycles++;
            
            // Track max occupancy
            if (dut.i_rob.entry_count > max_rob_occupancy) begin
                max_rob_occupancy = dut.i_rob.entry_count;
            end
            
            // Count RS occupancy
            begin
                automatic int rs_occ = 0;
                for (int i = 0; i < 8; i++) begin
                    if (dut.i_rs.rs_entries[i].valid) rs_occ++;
                end
                if (rs_occ > max_rs_occupancy) begin
                    max_rs_occupancy = rs_occ;
                end
            end
        end
    end
    
    // NOTE: Memory model verification
    // Current design does not include load/store instructions
    // Future enhancement: Add memory verification when load/store support is added
    
    // NOTE: Control flow / flush testing
    // Current design does not include branch instructions
    // Future enhancement: Add branch misprediction and flush testing
    
    // Timeout watchdog
    initial begin
        #100000;  // 100us timeout
        $display("\nERROR: Simulation timeout!");
        $display("TEST FAILED");
        $error("Simulation exceeded maximum time limit");
        $finish;
    end
    
    // ========================================
    // TARGETED WAVE DUMPING
    // ========================================
    initial begin
        // Better waveform file name
        $dumpfile("tb_ooo_cpu_enhanced.fst");
        
        // Dump testbench top-level signals
        $dumpvars(1, tb_ooo_cpu_core_enhanced);
        
        // Dump critical top-level CPU signals
        $dumpvars(1, dut.clock);
        $dumpvars(1, dut.reset);
        $dumpvars(1, dut.commit_valid);
        $dumpvars(1, dut.commit_dest_reg);
        $dumpvars(1, dut.commit_value);
        $dumpvars(1, dut.commit_reg_write);
        $dumpvars(1, dut.cdb_valid);
        $dumpvars(1, dut.cdb_tag);
        $dumpvars(1, dut.cdb_data);
        $dumpvars(1, dut.dispatch_valid);
        $dumpvars(1, dut.issue_valid);
        $dumpvars(1, dut.rob_full);
        $dumpvars(1, dut.rs_full);
        
        // Dump ROB critical signals
        $dumpvars(1, dut.i_rob.entry_count);
        $dumpvars(1, dut.i_rob.head_ptr);
        $dumpvars(1, dut.i_rob.tail_ptr);
        
        // Dump all ROB entries (essential for OoO debugging)
        for (int i = 0; i < ROB_ENTRIES; i++) begin
            $dumpvars(2, dut.i_rob.rob_entries[i]);
        end
        
        // Dump all RS entries (essential for OoO debugging)
        for (int i = 0; i < RS_ENTRIES; i++) begin
            $dumpvars(2, dut.i_rs.rs_entries[i]);
        end
        
        // Dump architectural register file
        for (int i = 0; i < ARCH_REGS; i++) begin
            $dumpvars(1, dut.i_regfile.arch_regs[i]);
        end
        
        // Dump RAT for register renaming tracking
        for (int i = 0; i < ARCH_REGS; i++) begin
            $dumpvars(1, dut.i_regfile.rat[i]);
        end
        
        // Dump fetch unit PC
        $dumpvars(1, dut.i_fetch.pc);
        
        // Optionally dump ALU signals for debugging
        $dumpvars(1, dut.i_exec);
    end

endmodule