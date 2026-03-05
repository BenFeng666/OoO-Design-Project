module instruction_mem(
    input wire [31:0] addr,
    output reg [31:0] instruction
);

reg [31:0] inst_mem [256];

always @(*) begin
    instruction = inst_mem[addr]
end
endmodule
