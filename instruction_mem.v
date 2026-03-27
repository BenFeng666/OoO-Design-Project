module instruction_mem(
    input wire [31:0] addr,
    output reg [31:0] instruction
);

reg [31:0] inst_mem [0:255];
integer i;

initial begin
    // clear all memory first
    for (i = 0; i < 256; i = i + 1)
        inst_mem[i] = 32'b0;

    // program
    inst_mem[0] = 32'h00500093; // x1 = 5
    inst_mem[1] = 32'hFFD00113; // x2 = -3
    inst_mem[2] = 32'h002081b3; // x3 = x1 + x2
    

end

always @(*) begin
    instruction = inst_mem[addr[9:2]];
end

endmodule
