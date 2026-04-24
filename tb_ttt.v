`timescale 1ns/1ps

module top_tb;

reg clk;
reg rst;

integer stdin_handle;
integer scan_ok;
integer user_move;
integer player_id;
integer move_count;

top uut (
    .clk(clk),
    .rst(rst)
);

// Clock
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

function [7:0] mark;
    input [31:0] value;
    begin
        if (value == 32'd1)
            mark = "X";
        else if (value == 32'd2)
            mark = "O";
        else
            mark = "_";
    end
endfunction

task print_board;
    begin
        $display("\nCurrent board:");
        $display(" %s | %s | %s ",
            mark(uut.u_data_mem.data_mem[0]),
            mark(uut.u_data_mem.data_mem[1]),
            mark(uut.u_data_mem.data_mem[2])
        );
        $display("---+---+---");
        $display(" %s | %s | %s ",
            mark(uut.u_data_mem.data_mem[3]),
            mark(uut.u_data_mem.data_mem[4]),
            mark(uut.u_data_mem.data_mem[5])
        );
        $display("---+---+---");
        $display(" %s | %s | %s ",
            mark(uut.u_data_mem.data_mem[6]),
            mark(uut.u_data_mem.data_mem[7]),
            mark(uut.u_data_mem.data_mem[8])
        );
        $display("----------------------");
    end
endtask

function integer is_occupied;
    input integer pos;
    begin
        if (uut.u_data_mem.data_mem[pos] != 32'd0)
            is_occupied = 1;
        else
            is_occupied = 0;
    end
endfunction

function integer check_win;
    input [31:0] p;
    begin
        check_win = 0;

        // Top row: 0, 1, 2
        if (uut.u_data_mem.data_mem[0] == p &&
            uut.u_data_mem.data_mem[1] == p &&
            uut.u_data_mem.data_mem[2] == p)
            check_win = 1;

        // Middle row: 3, 4, 5
        if (uut.u_data_mem.data_mem[3] == p &&
            uut.u_data_mem.data_mem[4] == p &&
            uut.u_data_mem.data_mem[5] == p)
            check_win = 1;

        // Bottom row: 6, 7, 8
        if (uut.u_data_mem.data_mem[6] == p &&
            uut.u_data_mem.data_mem[7] == p &&
            uut.u_data_mem.data_mem[8] == p)
            check_win = 1;

        // Left column: 0, 3, 6
        if (uut.u_data_mem.data_mem[0] == p &&
            uut.u_data_mem.data_mem[3] == p &&
            uut.u_data_mem.data_mem[6] == p)
            check_win = 1;

        // Middle column: 1, 4, 7
        if (uut.u_data_mem.data_mem[1] == p &&
            uut.u_data_mem.data_mem[4] == p &&
            uut.u_data_mem.data_mem[7] == p)
            check_win = 1;

        // Right column: 2, 5, 8
        if (uut.u_data_mem.data_mem[2] == p &&
            uut.u_data_mem.data_mem[5] == p &&
            uut.u_data_mem.data_mem[8] == p)
            check_win = 1;

        // Diagonal: 0, 4, 8
        if (uut.u_data_mem.data_mem[0] == p &&
            uut.u_data_mem.data_mem[4] == p &&
            uut.u_data_mem.data_mem[8] == p)
            check_win = 1;

        // Diagonal: 2, 4, 6
        if (uut.u_data_mem.data_mem[2] == p &&
            uut.u_data_mem.data_mem[4] == p &&
            uut.u_data_mem.data_mem[6] == p)
            check_win = 1;
    end
endfunction

task make_move;
    input integer move_pos;
    input integer player_num;
    begin
        $display("\nHuman chooses cell %0d, player = %0d", move_pos, player_num);

        // Testbench acts like a memory-mapped input device.
        // It directly writes the selected move into board memory.
        @(negedge clk);
        uut.u_data_mem.data_mem[move_pos] = player_num;

        @(posedge clk);
        print_board();
    end
endtask

initial begin
    stdin_handle = 32'h80000000; // stdin for vvp

    // Reset once
    rst = 0;
    #30;
    rst = 1;
    #30;

    // Clear board
    uut.u_data_mem.data_mem[0] = 0;
    uut.u_data_mem.data_mem[1] = 0;
    uut.u_data_mem.data_mem[2] = 0;
    uut.u_data_mem.data_mem[3] = 0;
    uut.u_data_mem.data_mem[4] = 0;
    uut.u_data_mem.data_mem[5] = 0;
    uut.u_data_mem.data_mem[6] = 0;
    uut.u_data_mem.data_mem[7] = 0;
    uut.u_data_mem.data_mem[8] = 0;

    player_id = 1;
    move_count = 0;

    $display("\nTic Tac Toe Keyboard Demo");
    $display("Type a move from 0 to 8, then press Enter.");
    $display("Board positions:");
    $display(" 0 | 1 | 2 ");
    $display("---+---+---");
    $display(" 3 | 4 | 5 ");
    $display("---+---+---");
    $display(" 6 | 7 | 8 ");
    $display("Type 9 to quit.");

    print_board();

    while (1) begin
        if (player_id == 1)
            $write("\nPlayer X, enter move: ");
        else
            $write("\nPlayer O, enter move: ");

        scan_ok = $fscanf(stdin_handle, "%d", user_move);

        if (scan_ok != 1) begin
            $display("Input error. Ending simulation.");
            $finish;
        end

        if (user_move == 9) begin
            $display("Quit.");
            $finish;
        end

        if (user_move < 0 || user_move > 8) begin
            $display("Invalid move. Use 0 to 8.");
        end
        else if (is_occupied(user_move)) begin
            $display("Cell %0d is already occupied. Try again.", user_move);
        end
        else begin
            make_move(user_move, player_id);
            move_count = move_count + 1;

            if (check_win(player_id)) begin
                if (player_id == 1)
                    $display("\nX wins!");
                else
                    $display("\nO wins!");

                $finish;
            end

            if (move_count == 9) begin
                $display("\nDraw!");
                $finish;
            end

            if (player_id == 1)
                player_id = 2;
            else
                player_id = 1;
        end
    end
end

endmodule
