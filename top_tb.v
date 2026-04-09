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

    $display("IQ: dispatch_valid=%b issue_valid=%b issue_op=%h issue_src1=%0d issue_src2=%0d issue_dest=%0d",
             uut.dispatch_valid_iq, uut.issue_valid, uut.issue_op,
             uut.issue_src1, uut.issue_src2, uut.issue_dest_tag);

    $display("CDB: valid=%b tag=%0d value=%0d",
             uut.cdb_valid, uut.cdb_tag, uut.cdb_value);

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

    $display("\n==================================================");
    $display("TOTAL PASSED = %0d / 7", pass_count);
    $display("==================================================");

    

    $finish;
end

endmodule
