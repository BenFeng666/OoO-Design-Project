module ImmGen(
    input [31:0] Instr,
    output reg [31:0] Imm
);
    always @(*) begin
        case(Instr[6:0])
            7'b0010011, 7'b0000011, 7'b1100111: // I-Type / Load / JALR
                Imm = {{20{Instr[31]}}, Instr[31:20]};
            7'b0100011: // S-Type (Store)
                Imm = {{20{Instr[31]}}, Instr[31:25], Instr[11:7]};
            7'b1100011: // B-Type (Branch)
                Imm = {{20{Instr[31]}}, Instr[7], Instr[30:25], Instr[11:8], 1'b0};
            default: Imm = 32'b0;
        endcase
    end
endmodule
