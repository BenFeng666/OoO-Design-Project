`timescale 1ns/1ps

module top_tb;

reg clk;
reg rst;
integer i;
integer pass_count;

top uut (
    .clk(clk),
    .rst(rst)
);

// -------------------------
// clock
// -------------------------
always #5 clk = ~clk;

// -------------------------
// helpers
// -------------------------
task clear_imem;
begin
    for (i = 0; i < 256; i = i + 1) begin
        uut.u_imem.inst_mem[i] = 32'h00000013; // nop
    end
end
endtask

task reset_core;
begin
    rst = 1'b1;
    #1;
    rst = 1'b0;   // active-low reset
    #1;
    rst = 1'b1;
    #1;
end
endtask

task clear_regfile;
begin
    for (i = 0; i < 32; i = i + 1) begin
        uut.u_reg_file.store_unit[i] = 32'd0;
    end
end
endtask

task preload_basic_regs;
begin
    uut.u_reg_file.store_unit[0] = 32'd0;
    uut.u_reg_file.store_unit[1] = 32'd7;
    uut.u_reg_file.store_unit[2] = 32'd3;
    uut.u_reg_file.store_unit[6] = 32'd2;
    uut.u_reg_file.store_unit[7] = 32'd5;
end
endtask

task show_state;
begin
    $display("--------------------------------------------------");
    $display("time=%0t", $time);
    $display("PC=%0d inst=%h", uut.pc, uut.instruction);

    $display("ID: inst=%h rs1_data=%0d rs2_data=%0d",
             uut.id_instruction, uut.rs1_data, uut.rs2_data);

    $display("DISPATCH: valid=%b op=%h dest_tag=%0d src1_ready=%b src1_tag=%0d src1_val=%0d src2_ready=%b src2_tag=%0d src2_val=%0d",
             uut.dispatch_valid_iq, uut.dispatch_op, uut.dispatch_dest_tag,
             uut.dispatch_src1_ready, uut.dispatch_src1_tag, uut.dispatch_src1_value,
             uut.dispatch_src2_ready, uut.dispatch_src2_tag, uut.dispatch_src2_value);

    $display("ISSUE0: valid=%b op=%h src1=%0d src2=%0d imm=%0d dest=%0d",
             uut.issue_valid0, uut.issue_alu_op0, uut.issue_src10, uut.issue_src20,
             uut.issue_imm0, uut.issue_dest_tag0);

    $display("ISSUE1: valid=%b op=%h src1=%0d src2=%0d imm=%0d dest=%0d",
             uut.issue_valid1, uut.issue_alu_op1, uut.issue_src11, uut.issue_src21,
             uut.issue_imm1, uut.issue_dest_tag1);

    $display("ALU0: result=%0d zero=%b neg=%b",
             uut.alu0_result, uut.alu0_zero, uut.alu0_negative);

    $display("ALU1: result=%0d zero=%b neg=%b",
             uut.alu1_result, uut.alu1_zero, uut.alu1_negative);

    $display("CDB: valid=%b tag=%0d value=%0d",
             uut.cdb_valid0, uut.cdb_tag0, uut.cdb_value0);

    $display("ROB: dispatch_idx=%0d commit_valid=%b commit_addr=x%0d commit_data=%0d",
             uut.dispatch_rob_idx, uut.commit_valid, uut.commit_addr, uut.commit_data);

    $display("REG: x1=%0d x2=%0d x3=%0d x4=%0d x5=%0d x6=%0d x7=%0d",
             uut.u_reg_file.store_unit[1],
             uut.u_reg_file.store_unit[2],
             uut.u_reg_file.store_unit[3],
             uut.u_reg_file.store_unit[4],
             uut.u_reg_file.store_unit[5],
             uut.u_reg_file.store_unit[6],
             uut.u_reg_file.store_unit[7]);
end
endtask

task run_cycles;
input integer n;
integer j;
begin
    for (j = 0; j < n; j = j + 1) begin
        @(posedge clk);
        #1;
        show_state;
    end
end
endtask

// -------------------------
// main
// -------------------------
initial begin
    clk = 1'b0;
    rst = 1'b1;
    pass_count = 0;

    $dumpfile("ooo_tb.vcd");
    $dumpvars(0, top_tb);

    // ============================================================
    // TEST 1: INDEPENDENT
    // add x3 = x1 + x2 = 10
    // sub x4 = x1 - x2 = 4
    // mul x5 = x1 * x2 = 21
    // ============================================================
    $display("\n==================================================");
    $display("TEST 1: INDEPENDENT ADD / SUB / MUL");
    $display("==================================================");

    clear_imem;
    reset_core;
    clear_regfile;
    preload_basic_regs;

    uut.u_imem.inst_mem[0] = 32'h002081b3; // add x3, x1, x2
    uut.u_imem.inst_mem[1] = 32'h40208233; // sub x4, x1, x2
    uut.u_imem.inst_mem[2] = 32'h022082b3; // mul x5, x1, x2
    uut.u_imem.inst_mem[3] = 32'h00000013;
    uut.u_imem.inst_mem[4] = 32'h00000013;
    uut.u_imem.inst_mem[5] = 32'h00000013;

    run_cycles(20);

    if (uut.u_reg_file.store_unit[3] == 32'd10 &&
        uut.u_reg_file.store_unit[4] == 32'd4  &&
        uut.u_reg_file.store_unit[5] == 32'd21) begin
        $display("TEST 1 PASS");
        pass_count = pass_count + 1;
    end else begin
        $display("TEST 1 FAIL");
    end

    // ============================================================
    // TEST 2: RAW chain
    // add x3 = 7+3 = 10
    // sub x4 = x3-3 = 7
    // mul x5 = x4*3 = 21
    // ============================================================
    $display("\n==================================================");
    $display("TEST 2: RAW DEPENDENCY CHAIN");
    $display("==================================================");

    clear_imem;
    reset_core;
    clear_regfile;
    preload_basic_regs;

    uut.u_imem.inst_mem[0] = 32'h002081b3; // add x3, x1, x2
    uut.u_imem.inst_mem[1] = 32'h40218233; // sub x4, x3, x2
    uut.u_imem.inst_mem[2] = 32'h022202b3; // mul x5, x4, x2
    uut.u_imem.inst_mem[3] = 32'h00000013;
    uut.u_imem.inst_mem[4] = 32'h00000013;
    uut.u_imem.inst_mem[5] = 32'h00000013;
    uut.u_imem.inst_mem[6] = 32'h00000013;

    run_cycles(24);

    if (uut.u_reg_file.store_unit[3] == 32'd10 &&
        uut.u_reg_file.store_unit[4] == 32'd7  &&
        uut.u_reg_file.store_unit[5] == 32'd21) begin
        $display("TEST 2 PASS");
        pass_count = pass_count + 1;
    end else begin
        $display("TEST 2 FAIL");
    end

    // ============================================================
    // TEST 3: WAW
    // add x3 = 10
    // sub x3 = 4
    // mul x3 = 21
    // final x3 must be youngest writer = 21
    // ============================================================
    $display("\n==================================================");
    $display("TEST 3: WAW SAME DEST");
    $display("==================================================");

    clear_imem;
    reset_core;
    clear_regfile;
    preload_basic_regs;

    uut.u_imem.inst_mem[0] = 32'h002081b3; // add x3, x1, x2   -> 10
    uut.u_imem.inst_mem[1] = 32'h402081b3; // sub x3, x1, x2   -> 4
    uut.u_imem.inst_mem[2] = 32'h022081b3; // mul x3, x1, x2   -> 21
    uut.u_imem.inst_mem[3] = 32'h00000013;
    uut.u_imem.inst_mem[4] = 32'h00000013;
    uut.u_imem.inst_mem[5] = 32'h00000013;

    run_cycles(24);

    if (uut.u_reg_file.store_unit[3] == 32'd21) begin
        $display("TEST 3 PASS");
        pass_count = pass_count + 1;
    end else begin
        $display("TEST 3 FAIL");
    end

    // ============================================================
    // TEST 4: RAW + WAW mixed
    // add x3 = 10
    // sub x3 = x3 - x2 = 7   (RAW on older x3, then WAW to same x3)
    // mul x4 = x3 * x2 = 21  (RAW on newest x3)
    // final x3 = 7, x4 = 21
    // ============================================================
    $display("\n==================================================");
    $display("TEST 4: RAW + WAW MIXED");
    $display("==================================================");

    clear_imem;
    reset_core;
    clear_regfile;
    preload_basic_regs;

    uut.u_imem.inst_mem[0] = 32'h002081b3; // add x3, x1, x2
    uut.u_imem.inst_mem[1] = 32'h402181b3; // sub x3, x3, x2
    uut.u_imem.inst_mem[2] = 32'h02218233; // mul x4, x3, x2
    uut.u_imem.inst_mem[3] = 32'h00000013;
    uut.u_imem.inst_mem[4] = 32'h00000013;
    uut.u_imem.inst_mem[5] = 32'h00000013;
    uut.u_imem.inst_mem[6] = 32'h00000013;

    run_cycles(26);

    if (uut.u_reg_file.store_unit[3] == 32'd7 &&
        uut.u_reg_file.store_unit[4] == 32'd21) begin
        $display("TEST 4 PASS");
        pass_count = pass_count + 1;
    end else begin
        $display("TEST 4 FAIL");
    end

    // ============================================================
    // TEST 5: multiple consumers of one producer
    // add x3 = 10
    // sub x4 = x3 - x2 = 7
    // mul x5 = x3 * x2 = 30
    // both x4 and x5 depend on same x3
    // ============================================================
    $display("\n==================================================");
    $display("TEST 5: ONE PRODUCER, TWO CONSUMERS");
    $display("==================================================");

    clear_imem;
    reset_core;
    clear_regfile;
    preload_basic_regs;

    uut.u_imem.inst_mem[0] = 32'h002081b3; // add x3, x1, x2
    uut.u_imem.inst_mem[1] = 32'h40218233; // sub x4, x3, x2
    uut.u_imem.inst_mem[2] = 32'h022182b3; // mul x5, x3, x2
    uut.u_imem.inst_mem[3] = 32'h00000013;
    uut.u_imem.inst_mem[4] = 32'h00000013;
    uut.u_imem.inst_mem[5] = 32'h00000013;
    uut.u_imem.inst_mem[6] = 32'h00000013;

    run_cycles(26);

    if (uut.u_reg_file.store_unit[3] == 32'd10 &&
        uut.u_reg_file.store_unit[4] == 32'd7  &&
        uut.u_reg_file.store_unit[5] == 32'd30) begin
        $display("TEST 5 PASS");
        pass_count = pass_count + 1;
    end else begin
        $display("TEST 5 FAIL");
    end

    // ============================================================
    // TEST 6: longer mixed chain
    // x1=7 x2=3 x6=2
    // add x3 = 10
    // sub x4 = x3 - x2 = 7
    // mul x5 = x4 * x6 = 14
    // add x3 = x5 + x2 = 17   (WAW on x3, RAW on x5)
    // final x3=17 x4=7 x5=14
    // ============================================================
    $display("\n==================================================");
    $display("TEST 6: LONGER RAW/WAW CHAIN");
    $display("==================================================");

    clear_imem;
    reset_core;
    clear_regfile;
    preload_basic_regs;

    uut.u_imem.inst_mem[0] = 32'h002081b3; // add x3, x1, x2
    uut.u_imem.inst_mem[1] = 32'h40218233; // sub x4, x3, x2
    uut.u_imem.inst_mem[2] = 32'h026202b3; // mul x5, x4, x6
    uut.u_imem.inst_mem[3] = 32'h002281b3; // add x3, x5, x2
    uut.u_imem.inst_mem[4] = 32'h00000013;
    uut.u_imem.inst_mem[5] = 32'h00000013;
    uut.u_imem.inst_mem[6] = 32'h00000013;
    uut.u_imem.inst_mem[7] = 32'h00000013;

    run_cycles(30);

    if (uut.u_reg_file.store_unit[3] == 32'd17 &&
        uut.u_reg_file.store_unit[4] == 32'd7  &&
        uut.u_reg_file.store_unit[5] == 32'd14) begin
        $display("TEST 6 PASS");
        pass_count = pass_count + 1;
    end else begin
        $display("TEST 6 FAIL");
    end

    // ============================================================
    // TEST 7: OLDER SLOW OP, YOUNGER FAST OP
    // x1=7 x2=3 x6=2 x7=5
    //
    // inst0: mul x3 = x1 * x7 = 35   (older, should be slow if MUL is multi-cycle)
    // inst1: add x4 = x6 + x2 = 5    (younger, independent, should finish earlier)
    //
    // OoO proof goal:
    // - younger add may execute/finish before older mul
    // - but ROB must still commit x3 first, then x4
    //
    // final architectural state must be:
    // x3 = 35
    // x4 = 5
    // ============================================================
    $display("\n==================================================");
    $display("TEST 7: OLDER SLOW OP, YOUNGER FAST OP");
    $display("==================================================");

    clear_imem;
    reset_core;
    clear_regfile;
    preload_basic_regs;

    uut.u_imem.inst_mem[0] = 32'h027081b3; // mul x3, x1, x7   -> 7*5 = 35
    uut.u_imem.inst_mem[1] = 32'h00230233; // add x4, x6, x2   -> 2+3 = 5
    uut.u_imem.inst_mem[2] = 32'h00000013;
    uut.u_imem.inst_mem[3] = 32'h00000013;
    uut.u_imem.inst_mem[4] = 32'h00000013;
    uut.u_imem.inst_mem[5] = 32'h00000013;
    uut.u_imem.inst_mem[6] = 32'h00000013;
    uut.u_imem.inst_mem[7] = 32'h00000013;

    run_cycles(30);

    if (uut.u_reg_file.store_unit[3] == 32'd35 &&
        uut.u_reg_file.store_unit[4] == 32'd5) begin
        $display("TEST 7 PASS");
        pass_count = pass_count + 1;
    end else begin
        $display("TEST 7 FAIL");
    end

    // ============================================================
    // TEST 8: THREE-INSTRUCTION RAW CHAIN + ONE INDEPENDENT YOUNGER
    // x1=7 x2=3 x7=5
    //
    // add x3 = x1 + x2 = 10
    // sub x4 = x3 - x2 = 7      (depends on x3)
    // mul x5 = x4 * x2 = 21     (depends on x4)
    // add x6 = x7 + x2 = 8      (independent younger instruction)
    //
    // Goal:
    // - first three are chained and should serialize by dependency
    // - fourth is independent and should be able to execute earlier
    //   once you have enough execution resources
    // - commit must still remain in order
    //
    // final: x3=10, x4=7, x5=21, x6=8
    // ============================================================
    $display("\n==================================================");
    $display("TEST 8: RAW CHAIN + INDEPENDENT YOUNGER");
    $display("==================================================");

    clear_imem;
    reset_core;
    clear_regfile;
    preload_basic_regs;

    uut.u_imem.inst_mem[0] = 32'h002081b3; // add x3, x1, x2   -> 10
    uut.u_imem.inst_mem[1] = 32'h40218233; // sub x4, x3, x2   -> 7
    uut.u_imem.inst_mem[2] = 32'h022202b3; // mul x5, x4, x2   -> 21
    uut.u_imem.inst_mem[3] = 32'h00238333; // add x6, x7, x2   -> 8
    uut.u_imem.inst_mem[4] = 32'h00000013;
    uut.u_imem.inst_mem[5] = 32'h00000013;
    uut.u_imem.inst_mem[6] = 32'h00000013;
    uut.u_imem.inst_mem[7] = 32'h00000013;
    uut.u_imem.inst_mem[8] = 32'h00000013;

    run_cycles(32);

    if (uut.u_reg_file.store_unit[3] == 32'd10 &&
        uut.u_reg_file.store_unit[4] == 32'd7  &&
        uut.u_reg_file.store_unit[5] == 32'd21 &&
        uut.u_reg_file.store_unit[6] == 32'd8) begin
        $display("TEST 8 PASS");
        pass_count = pass_count + 1;
    end else begin
        $display("TEST 8 FAIL");
    end

        // ============================================================
    // TEST 9: TRUE OVERTAKE CHECK
    // Goal:
    //   inst0 produces x3
    //   inst1 waits on x4 (not ready yet)
    //   inst2 is independent and should execute before inst1
    //   inst3 later produces x4 so inst1 can finally run
    //
    // Program:
    //   0: add x3, x1, x2      -> 10
    //   1: add x5, x4, x2      -> waits for x4
    //   2: add x6, x7, x2      -> 8   (independent younger)
    //   3: add x4, x1, x1      -> 14  (finally makes x4 ready)
    //
    // Expected final:
    //   x3 = 10
    //   x4 = 14
    //   x5 = 17
    //   x6 = 8
    //
    // What to look for in the log:
    //   x6 instruction should ISSUE/EXECUTE before x5 instruction
    //   but commit should still be x3 -> x5 -> x6 -> x4 only if your ROB
    //   preserves original dispatch order, or according to your actual
    //   instruction order:
    //     inst0(x3), inst1(x5), inst2(x6), inst3(x4)
    //   So even if x6 finishes early, it must not commit before x5.
    // ============================================================
    $display("\n==================================================");
    $display("TEST 9: TRUE OVERTAKE CHECK");
    $display("==================================================");

    clear_imem;
    reset_core;
    clear_regfile;
    preload_basic_regs;

    uut.u_imem.inst_mem[0] = 32'h002081b3; // add x3, x1, x2   -> 10
    uut.u_imem.inst_mem[1] = 32'h002202b3; // add x5, x4, x2   -> waits for x4
    uut.u_imem.inst_mem[2] = 32'h00238333; // add x6, x7, x2   -> 8
    uut.u_imem.inst_mem[3] = 32'h00108233; // add x4, x1, x1   -> 14
    uut.u_imem.inst_mem[4] = 32'h00000013;
    uut.u_imem.inst_mem[5] = 32'h00000013;
    uut.u_imem.inst_mem[6] = 32'h00000013;
    uut.u_imem.inst_mem[7] = 32'h00000013;
    uut.u_imem.inst_mem[8] = 32'h00000013;
    uut.u_imem.inst_mem[9] = 32'h00000013;

    run_cycles(36);

    if (uut.u_reg_file.store_unit[3] == 32'd10 &&
        uut.u_reg_file.store_unit[4] == 32'd14 &&
        uut.u_reg_file.store_unit[5] == 32'd17 &&
        uut.u_reg_file.store_unit[6] == 32'd8) begin
        $display("TEST 9 PASS");
        pass_count = pass_count + 1;
    end else begin
        $display("TEST 9 FAIL");
    end

    $display("\n==================================================");
    $display("TOTAL PASSED = %0d / 8", pass_count);
    $display("==================================================");

    $finish;
end

endmodule
