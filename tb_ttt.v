`timescale 1ns/1ps

module top_tb;

reg clk;
reg rst;
integer i;

integer cycle_count;
integer commit_count;
integer stable_count;
real cpi;

top uut (
    .clk(clk),
    .rst(rst)
);

always #5 clk = ~clk;

// Final board:
// X | X | X
// _ | O | _
// _ | _ | O
wire final_state_ok;

assign final_state_ok =
    uut.u_reg_file.store_unit[10] == 32'd1 && // cell 0 = X
    uut.u_reg_file.store_unit[11] == 32'd1 && // cell 1 = X
    uut.u_reg_file.store_unit[12] == 32'd1 && // cell 2 = X
    uut.u_reg_file.store_unit[13] == 32'd0 && // cell 3 = empty
    uut.u_reg_file.store_unit[14] == 32'd2 && // cell 4 = O
    uut.u_reg_file.store_unit[15] == 32'd0 && // cell 5 = empty
    uut.u_reg_file.store_unit[16] == 32'd0 && // cell 6 = empty
    uut.u_reg_file.store_unit[17] == 32'd0 && // cell 7 = empty
    uut.u_reg_file.store_unit[18] == 32'd2 && // cell 8 = O
    uut.u_reg_file.store_unit[19] == 32'd1 && // winner = X
    commit_count >= 6;

task clear_imem;
begin
    for (i = 0; i < 256; i = i + 1)
        uut.u_imem.inst_mem[i] = 32'h00000013; // nop
end
endtask

task reset_core;
begin
    rst = 1'b1;
    #1;
    rst = 1'b0;
    #1;
    rst = 1'b1;
    #1;
end
endtask

task clear_regfile;
begin
    for (i = 0; i < 32; i = i + 1)
        uut.u_reg_file.store_unit[i] = 32'd0;
end
endtask

task load_program;
begin
    clear_imem;

    // ------------------------------------------------------------
    // Tic Tac Toe scripted moves using RISC-V binary instructions
    //
    // addi x10, x0, 1   // X moves to cell 0
    // addi x14, x0, 2   // O moves to cell 4
    // addi x11, x0, 1   // X moves to cell 1
    // addi x18, x0, 2   // O moves to cell 8
    // addi x12, x0, 1   // X moves to cell 2
    // addi x19, x0, 1   // winner = X
    // ------------------------------------------------------------

    uut.u_imem.inst_mem[0] = 32'h00100513; // addi x10, x0, 1
    uut.u_imem.inst_mem[1] = 32'h00200713; // addi x14, x0, 2
    uut.u_imem.inst_mem[2] = 32'h00100593; // addi x11, x0, 1
    uut.u_imem.inst_mem[3] = 32'h00200913; // addi x18, x0, 2
    uut.u_imem.inst_mem[4] = 32'h00100613; // addi x12, x0, 1
    uut.u_imem.inst_mem[5] = 32'h00100993; // addi x19, x0, 1

    for (i = 6; i < 80; i = i + 1)
        uut.u_imem.inst_mem[i] = 32'h00000013;
end
endtask

task print_cell;
input [31:0] v;
begin
    if (v == 32'd1)
        $write(" X ");
    else if (v == 32'd2)
        $write(" O ");
    else
        $write(" _ ");
end
endtask

task print_board;
begin
    $display("");
    print_cell(uut.u_reg_file.store_unit[10]);
    $write("|");
    print_cell(uut.u_reg_file.store_unit[11]);
    $write("|");
    print_cell(uut.u_reg_file.store_unit[12]);
    $display("");
    $display("---+---+---");
    print_cell(uut.u_reg_file.store_unit[13]);
    $write("|");
    print_cell(uut.u_reg_file.store_unit[14]);
    $write("|");
    print_cell(uut.u_reg_file.store_unit[15]);
    $display("");
    $display("---+---+---");
    print_cell(uut.u_reg_file.store_unit[16]);
    $write("|");
    print_cell(uut.u_reg_file.store_unit[17]);
    $write("|");
    print_cell(uut.u_reg_file.store_unit[18]);
    $display("");
end
endtask

task show_state;
begin
    $display("cycle=%0d PC=%0d inst=%h commit=%b commit_count=%0d winner=%0d",
        cycle_count,
        uut.pc,
        uut.instruction,
        uut.commit_valid,
        commit_count,
        uut.u_reg_file.store_unit[19]);

    print_board;
end
endtask

task run_until_done;
begin : RUN_LOOP
    stable_count = 0;

    while (cycle_count < 100) begin
        @(posedge clk);
        #1;

        cycle_count = cycle_count + 1;

        if (uut.commit_valid)
            commit_count = commit_count + 1;

        show_state;

        if (final_state_ok)
            stable_count = stable_count + 1;
        else
            stable_count = 0;

        if (stable_count >= 3) begin
            $display("Final board stable. Stopping at cycle %0d.", cycle_count);
            disable RUN_LOOP;
        end
    end
end
endtask

initial begin
    clk = 1'b0;
    rst = 1'b1;

    cycle_count = 0;
    commit_count = 0;
    stable_count = 0;
    cpi = 0.0;

    $dumpfile("ooo_tictactoe_binary_tb.vcd");
    $dumpvars(0, top_tb);

    $display("\n==================================================");
    $display("OoO TIC TAC TOE BINARY-CODE DEMO");
    $display("X and O moves are real instructions");
    $display("==================================================");

    load_program;

    reset_core;
    #2;

    clear_regfile;

    run_until_done;

    if (commit_count > 0)
        cpi = cycle_count * 1.0 / commit_count;
    else
        cpi = 0.0;

    $display("\nFINAL TIC TAC TOE BOARD:");
    print_board;

    $display("\nWinner register x19 = %0d", uut.u_reg_file.store_unit[19]);
    $display("1 means X wins, 2 means O wins");

    $display("\n==================================================");
    $display("OoO TIC TAC TOE CPI RESULT");
    $display("Total cycles           = %0d", cycle_count);
    $display("Committed instructions = %0d", commit_count);
    $display("CPI = cycles / commits = %0.3f", cpi);
    $display("==================================================");

    if (final_state_ok)
        $display("TIC TAC TOE DEMO PASS: X wins top row");
    else
        $display("TIC TAC TOE DEMO FAIL");

    $finish;
end

endmodule
