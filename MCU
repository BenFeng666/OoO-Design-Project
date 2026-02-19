module ControlUnit(
    input [6:0] Opcode,
    output reg Branch, MemRead, MemtoReg, MemWrite, ALUSrc, RegWrite
);
    always @(*) begin
        // Defaults (Safety)
        {Branch, MemRead, MemtoReg, MemWrite, ALUSrc, RegWrite} = 6'b0;

        case(Opcode)
            7'b0110011: // R-Type (ADD, SUB...)
                {RegWrite} = 1'b1;
            7'b0010011: // I-Type (ADDI...)
                {ALUSrc, RegWrite} = 2'b11;
            7'b0000011: // Load (LW...)
                {ALUSrc, MemtoReg, RegWrite, MemRead} = 4'b1111;
            7'b0100011: // Store (SW...)
                {ALUSrc, MemWrite} = 2'b11;
            7'b1100011: // Branch (BEQ...)
                {Branch} = 1'b1;
            7'b1101111: // JAL (Jump)
                {RegWrite} = 1'b1; // Simplified for basic JAL
        endcase
    end
endmodule
