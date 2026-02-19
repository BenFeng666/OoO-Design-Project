module WriteBack (
    // Data Inputs (from MEM/WB Pipeline Register)
    input wire [31:0] ALU_Result,     // From ALU (for arithmetic/logic)
    input wire [31:0] Read_Data,      // From Data Memory (for Loads)
    input wire [31:0] PC_Plus_4,      // From Fetch Stage (for JAL/JALR)
    
    // Control Inputs (from MEM/WB Pipeline Register)
    input wire [1:0]  MemToReg,       // Mux Selector
    input wire        RegWrite,       // Enable signal
    input wire [4:0]  rd,             // Destination Register
    
    // Outputs (Sent BACK to ID Stage - Register File)
    output reg [31:0] Result_Data,    // The final data to write
    output wire [4:0] Write_Reg_Idx,  // The register to write to
    output wire       RegWrite_En     // The write enable signal
);

    // Pass-through logic for control signals
    assign Write_Reg_Idx = rd;
    assign RegWrite_En   = RegWrite;

    // --------------------------------------------------------
    // Write Back MUX Logic
    // --------------------------------------------------------
    always @(*) begin
        case (MemToReg)
            // 00: ALU Result (R-Type, I-Type Arithmetic)
            2'b00: Result_Data = ALU_Result;
            
            // 01: Memory Data (Loads: LW, LB, etc.)
            2'b01: Result_Data = Read_Data;
            
            // 10: PC + 4 (Jumps: JAL, JALR)
            // We need to save the return address so the function can return later.
            2'b10: Result_Data = PC_Plus_4;
            
            // Default: Safe fallback
            default: Result_Data = 32'b0;
        endcase
    end

endmodule
