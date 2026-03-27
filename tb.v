`timescale 1ns/1ps

module top_tb;

reg clk;
reg rst;

top uut (
    .clk(clk),
    .rst(rst)
);

always #5 clk = ~clk;

initial begin
    clk = 0;
    rst = 0;

    #10;
    rst = 1;
    $monitor("time=%0t PC=%0d instruction=%h", $time, uut.pc, uut.instruction);

    #100;

    $display("x1 = %0d", uut.u_reg_file.store_unit[1]);
    $display("x2 = %0d", uut.u_reg_file.store_unit[2]);
    $display("x3 = %0d", uut.u_reg_file.store_unit[3]);

    if (uut.u_reg_file.store_unit[3] == 32'd2)
        $display("PASS: 1 + 1 = 2");
    else
        $display("FAIL: x3 != 2");

    $finish;
end

endmodule
