module ALU (
    input  wire [31:0] Val_A,      // rs1 value or PC (for AUIPC)
    input  wire [31:0] Val_B,      // rs2 value or Immediate
    input  wire [6:0]  opcode,     // The 7-bit opcode
    input  wire [2:0]  funct3,     // The 3-bit function code
    input  wire [6:0]  funct7,     // The 7-bit function code (mostly for bit 30)
    
    output reg  [31:0] ALU_Result, // The calculation result
    output wire        Zero_Flag   // 1 if Result is 0 (Used for BEQ)
);

    // Opcodes defined from RV32I spec
    localparam OP_R_TYPE   = 7'b0110011;
    localparam OP_I_TYPE   = 7'b0010011; // Arithmetic I-type
    localparam OP_LOAD     = 7'b0000011;
    localparam OP_STORE    = 7'b0100011;
    localparam OP_BRANCH   = 7'b1100011;
    localparam OP_LUI      = 7'b0110111;
    localparam OP_AUIPC    = 7'b0010111;
    localparam OP_JAL      = 7'b1101111;
    localparam OP_JALR     = 7'b1100111;

    always @(*) begin
        // Default value to prevent latches
        ALU_Result = 32'b0;

        case (opcode)
            // -----------------------------
            // R-TYPE (Register-Register)
            // -----------------------------
            OP_R_TYPE: begin
                case (funct3)
                    3'b000: begin // ADD or SUB
                        if (funct7[5]) // If bit 30 is 1 (0x20), it's SUB
                            ALU_Result = Val_A - Val_B;
                        else           // Otherwise ADD
                            ALU_Result = Val_A + Val_B;
                    end
                    3'b001: ALU_Result = Val_A << Val_B[4:0];         // SLL
                    3'b010: ALU_Result = ($signed(Val_A) < $signed(Val_B)) ? 32'd1 : 32'd0; // SLT
                    3'b011: ALU_Result = (Val_A < Val_B) ? 32'd1 : 32'd0;                   // SLTU
                    3'b100: ALU_Result = Val_A ^ Val_B;               // XOR
                    3'b101: begin // SRL or SRA
                        if (funct7[5]) // SRA (Arithmetic shift)
                            ALU_Result = $signed(Val_A) >>> Val_B[4:0];
                        else           // SRL (Logical shift)
                            ALU_Result = Val_A >> Val_B[4:0];
                    end
                    3'b110: ALU_Result = Val_A | Val_B;               // OR
                    3'b111: ALU_Result = Val_A & Val_B;               // AND
                endcase
            end

            // -----------------------------
            // I-TYPE (Register-Immediate)
            // -----------------------------
            OP_I_TYPE: begin
                case (funct3)
                    3'b000: ALU_Result = Val_A + Val_B;               // ADDI
                    3'b010: ALU_Result = ($signed(Val_A) < $signed(Val_B)) ? 32'd1 : 32'd0; // SLTI
                    3'b011: ALU_Result = (Val_A < Val_B) ? 32'd1 : 32'd0;                   // SLTIU
                    3'b100: ALU_Result = Val_A ^ Val_B;               // XORI
                    3'b110: ALU_Result = Val_A | Val_B;               // ORI
                    3'b111: ALU_Result = Val_A & Val_B;               // ANDI
                    3'b001: ALU_Result = Val_A << Val_B[4:0];         // SLLI
                    3'b101: begin // SRLI or SRAI
                        if (funct7[5]) // Bit 30 distinguishes SRAI
                            ALU_Result = $signed(Val_A) >>> Val_B[4:0];
                        else
                            ALU_Result = Val_A >> Val_B[4:0];
                    end
                endcase
            end

            // -----------------------------
            // LOADS & STORES (Address Calc)
            // -----------------------------
            OP_LOAD, OP_STORE: begin
                ALU_Result = Val_A + Val_B; // Mem Address = rs1 + imm
            end

            // -----------------------------
            // BRANCHES (Comparison)
            // -----------------------------
            // In EX stage, branches usually perform subtraction to check conditions.
            // Some designs use a dedicated comparator. Here we use subtraction.
            // The Zero_Flag output handles BEQ/BNE.
            OP_BRANCH: begin
                ALU_Result = Val_A - Val_B;
                // Note: Complex branches like BLT/BGE usually rely on flags
                // derived from this subtraction or a dedicated comparator.
            end

            // -----------------------------
            // OTHER (LUI, AUIPC, JAL, JALR)
            // -----------------------------
            OP_LUI:   ALU_Result = Val_B;            // LUI just passes the immediate
            OP_AUIPC: ALU_Result = Val_A + Val_B;    // PC + Imm
            OP_JAL:   ALU_Result = Val_A + 4;        // Store PC+4 (Link)
            OP_JALR:  ALU_Result = Val_A + 4;        // Store PC+4 (Link)
            
            default: ALU_Result = 32'b0;
        endcase
    end

    // ------------------------------------------
    // OUTPUT: Zero Flag
    // ------------------------------------------
    // Used for BEQ (Branch if Equal). If Result == 0, then A == B.
    assign Zero_Flag = (ALU_Result == 32'b0) ? 1'b1 : 1'b0;

endmodule
