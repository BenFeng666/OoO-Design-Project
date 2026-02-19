// Immediate Generator for RV32I Single-Cycle Core
// Extracts and sign-extends immediate values from instructions
// Supports I-type, S-type, B-type, U-type, and J-type formats

module immediate_generator (
    input  logic [31:0] instruction,     // 32-bit instruction
    input  logic [2:0]  imm_type,        // Immediate type selector
    output logic [31:0] immediate        // Sign-extended 32-bit immediate
);

    // Immediate type encoding
    localparam IMM_I = 3'b000;  // I-type: ADDI, loads, JALR
    localparam IMM_S = 3'b001;  // S-type: stores
    localparam IMM_B = 3'b010;  // B-type: branches
    localparam IMM_U = 3'b011;  // U-type: LUI, AUIPC
    localparam IMM_J = 3'b100;  // J-type: JAL

    // Combinational logic for immediate generation
    always_comb begin
        case (imm_type)
            IMM_I: begin
                // I-type: inst[31:20]
                // Sign-extend 12-bit immediate
                immediate = {{20{instruction[31]}}, instruction[31:20]};
            end
            
            IMM_S: begin
                // S-type: {inst[31:25], inst[11:7]}
                // Sign-extend 12-bit immediate
                immediate = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
            end
            
            IMM_B: begin
                // B-type: {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}
                // Sign-extend 13-bit immediate (last bit is implicit 0)
                immediate = {{19{instruction[31]}}, instruction[31], instruction[7], 
                            instruction[30:25], instruction[11:8], 1'b0};
            end
            
            IMM_U: begin
                // U-type: {inst[31:12], 12'b0}
                // Upper 20 bits, lower 12 bits are zeros
                immediate = {instruction[31:12], 12'b0};
            end
            
            IMM_J: begin
                // J-type: {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}
                // Sign-extend 21-bit immediate (last bit is implicit 0)
                immediate = {{11{instruction[31]}}, instruction[31], instruction[19:12], 
                            instruction[20], instruction[30:21], 1'b0};
            end
            
            default: begin
                // Default to zero for undefined types
                immediate = 32'h00000000;
            end
        endcase
    end

endmodule