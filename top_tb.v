
`timescale 1ns/1ps

module top_tb;

reg clk;
reg rst;
integer i;
integer pass_count;

// DUT
top uut (
    .clk(clk),
    .rst(rst)
);

// clock
always #5 clk = ~clk;

// -------------------------
// helper tasks
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
    rst = 1'b0;
    #12;
    rst = 1'b1;
end
endtask

task show_pipeline_state;
begin
    $display("------------------------------------------------------------");
    $display("time = %0t", $time);
    $display("IF  : PC=%0d  inst=%h", uut.pc, uut.instruction);

    $display("ID  : inst=%h  rs1_data=%0d  rs2_data=%0d  imm=%0d",
             uut.id_instruction, uut.rs1_data, uut.rs2_data, uut.imm);

    $display("EX  : alu_in2=%0d  alu_result=%0d",
             uut.alu_in2, uut.alu_result);

    $display("MEM : alu_result=%0d  mem_data=%0d",
             uut.mem_alu_result, uut.mem_data);

    $display("WB  : wb_data=%0d", uut.wb_data);

    $display("REG : x1=%0d  x2=%0d  x3=%0d x4=%0d",
             uut.u_reg_file.store_unit[1],
             uut.u_reg_file.store_unit[2],
             uut.u_reg_file.store_unit[3],
             uut.u_reg_file.store_unit[4]);
end
endtask

task run_cycles_with_trace;
input integer n;
integer j;
begin
    for (j = 0; j < n; j = j + 1) begin
        @(posedge clk);
        show_pipeline_state;
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

    $dumpfile("tb_pipeline_trace.vcd");
    $dumpvars(0, top_tb);

    // ============================================================
    // TEST 1: ADDI + ADD
    // ============================================================
    $display("\n============================================================");
    $display("==== TEST 1: ADDI + ADD ====");
    clear_imem;

    uut.u_imem.inst_mem[0] = 32'h00100093; // addi x1, x0, 1
    uut.u_imem.inst_mem[1] = 32'h00100113; // addi x2, x0, 1
    uut.u_imem.inst_mem[2] = 32'h00000013; // nop
    uut.u_imem.inst_mem[3] = 32'h00000013; // nop
    uut.u_imem.inst_mem[4] = 32'h00000013; // nop
    uut.u_imem.inst_mem[5] = 32'h002081b3; // add x3, x1, x2
    uut.u_imem.inst_mem[6] = 32'h00000013; // nop
    uut.u_imem.inst_mem[7] = 32'h00000013; // nop
    uut.u_imem.inst_mem[8] = 32'h00000013; // nop

    reset_core;
    run_cycles_with_trace(20);

    $display("FINAL RESULT TEST 1:");
    $display("x1 = %0d", uut.u_reg_file.store_unit[1]);
    $display("x2 = %0d", uut.u_reg_file.store_unit[2]);
    $display("x3 = %0d", uut.u_reg_file.store_unit[3]);

    if (uut.u_reg_file.store_unit[1] == 32'd1 &&
        uut.u_reg_file.store_unit[2] == 32'd1 &&
        uut.u_reg_file.store_unit[3] == 32'd2) begin
        $display("TEST 1 (ADDI + ADD): PASS");
        pass_count = pass_count + 1;
    end
    else begin
        $display("TEST 1 (ADDI + ADD): FAIL");
    end

    // ============================================================
    // TEST 2: SUB
    // ============================================================
    $display("\n============================================================");
    $display("==== TEST 2: SUB ====");
    clear_imem;

    uut.u_imem.inst_mem[0] = 32'h00700093; // addi x1, x0, 7
    uut.u_imem.inst_mem[1] = 32'h00300113; // addi x2, x0, 3
    uut.u_imem.inst_mem[2] = 32'h00000013; // nop
    uut.u_imem.inst_mem[3] = 32'h00000013; // nop
    uut.u_imem.inst_mem[4] = 32'h00000013; // nop
    uut.u_imem.inst_mem[5] = 32'h402081b3; // sub x3, x1, x2
    uut.u_imem.inst_mem[6] = 32'h00000013; // nop
    uut.u_imem.inst_mem[7] = 32'h00000013; // nop
    uut.u_imem.inst_mem[8] = 32'h00000013; // nop

    reset_core;
    run_cycles_with_trace(20);

    $display("FINAL RESULT TEST 2:");
    $display("x1 = %0d", uut.u_reg_file.store_unit[1]);
    $display("x2 = %0d", uut.u_reg_file.store_unit[2]);
    $display("x3 = %0d", uut.u_reg_file.store_unit[3]);

    if (uut.u_reg_file.store_unit[3] == 32'd4) begin
        $display("TEST 2 (SUB): PASS");
        pass_count = pass_count + 1;
    end
    else begin
        $display("TEST 2 (SUB): FAIL");
    end

    // ============================================================
    // TEST 3: MUL
    // only passes if your ALU/ALU_control support mul
    // ============================================================
    $display("\n============================================================");
    $display("==== TEST 3: MUL ====");
    clear_imem;

    uut.u_imem.inst_mem[0] = 32'h00300093; // addi x1, x0, 3
    uut.u_imem.inst_mem[1] = 32'h00400113; // addi x2, x0, 4
    uut.u_imem.inst_mem[2] = 32'h00000013; // nop
    uut.u_imem.inst_mem[3] = 32'h00000013; // nop
    uut.u_imem.inst_mem[4] = 32'h00000013; // nop
    uut.u_imem.inst_mem[5] = 32'h022081b3; // mul x3, x1, x2
    uut.u_imem.inst_mem[6] = 32'h00000013; // nop
    uut.u_imem.inst_mem[7] = 32'h00000013; // nop
    uut.u_imem.inst_mem[8] = 32'h00000013; // nop

    reset_core;
    run_cycles_with_trace(20);

    $display("FINAL RESULT TEST 3:");
    $display("x1 = %0d", uut.u_reg_file.store_unit[1]);
    $display("x2 = %0d", uut.u_reg_file.store_unit[2]);
    $display("x3 = %0d", uut.u_reg_file.store_unit[3]);

    if (uut.u_reg_file.store_unit[3] == 32'd12) begin
        $display("TEST 3 (MUL): PASS");
        pass_count = pass_count + 1;
    end
    else begin
        $display("TEST 3 (MUL): FAIL");
    end

    // ============================================================
    // TEST 4: SW / LW
    // ============================================================
    $display("\n============================================================");
    $display("==== TEST 4: SW / LW ====");
    clear_imem;

    uut.u_imem.inst_mem[0]  = 32'h00500093; // addi x1, x0, 5
    uut.u_imem.inst_mem[1]  = 32'h00000113; // addi x2, x0, 0
    uut.u_imem.inst_mem[2]  = 32'h00000013; // nop
    uut.u_imem.inst_mem[3]  = 32'h00000013; // nop
    uut.u_imem.inst_mem[4]  = 32'h00000013; // nop
    uut.u_imem.inst_mem[5]  = 32'h00112023; // sw x1, 0(x2)
    uut.u_imem.inst_mem[6]  = 32'h00000013; // nop
    uut.u_imem.inst_mem[7]  = 32'h00000013; // nop
    uut.u_imem.inst_mem[8]  = 32'h00012183; // lw x3, 0(x2)
    uut.u_imem.inst_mem[9]  = 32'h00000013; // nop
    uut.u_imem.inst_mem[10] = 32'h00000013; // nop
    uut.u_imem.inst_mem[11] = 32'h00000013; // nop

    reset_core;
    run_cycles_with_trace(24);

    $display("FINAL RESULT TEST 4:");
    $display("x1 = %0d", uut.u_reg_file.store_unit[1]);
    $display("x2 = %0d", uut.u_reg_file.store_unit[2]);
    $display("x3 = %0d", uut.u_reg_file.store_unit[3]);

    if (uut.u_reg_file.store_unit[3] == 32'd5) begin
        $display("TEST 4 (SW / LW): PASS");
        pass_count = pass_count + 1;
    end
    else begin
        $display("TEST 4 (SW / LW): FAIL");
    end

    $display("\n============================================================");
    $display("==== ALL TESTS FINISHED ====");
    $display("TOTAL PASSED: %0d / 4", pass_count);
    
    // ============================================================
// TEST 5: BEQ TAKEN
// x1 = 5
// x2 = 5
// beq x1, x2, +8   -> should skip next instruction
// addi x3, x0, 99  -> should be skipped
// addi x3, x0, 7   -> should execute
// expect x3 = 7
// ============================================================
$display("\n============================================================");
$display("==== TEST 5: BEQ TAKEN ====");
clear_imem;

uut.u_imem.inst_mem[0] = 32'h00500093; // addi x1, x0, 5
uut.u_imem.inst_mem[1] = 32'h00500113; // addi x2, x0, 5
uut.u_imem.inst_mem[2] = 32'h00000013; // nop
uut.u_imem.inst_mem[3] = 32'h00000013; // nop
uut.u_imem.inst_mem[4] = 32'h00000013; // nop
uut.u_imem.inst_mem[5] = 32'h00208463; // beq x1, x2, +8
uut.u_imem.inst_mem[6] = 32'h06300193; // addi x3, x0, 99  (skip)
uut.u_imem.inst_mem[7] = 32'h00700193; // addi x3, x0, 7   (take)
uut.u_imem.inst_mem[8] = 32'h00000013; // nop
uut.u_imem.inst_mem[9] = 32'h00000013; // nop
uut.u_imem.inst_mem[10] = 32'h00000013; // nop

reset_core;
run_cycles_with_trace(24);

$display("FINAL RESULT TEST 5:");
$display("x1 = %0d", uut.u_reg_file.store_unit[1]);
$display("x2 = %0d", uut.u_reg_file.store_unit[2]);
$display("x3 = %0d", uut.u_reg_file.store_unit[3]);

if (uut.u_reg_file.store_unit[3] == 32'd7) begin
    $display("TEST 5 (BEQ TAKEN): PASS");
    pass_count = pass_count + 1;
end
else begin
    $display("TEST 5 (BEQ TAKEN): FAIL");
end

// ============================================================
// TEST 6: BEQ NOT TAKEN
// x1 = 5
// x2 = 3
// beq x1, x2, +8   -> should NOT branch
// addi x3, x0, 99  -> should execute
// expect x3 = 99
// ============================================================
$display("\n============================================================");
$display("==== TEST 6: BEQ NOT TAKEN ====");
clear_imem;

uut.u_imem.inst_mem[0] = 32'h00500093; // addi x1, x0, 5
uut.u_imem.inst_mem[1] = 32'h00300113; // addi x2, x0, 3
uut.u_imem.inst_mem[2] = 32'h00000013; // nop
uut.u_imem.inst_mem[3] = 32'h00000013; // nop
uut.u_imem.inst_mem[4] = 32'h00000013; // nop
uut.u_imem.inst_mem[5] = 32'h00208463; // beq x1, x2, +8
uut.u_imem.inst_mem[6] = 32'h06300193; // addi x3, x0, 99
uut.u_imem.inst_mem[7] = 32'h00700213; // addi x4, x0, 7
uut.u_imem.inst_mem[8] = 32'h00000013; // nop
uut.u_imem.inst_mem[9] = 32'h00000013; // nop
uut.u_imem.inst_mem[10] = 32'h00000013; // nop

reset_core;
run_cycles_with_trace(24);

$display("FINAL RESULT TEST 6:");
$display("x1 = %0d", uut.u_reg_file.store_unit[1]);
$display("x2 = %0d", uut.u_reg_file.store_unit[2]);
$display("x3 = %0d", uut.u_reg_file.store_unit[3]);
$display("x4 = %0d", uut.u_reg_file.store_unit[4]);

if (uut.u_reg_file.store_unit[3] == 32'd99) begin
    $display("TEST 6 (BEQ NOT TAKEN): PASS");
    pass_count = pass_count + 1;
end
else begin
    $display("TEST 6 (BEQ NOT TAKEN): FAIL");
end

// ============================================================
// TEST 7: SW -> LW -> COMPUTE
// x1 = 8
// x2 = 0
// sw x1, 0(x2)
// lw x3, 0(x2)
// add x4, x3, x1
// expect x3 = 8, x4 = 16
// ============================================================
$display("\n============================================================");
$display("==== TEST 7: SW -> LW -> COMPUTE ====");
clear_imem;

uut.u_imem.inst_mem[0]  = 32'h00800093; // addi x1, x0, 8
uut.u_imem.inst_mem[1]  = 32'h00000113; // addi x2, x0, 0
uut.u_imem.inst_mem[2]  = 32'h00000013; // nop
uut.u_imem.inst_mem[3]  = 32'h00000013; // nop
uut.u_imem.inst_mem[4]  = 32'h00000013; // nop
uut.u_imem.inst_mem[5]  = 32'h00112023; // sw x1, 0(x2)
uut.u_imem.inst_mem[6]  = 32'h00000013; // nop
uut.u_imem.inst_mem[7]  = 32'h00000013; // nop
uut.u_imem.inst_mem[8]  = 32'h00012183; // lw x3, 0(x2)
uut.u_imem.inst_mem[9]  = 32'h00000013; // nop
uut.u_imem.inst_mem[10] = 32'h00000013; // nop
uut.u_imem.inst_mem[11] = 32'h00000013; // nop
uut.u_imem.inst_mem[12] = 32'h00118233; // add x4, x3, x1
uut.u_imem.inst_mem[13] = 32'h00000013; // nop
uut.u_imem.inst_mem[14] = 32'h00000013; // nop
uut.u_imem.inst_mem[15] = 32'h00000013; // nop

reset_core;
run_cycles_with_trace(30);

$display("FINAL RESULT TEST 7:");
$display("x1 = %0d", uut.u_reg_file.store_unit[1]);
$display("x2 = %0d", uut.u_reg_file.store_unit[2]);
$display("x3 = %0d", uut.u_reg_file.store_unit[3]);
$display("x4 = %0d", uut.u_reg_file.store_unit[4]);

if (uut.u_reg_file.store_unit[3] == 32'd8 &&
    uut.u_reg_file.store_unit[4] == 32'd16) begin
    $display("TEST 7 (SW -> LW -> COMPUTE): PASS");
    pass_count = pass_count + 1;
end
else begin
    $display("TEST 7 (SW -> LW -> COMPUTE): FAIL");
end
$finish;
end



endmodule
