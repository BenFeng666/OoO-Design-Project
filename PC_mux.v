module PC_mux (
    input wire [31:0] PC4,
    input wire [31:0] branch_target,
    input wire [31:0] jal_target,
    input wire [1:0] pc_sel, // 00 for pc4 01 for bt 11 for jal
    output reg [31:0] next_pc
);

always @(*) begin

    case (pc_sel)

    default: next_pc = PC4;
    2'b00: next_pc = PC4;

    2'b01: next_pc = branch_target;

    2'b11: next_pc = jal_target;
    endcase

    
end
endmodule
