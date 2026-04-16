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

    $display("\n==================================================");
    $display("TEST 11: MIXED OoO STRESS (ADD/MUL/LW/SW/BEQ/JAL/ADDI)");
    $display("==================================================");

    clear_imem;
    reset_core;
    clear_regfile;
    preload_basic_regs;

    // extra init
    uut.u_reg_file.store_unit[8]  = 32'd0;
    uut.u_reg_file.store_unit[9]  = 32'd0;
    uut.u_reg_file.store_unit[10] = 32'd0;
    uut.u_reg_file.store_unit[11] = 32'd0;
    uut.u_reg_file.store_unit[12] = 32'd0;
    uut.u_reg_file.store_unit[13] = 32'd0;
    uut.u_reg_file.store_unit[14] = 32'd0;
    uut.u_reg_file.store_unit[15] = 32'd0;

    // clear data memory too

    // ------------------------------------------------------------
    // Program layout
    //
    // x1 = 7, x2 = 3, x6 = 2, x7 = 5
    //
    // 0  sub  x3,  x1, x2      -> 4
    // 1  mul  x4,  x1, x2      -> 21
    // 2  mul  x5,  x6, x7      -> 10
    // 3  add  x8,  x1, x1      -> 14
    // 4  addi x9,  x3, 8       -> 12
    // 5  sw   x8,  0(x0)       -> mem[0] = 14
    // 6  lw   x10, 0(x0)       -> 14
    // 7  add  x11, x10, x3     -> 18
    // 8  beq  x3,  x3, +8      -> taken, skip next addi
    // 9  addi x12, x0, 99      -> should be skipped if beq works
    // 10 jal  x13, +8          -> x13 = PC+4, skip next add
    // 11 add  x14, x1, x2      -> should be skipped if jal works
    // 12 addi x15, x0, 55      -> executes after jal target
    // ------------------------------------------------------------

    uut.u_imem.inst_mem[0]  = 32'h402081b3; // sub  x3,  x1, x2
    uut.u_imem.inst_mem[1]  = 32'h02208233; // mul  x4,  x1, x2
    uut.u_imem.inst_mem[2]  = 32'h027302b3; // mul  x5,  x6, x7
    uut.u_imem.inst_mem[3]  = 32'h00108433; // add  x8,  x1, x1
    uut.u_imem.inst_mem[4]  = 32'h00818493; // addi x9,  x3, 8
    uut.u_imem.inst_mem[5]  = 32'h00802023; // sw   x8,  0(x0)
    uut.u_imem.inst_mem[6]  = 32'h00002503; // lw   x10, 0(x0)
    uut.u_imem.inst_mem[7]  = 32'h003505b3; // add  x11, x10, x3
    uut.u_imem.inst_mem[8]  = 32'h00318463; // beq  x3,  x3, +8
    uut.u_imem.inst_mem[9]  = 32'h06300613; // addi x12, x0, 99
    uut.u_imem.inst_mem[10] = 32'h008006ef; // jal  x13, +8
    uut.u_imem.inst_mem[11] = 32'h00208733; // add  x14, x1, x2
    uut.u_imem.inst_mem[12] = 32'h03700793; // addi x15, x0, 55

    // fill rest with nops
    uut.u_imem.inst_mem[13] = 32'h00000013;
    uut.u_imem.inst_mem[14] = 32'h00000013;
    uut.u_imem.inst_mem[15] = 32'h00000013;
    uut.u_imem.inst_mem[16] = 32'h00000013;
    uut.u_imem.inst_mem[17] = 32'h00000013;
    uut.u_imem.inst_mem[18] = 32'h00000013;
    uut.u_imem.inst_mem[19] = 32'h00000013;

    run_cycles(80);

    $display("FINAL REG CHECK:");
    $display("x3  = %0d (expect 4)",  uut.u_reg_file.store_unit[3]);
    $display("x4  = %0d (expect 21)", uut.u_reg_file.store_unit[4]);
    $display("x5  = %0d (expect 10)", uut.u_reg_file.store_unit[5]);
    $display("x8  = %0d (expect 14)", uut.u_reg_file.store_unit[8]);
    $display("x9  = %0d (expect 12)", uut.u_reg_file.store_unit[9]);
    $display("x10 = %0d (expect 14 if lw/sw work)", uut.u_reg_file.store_unit[10]);
    $display("x11 = %0d (expect 18 if lw works)",   uut.u_reg_file.store_unit[11]);
    $display("x12 = %0d (expect 0 if beq works)",   uut.u_reg_file.store_unit[12]);
    $display("x13 = %0d (expect nonzero PC+4 if jal works)", uut.u_reg_file.store_unit[13]);
    $display("x14 = %0d (expect 0 if jal skips add)", uut.u_reg_file.store_unit[14]);
    $display("x15 = %0d (expect 55 if jal target works)", uut.u_reg_file.store_unit[15]);
    $display("mem check skipped: internal data_mem array name not exposed");
    $display("ROB head=%0d valid=%b ready=%b is_store=%b is_branch=%b is_jump=%b",
         uut.u_rob.head,
         uut.u_rob.valid[uut.u_rob.head],
         uut.u_rob.ready[uut.u_rob.head],
         uut.u_rob.is_store[uut.u_rob.head],
         uut.u_rob.is_branch[uut.u_rob.head],
         uut.u_rob.is_jump[uut.u_rob.head]);

    $display("SW/LW dbg: issue_sw=%b sw_tag=%0d sw_data=%0d issue_lw=%b lw_addr=%0d cdb_valid=%b cdb_tag=%0d cdb_val=%0d",
         uut.issue_mem_write1, uut.issue_dest_tag1, uut.ex1_store_data,
         uut.issue_mem_read1, uut.alu1_result,
         uut.cdb_valid0, uut.cdb_tag0, uut.cdb_value0);

    // Base arithmetic pass condition
    if (uut.u_reg_file.store_unit[3]  == 32'd4  &&
        uut.u_reg_file.store_unit[4]  == 32'd21 &&
        uut.u_reg_file.store_unit[5]  == 32'd10 &&
        uut.u_reg_file.store_unit[8]  == 32'd14 &&
        uut.u_reg_file.store_unit[9]  == 32'd12) begin
        $display("TEST 11 BASE ARITH PASS");
        pass_count = pass_count + 1;
    end else begin
        $display("TEST 11 BASE ARITH FAIL");
    end

    $display("\n==================================================");
    $display("TOTAL PASSED = %0d / 1", pass_count);
    $display("==================================================");

    $finish;
end

endmodule
