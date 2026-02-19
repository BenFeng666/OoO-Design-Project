module RISCV_Pipeline_Top(
    input clk,
    input reset
);
    // ===========================================================================
    // 1. WIRES (Connecting stages together)
    // ===========================================================================
    
    // IF Stage Wires
    wire [31:0] IF_PC, IF_Instr, IF_PC_Plus_4;
    wire [31:0] PC_Next, PC_Branch_Target;
    wire PCSrc; // 1 if Branch taken

    // ID Stage Wires
    wire [31:0] ID_PC, ID_Instr; // Inputs from IF/ID Reg
    wire [31:0] ID_ReadData1, ID_ReadData2, ID_Imm;
    wire ID_Branch, ID_MemRead, ID_MemtoReg, ID_MemWrite, ID_ALUSrc, ID_RegWrite; // Control sigs
    
    // EX Stage Wires
    wire [31:0] EX_PC, EX_ReadData1, EX_ReadData2, EX_Imm;
    wire [4:0]  EX_Rd, EX_Rs1, EX_Rs2;
    wire [31:0] EX_ALU_Result;
    wire EX_Zero_Flag;
    wire [31:0] EX_ALU_Input_B; // Mux output for ALU source
    
    // MEM Stage Wires
    wire [31:0] MEM_ALU_Result, MEM_WriteData;
    wire [4:0]  MEM_Rd;
    wire [31:0] MEM_ReadData;
    wire MEM_Zero_Flag, MEM_Branch;
    
    // WB Stage Wires
    wire [31:0] WB_ReadData, WB_ALU_Result;
    wire [4:0]  WB_Rd;
    wire [31:0] WB_Result_Data;
    wire WB_RegWrite, WB_MemtoReg;

    // ===========================================================================
    // 2. PIPELINE REGISTERS (The "Glue" between stages)
    // ===========================================================================
    // These hold the data for one clock cycle.
    
    // IF/ID Pipeline Register
    reg [31:0] IF_ID_PC, IF_ID_Instr;

    // ID/EX Pipeline Register
    reg [31:0] ID_EX_PC, ID_EX_ReadData1, ID_EX_ReadData2, ID_EX_Imm;
    reg [4:0]  ID_EX_Rd, ID_EX_Rs1, ID_EX_Rs2;
    reg [31:0] ID_EX_Instr; // For funct3/funct7 extraction
    reg        ID_EX_MemRead, ID_EX_MemtoReg, ID_EX_MemWrite, ID_EX_RegWrite, ID_EX_Branch, ID_EX_ALUSrc;

    // EX/MEM Pipeline Register
    reg [31:0] EX_MEM_ALU_Result, EX_MEM_WriteData;
    reg [4:0]  EX_MEM_Rd;
    reg        EX_MEM_MemRead, EX_MEM_MemtoReg, EX_MEM_MemWrite, EX_MEM_RegWrite, EX_MEM_Branch, EX_MEM_Zero;

    // MEM/WB Pipeline Register
    reg [31:0] MEM_WB_ReadData, MEM_WB_ALU_Result;
    reg [4:0]  MEM_WB_Rd;
    reg        MEM_WB_MemtoReg, MEM_WB_RegWrite;

    // ===========================================================================
    // 3. STAGE LOGIC & INSTANTIATION
    // ===========================================================================

    // --- IF STAGE ---
    // PCSrc Logic: Take branch if (Branch Instruction in MEM stage) AND (Zero Flag Set)
    assign PCSrc = EX_MEM_Branch & EX_MEM_Zero; 
    
    ProgramCounter pc_module (
        .clk(clk), .reset(reset),
        .PCSrc(PCSrc), 
        .PC_Branch(EX_MEM_ALU_Result), // Branch target calculated in EX, passed to MEM
        .PC_Write_En(1'b1), // Always enabled for basic pipeline
        .PC(IF_PC), .PC_Plus_4(IF_PC_Plus_4)
    );

    InstructionMemory imem_module (
        .pc(IF_PC), .instruction(IF_Instr)
    );

    // --- IF/ID REGISTER WRITE ---
    always @(posedge clk) begin
        if (reset) begin
            IF_ID_PC <= 0; IF_ID_Instr <= 0;
        end else begin
            IF_ID_PC <= IF_PC;
            IF_ID_Instr <= IF_Instr;
        end
    end

    // --- ID STAGE ---
    ControlUnit ctrl_unit (
        .Opcode(IF_ID_Instr[6:0]),
        .Branch(ID_Branch), .MemRead(ID_MemRead), .MemtoReg(ID_MemtoReg),
        .MemWrite(ID_MemWrite), .ALUSrc(ID_ALUSrc), .RegWrite(ID_RegWrite)
    );

    RegisterFile reg_file (
        .clk(clk), .reset(reset),
        .rs1(IF_ID_Instr[19:15]), .rs2(IF_ID_Instr[24:20]),
        .rd(MEM_WB_Rd),             // Write-Back Dest
        .Write_Data(WB_Result_Data), // Write-Back Data
        .RegWrite_En(MEM_WB_RegWrite),
        .Read_Data_1(ID_ReadData1), .Read_Data_2(ID_ReadData2)
    );

    ImmGen imm_gen ( .Instr(IF_ID_Instr), .Imm(ID_Imm) );

    // --- ID/EX REGISTER WRITE ---
    always @(posedge clk) begin
        if (reset) begin
            ID_EX_PC <= 0; ID_EX_ReadData1 <= 0; ID_EX_ReadData2 <= 0; ID_EX_Imm <= 0;
            ID_EX_Rd <= 0; ID_EX_RegWrite <= 0; ID_EX_MemWrite <= 0; // Reset critical signals
        end else begin
            ID_EX_PC <= IF_ID_PC;
            ID_EX_ReadData1 <= ID_ReadData1;
            ID_EX_ReadData2 <= ID_ReadData2;
            ID_EX_Imm <= ID_Imm;
            ID_EX_Rd <= IF_ID_Instr[11:7];
            ID_EX_Instr <= IF_ID_Instr; // Pass instruction for funct3/7
            
            // Pass Control Signals
            ID_EX_MemRead <= ID_MemRead; ID_EX_MemtoReg <= ID_MemtoReg;
            ID_EX_MemWrite <= ID_MemWrite; ID_EX_RegWrite <= ID_RegWrite;
            ID_EX_Branch <= ID_Branch; ID_EX_ALUSrc <= ID_ALUSrc;
        end
    end

    // --- EX STAGE ---
    // MUX: Select Register Data or Immediate
    assign EX_ALU_Input_B = (ID_EX_ALUSrc) ? ID_EX_Imm : ID_EX_ReadData2;

    ALU alu_module (
        .Val_A(ID_EX_ReadData1), .Val_B(EX_ALU_Input_B),
        .opcode(ID_EX_Instr[6:0]), .funct3(ID_EX_Instr[14:12]), .funct7(ID_EX_Instr[31:25]),
        .ALU_Result(EX_ALU_Result), .Zero_Flag(EX_Zero_Flag)
    );

    // --- EX/MEM REGISTER WRITE ---
    always @(posedge clk) begin
        if (reset) begin
            EX_MEM_RegWrite <= 0; EX_MEM_MemWrite <= 0;
        end else begin
            EX_MEM_ALU_Result <= EX_ALU_Result; // This might be address or math result
            EX_MEM_WriteData <= ID_EX_ReadData2; // Data to store (SW)
            EX_MEM_Rd <= ID_EX_Rd;
            EX_MEM_Zero <= EX_Zero_Flag;
            
            // Control Signals
            EX_MEM_MemRead <= ID_EX_MemRead; EX_MEM_MemtoReg <= ID_EX_MemtoReg;
            EX_MEM_MemWrite <= ID_EX_MemWrite; EX_MEM_RegWrite <= ID_EX_RegWrite;
            EX_MEM_Branch <= ID_EX_Branch;
        end
    end

    // --- MEM STAGE ---
    DataMemory dmem_module (
        .clk(clk), .reset(reset),
        .MemWrite(EX_MEM_MemWrite), .MemRead(EX_MEM_MemRead),
        .Address(EX_MEM_ALU_Result), .Write_Data(EX_MEM_WriteData),
        .Read_Data(MEM_ReadData)
    );

    // --- MEM/WB REGISTER WRITE ---
    always @(posedge clk) begin
        if (reset) begin
            MEM_WB_RegWrite <= 0;
        end else begin
            MEM_WB_ReadData <= MEM_ReadData;
            MEM_WB_ALU_Result <= EX_MEM_ALU_Result;
            MEM_WB_Rd <= EX_MEM_Rd;
            
            // Control Signals
            MEM_WB_MemtoReg <= EX_MEM_MemtoReg;
            MEM_WB_RegWrite <= EX_MEM_RegWrite;
        end
    end

    // --- WB STAGE ---
    // Select between ALU Result and Memory Result
    assign WB_Result_Data = (MEM_WB_MemtoReg) ? MEM_WB_ReadData : MEM_WB_ALU_Result;

endmodule
