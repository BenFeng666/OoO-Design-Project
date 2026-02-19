// Control Unit (Decoder) for RV32I Single-Cycle Core
// Decodes instructions and generates control signals for the datapath

module control_unit (
    input  logic [31:0] instruction,     // 32-bit instruction
    
    // Control signals
    output logic [3:0]  alu_control,     // ALU operation selector
    output logic [2:0]  imm_type,        // Immediate type for generator
    output logic        reg_write,       // Register file write enable
    output logic        mem_read,        // Memory read enable
    output logic        mem_write,       // Memory write enable
    output logic        alu_src,         // ALU operand B source (0=reg, 1=imm)
    output logic [1:0]  wb_src,          // Write-back source (00=ALU, 01=Mem, 10=PC+4)
    output logic        branch,          // Branch instruction flag
    output logic        jump,            // Jump instruction flag
    output logic [2:0]  funct3           // Pass through funct3 for branch/mem operations
);

    // Extract instruction fields
    logic [6:0] opcode;
    logic [2:0] funct3_internal;
    logic [6:0] funct7;
    
    assign opcode = instruction[6:0];
    assign funct3_internal = instruction[14:12];
    assign funct7 = instruction[31:25];
    assign funct3 = funct3_internal;  // Pass through for use in branch/memory logic
    
    // RV32I Opcodes
    localparam OP_R_TYPE    = 7'b0110011;  // R-type (ADD, SUB, AND, OR, XOR, SLT, SLTU, SLL, SRL, SRA)
    localparam OP_I_ALU     = 7'b0010011;  // I-type ALU (ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI)
    localparam OP_LOAD      = 7'b0000011;  // Load instructions (LB, LH, LW, LBU, LHU)
    localparam OP_STORE     = 7'b0100011;  // Store instructions (SB, SH, SW)
    localparam OP_BRANCH    = 7'b1100011;  // Branch instructions (BEQ, BNE, BLT, BGE, BLTU, BGEU)
    localparam OP_JAL       = 7'b1101111;  // JAL
    localparam OP_JALR      = 7'b1100111;  // JALR
    localparam OP_LUI       = 7'b0110111;  // LUI
    localparam OP_AUIPC     = 7'b0010111;  // AUIPC
    
    // ALU function codes (funct3)
    localparam FUNCT3_ADD_SUB = 3'b000;
    localparam FUNCT3_SLT     = 3'b010;
    localparam FUNCT3_SLTU    = 3'b011;
    localparam FUNCT3_XOR     = 3'b100;
    localparam FUNCT3_OR      = 3'b110;
    localparam FUNCT3_AND     = 3'b111;
    localparam FUNCT3_SLL     = 3'b001;
    localparam FUNCT3_SRL_SRA = 3'b101;
    
    // ALU control encoding (matching alu.sv)
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_XOR  = 4'b0100;
    localparam ALU_SLT  = 4'b0101;
    localparam ALU_SLTU = 4'b0110;
    localparam ALU_SLL  = 4'b0111;
    localparam ALU_SRL  = 4'b1000;
    localparam ALU_SRA  = 4'b1001;
    
    // Immediate type encoding (matching immediate_generator.sv)
    localparam IMM_I = 3'b000;
    localparam IMM_S = 3'b001;
    localparam IMM_B = 3'b010;
    localparam IMM_U = 3'b011;
    localparam IMM_J = 3'b100;
    
    // Write-back source encoding
    localparam WB_ALU  = 2'b00;
    localparam WB_MEM  = 2'b01;
    localparam WB_PC4  = 2'b10;
    
    // Main decoder logic
    always_comb begin
        // Default control signals (prevent latches)
        alu_control = ALU_ADD;
        imm_type = IMM_I;
        reg_write = 1'b0;
        mem_read = 1'b0;
        mem_write = 1'b0;
        alu_src = 1'b0;
        wb_src = WB_ALU;
        branch = 1'b0;
        jump = 1'b0;
        
        case (opcode)
            OP_R_TYPE: begin
                // R-type instructions
                reg_write = 1'b1;
                alu_src = 1'b0;  // ALU operand B from register
                wb_src = WB_ALU;
                
                // Decode ALU operation based on funct3 and funct7
                case (funct3_internal)
                    FUNCT3_ADD_SUB: alu_control = (funct7[5]) ? ALU_SUB : ALU_ADD;
                    FUNCT3_SLT:     alu_control = ALU_SLT;
                    FUNCT3_SLTU:    alu_control = ALU_SLTU;
                    FUNCT3_XOR:     alu_control = ALU_XOR;
                    FUNCT3_OR:      alu_control = ALU_OR;
                    FUNCT3_AND:     alu_control = ALU_AND;
                    FUNCT3_SLL:     alu_control = ALU_SLL;
                    FUNCT3_SRL_SRA: alu_control = (funct7[5]) ? ALU_SRA : ALU_SRL;
                    default:        alu_control = ALU_ADD;
                endcase
            end
            
            OP_I_ALU: begin
                // I-type ALU instructions
                reg_write = 1'b1;
                alu_src = 1'b1;  // ALU operand B from immediate
                wb_src = WB_ALU;
                imm_type = IMM_I;
                
                // Decode ALU operation based on funct3
                case (funct3_internal)
                    FUNCT3_ADD_SUB: alu_control = ALU_ADD;  // ADDI
                    FUNCT3_SLT:     alu_control = ALU_SLT;  // SLTI
                    FUNCT3_SLTU:    alu_control = ALU_SLTU; // SLTIU
                    FUNCT3_XOR:     alu_control = ALU_XOR;  // XORI
                    FUNCT3_OR:      alu_control = ALU_OR;   // ORI
                    FUNCT3_AND:     alu_control = ALU_AND;  // ANDI
                    FUNCT3_SLL:     alu_control = ALU_SLL;  // SLLI
                    FUNCT3_SRL_SRA: alu_control = (funct7[5]) ? ALU_SRA : ALU_SRL; // SRLI/SRAI
                    default:        alu_control = ALU_ADD;
                endcase
            end
            
            OP_LOAD: begin
                // Load instructions
                reg_write = 1'b1;
                mem_read = 1'b1;
                alu_src = 1'b1;  // Address = rs1 + immediate
                wb_src = WB_MEM;
                imm_type = IMM_I;
                alu_control = ALU_ADD;
            end
            
            OP_STORE: begin
                // Store instructions
                mem_write = 1'b1;
                alu_src = 1'b1;  // Address = rs1 + immediate
                imm_type = IMM_S;
                alu_control = ALU_ADD;
            end
            
            OP_BRANCH: begin
                // Branch instructions
                branch = 1'b1;
                alu_src = 1'b0;  // Compare two registers
                imm_type = IMM_B;
                alu_control = ALU_SUB;  // Used for comparison
            end
            
            OP_JAL: begin
                // JAL instruction
                reg_write = 1'b1;
                jump = 1'b1;
                wb_src = WB_PC4;  // Write PC+4 to rd
                imm_type = IMM_J;
                alu_control = ALU_ADD;
            end
            
            OP_JALR: begin
                // JALR instruction
                reg_write = 1'b1;
                jump = 1'b1;
                alu_src = 1'b1;  // Target = rs1 + immediate
                wb_src = WB_PC4;  // Write PC+4 to rd
                imm_type = IMM_I;
                alu_control = ALU_ADD;
            end
            
            OP_LUI: begin
                // LUI instruction
                reg_write = 1'b1;
                alu_src = 1'b1;
                wb_src = WB_ALU;
                imm_type = IMM_U;
                alu_control = ALU_ADD;  // Can use ADD with rs1=0
            end
            
            OP_AUIPC: begin
                // AUIPC instruction
                reg_write = 1'b1;
                alu_src = 1'b1;
                wb_src = WB_ALU;
                imm_type = IMM_U;
                alu_control = ALU_ADD;  // PC + immediate
            end
            
            default: begin
                // Invalid instruction - all signals stay at default
                reg_write = 1'b0;
            end
        endcase
    end

endmodule