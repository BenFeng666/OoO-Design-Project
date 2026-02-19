// Arithmetic Logic Unit (ALU) for RV32I Single-Cycle Core
// Performs arithmetic, logical, comparison, and shift operations

module alu (
    input  logic [31:0] operand_a,       // First operand
    input  logic [31:0] operand_b,       // Second operand
    input  logic [3:0]  alu_control,     // ALU operation selector
    output logic [31:0] result,          // ALU result
    output logic        zero             // Zero flag (result == 0)
);

    // ALU operation encoding
    localparam ALU_ADD  = 4'b0000;  // Addition
    localparam ALU_SUB  = 4'b0001;  // Subtraction
    localparam ALU_AND  = 4'b0010;  // Bitwise AND
    localparam ALU_OR   = 4'b0011;  // Bitwise OR
    localparam ALU_XOR  = 4'b0100;  // Bitwise XOR
    localparam ALU_SLT  = 4'b0101;  // Set Less Than (signed)
    localparam ALU_SLTU = 4'b0110;  // Set Less Than Unsigned
    localparam ALU_SLL  = 4'b0111;  // Shift Left Logical
    localparam ALU_SRL  = 4'b1000;  // Shift Right Logical
    localparam ALU_SRA  = 4'b1001;  // Shift Right Arithmetic

    // Combinational logic for ALU operations
    always_comb begin
        case (alu_control)
            ALU_ADD: begin
                // Addition
                result = operand_a + operand_b;
            end
            
            ALU_SUB: begin
                // Subtraction
                result = operand_a - operand_b;
            end
            
            ALU_AND: begin
                // Bitwise AND
                result = operand_a & operand_b;
            end
            
            ALU_OR: begin
                // Bitwise OR
                result = operand_a | operand_b;
            end
            
            ALU_XOR: begin
                // Bitwise XOR
                result = operand_a ^ operand_b;
            end
            
            ALU_SLT: begin
                // Set Less Than (signed comparison)
                result = ($signed(operand_a) < $signed(operand_b)) ? 32'h00000001 : 32'h00000000;
            end
            
            ALU_SLTU: begin
                // Set Less Than Unsigned
                result = (operand_a < operand_b) ? 32'h00000001 : 32'h00000000;
            end
            
            ALU_SLL: begin
                // Shift Left Logical (shift amount in lower 5 bits of operand_b)
                result = operand_a << operand_b[4:0];
            end
            
            ALU_SRL: begin
                // Shift Right Logical (shift amount in lower 5 bits of operand_b)
                result = operand_a >> operand_b[4:0];
            end
            
            ALU_SRA: begin
                // Shift Right Arithmetic (shift amount in lower 5 bits of operand_b)
                result = $signed(operand_a) >>> operand_b[4:0];
            end
            
            default: begin
                // Default to zero for undefined operations
                result = 32'h00000000;
            end
        endcase
    end
    
    // Zero flag generation (useful for branch conditions)
    assign zero = (result == 32'h00000000);

endmodule