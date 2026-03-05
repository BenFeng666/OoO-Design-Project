module imm_gen (
    input wire [31:0] instruction,
    output reg [31:0] imm
);

always @(*) 
begin
    case (instruction[6:0])

    7'b0010011: imm= {{20{instruction[31]}},{instruction[31:20]}};//I type
    7'b0100011: imm= {{20{instruction[31]}},{instruction[31:25]},{instruction[11:7]}};//S type
    7'b1100011: imm= {{19{instruction[31]}},{instruction[31]},{instruction[7]},{instruction[30:25]},{instruction[11:8]},1'b0};//B type
    7'b0110111: imm= {{instruction[31:12]},12'b0};//u type
    7'b1101111: imm= {{11{instruction[31]}},{instruction[31]},{instruction[19:12]},{instruction[20]},{instruction[30:21]},1'b0};//j type
    default: imm=32'b0;
    endcase


end
endmodule



