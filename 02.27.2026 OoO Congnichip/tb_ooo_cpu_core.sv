// Testbench for Out-of-Order CPU Core
// Verifies correct execution of the test program in ROM
// Checks register file values after program completion

module tb_ooo_cpu_core;

    // Clock and reset
    logic clock;
    logic reset;
    
    // Test control
    int cycle_count;
    logic test_passed;
    logic test_complete;
    
    // Expected register values (from the test program)
    logic [31:0] expected_regs [32];
    
    // Instantiate the CPU
    ooo_cpu_core dut (
        .clock(clock),
        .reset(reset)
    );
    
    // Clock generation (10ns period = 100MHz)
    initial begin
        clock = 0;
        forever #5 clock = ~clock;
    end
    
    // Initialize expected register values
    initial begin
        // Initialize all registers to 0
        for (int i = 0; i < 32; i++) begin
            expected_regs[i] = 32'h0;
        end
        
        // Expected values after program execution
        // Based on the program in instruction_rom.sv:
        expected_regs[0]  = 32'h00000000;  // x0 always 0
        expected_regs[1]  = 32'h00000000;  // x1 = 0
        expected_regs[2]  = 32'h00000005;  // x2 = 5 (ADDI x2, x0, 5)
        expected_regs[3]  = 32'h0000000A;  // x3 = 10 (ADDI x3, x0, 10)
        expected_regs[4]  = 32'h0000000F;  // x4 = 15 (ADD x4, x2, x3 = 5+10)
        expected_regs[5]  = 32'h00000005;  // x5 = 5 (SUB x5, x3, x2 = 10-5)
        expected_regs[6]  = 32'h00000000;  // x6 = 0 (AND x6, x2, x3 = 5&10)
        expected_regs[7]  = 32'h0000000F;  // x7 = 15 (OR x7, x2, x3 = 5|10)
        expected_regs[8]  = 32'h0000000F;  // x8 = 15 (XOR x8, x2, x3 = 5^10)
        expected_regs[9]  = 32'h00000005;  // x9 = 5 (SLL x9, x2, x1 = 5<<0)
        expected_regs[10] = 32'h00000005;  // x10 = 5 (SRL x10, x2, x1 = 5>>0)
        expected_regs[11] = 32'h00000001;  // x11 = 1 (SLT x11, x2, x3 = 5<10)
        expected_regs[12] = 32'h00000001;  // x12 = 1 (SLTU x12, x2, x3 = 5<10)
        expected_regs[13] = 32'h0000000A;  // x13 = 10 (ADDI x13, x4, -5 = 15-5)
        expected_regs[14] = 32'h0000000F;  // x14 = 15 (ADD x14, x13, x5 = 10+5)
    end
    
    // Test sequence
    initial begin
        $display("TEST START");
        $display("========================================");
        $display("Out-of-Order CPU Core Testbench");
        $display("========================================");
        
        // Initialize signals
        reset = 1;
        cycle_count = 0;
        test_passed = 1'b1;
        test_complete = 1'b0;
        
        // Hold reset for a few cycles
        repeat(5) @(posedge clock);
        reset = 0;
        $display("Time %0t: Reset deasserted, CPU starting execution", $time);
        
        // Run for enough cycles to complete the program
        // The program has 16 instructions in ROM
        // With out-of-order execution, it should complete in ~50-100 cycles
        repeat(200) @(posedge clock) begin
            cycle_count++;
        end
        
        $display("\nTime %0t: Execution complete after %0d cycles", $time, cycle_count);
        test_complete = 1'b1;
        
        // Wait a few more cycles for pipeline to drain
        repeat(10) @(posedge clock);
        
        // Check register file contents
        $display("\n========================================");
        $display("Register File Verification");
        $display("========================================");
        
        check_registers();
        
        // Final result
        $display("\n========================================");
        if (test_passed) begin
            $display("TEST PASSED");
            $display("All register values match expected results!");
        end else begin
            $display("TEST FAILED");
            $display("Some register values do not match!");
            $error("Test failed - register mismatches detected");
        end
        $display("========================================");
        
        $finish;
    end
    
    // Task to check register values
    task check_registers();
        logic [31:0] actual_value;
        int errors;
        errors = 0;
        
        $display("\nReg | Expected   | Actual     | Status");
        $display("----|------------|------------|--------");
        
        for (int i = 0; i < 15; i++) begin
            // Access register file through the DUT
            actual_value = dut.i_regfile.arch_regs[i];
            
            if (actual_value !== expected_regs[i]) begin
                $display("LOG: %0t : ERROR : tb_ooo_cpu_core : dut.i_regfile.arch_regs[%0d] : expected_value: 0x%08h actual_value: 0x%08h", 
                         $time, i, expected_regs[i], actual_value);
                $display("x%-2d | 0x%08h | 0x%08h | FAIL", i, expected_regs[i], actual_value);
                errors++;
                test_passed = 1'b0;
            end else begin
                $display("x%-2d | 0x%08h | 0x%08h | PASS", i, expected_regs[i], actual_value);
            end
        end
        
        if (errors > 0) begin
            $display("\nTotal errors: %0d", errors);
        end else begin
            $display("\nAll checked registers match!");
        end
    endtask
    
    // Monitor key signals during execution
    always @(posedge clock) begin
        if (!reset && !test_complete) begin
            // Monitor commits
            if (dut.commit_valid && dut.commit_reg_write) begin
                $display("LOG: %0t : INFO : tb_ooo_cpu_core : dut.commit_dest_reg : expected_value: commit actual_value: x%0d = 0x%08h", 
                         $time, dut.commit_dest_reg, dut.commit_value);
            end
            
            // Monitor dispatch
            if (dut.dispatch_valid) begin
                $display("LOG: %0t : INFO : tb_ooo_cpu_core : dut.dispatch_valid : expected_value: dispatch actual_value: alu_op=%0d dest=x%0d", 
                         $time, dut.dispatch_alu_op, dut.rob_dest_reg);
            end
            
            // Monitor issues
            if (dut.issue_valid) begin
                $display("LOG: %0t : INFO : tb_ooo_cpu_core : dut.issue_valid : expected_value: issue actual_value: alu_op=%0d tag=%0d", 
                         $time, dut.issue_alu_op, dut.issue_dest_tag);
            end
            
            // Monitor CDB broadcasts
            if (dut.cdb_valid) begin
                $display("LOG: %0t : INFO : tb_ooo_cpu_core : dut.cdb_valid : expected_value: cdb actual_value: tag=%0d data=0x%08h", 
                         $time, dut.cdb_tag, dut.cdb_data);
            end
        end
    end
    
    // Timeout watchdog
    initial begin
        #50000;  // 50us timeout
        $display("\nERROR: Simulation timeout!");
        $display("TEST FAILED");
        $error("Simulation exceeded maximum time limit");
        $finish;
    end
    
    // Waveform dumping
    initial begin
        $dumpfile("dumpfile.fst");
        $dumpvars(0);
    end

endmodule