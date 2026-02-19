module RegisterFile (
    input wire clk,
    input wire reset,
    
    // Read Ports (Instruction Decode Stage)
    input wire [4:0] rs1,          // Source Register 1 Index
    input wire [4:0] rs2,          // Source Register 2 Index
    
    // Write Port (Write Back Stage)
    input wire RegWrite_En,        // Write Enable Control Signal
    input wire [4:0] rd,           // Destination Register Index
    input wire [31:0] Write_Data,  // Data to write into rd
    
    // Outputs
    output wire [31:0] Read_Data_1, // Value of rs1
    output wire [31:0] Read_Data_2  // Value of rs2
);

    // 32 registers, each 32 bits wide
    reg [31:0] registers [31:0];
    integer i;

    // --------------------------------------------------------
    // Asynchronous Read Logic
    // --------------------------------------------------------
    // RISC-V Requirement: Register x0 is HARDWIRED to 0.
    // Even if you try to write to it, reading it must always return 0.
    assign Read_Data_1 = (rs1 == 5'b0) ? 32'b0 : registers[rs1];
    assign Read_Data_2 = (rs2 == 5'b0) ? 32'b0 : registers[rs2];

    // --------------------------------------------------------
    // Synchronous Write Logic
    // --------------------------------------------------------
    // Writes happen on the rising edge of the clock.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Reset all registers to 0
            for (i = 0; i < 32; i = i + 1) begin
                registers[i] <= 32'b0;
            end
        end 
        else if (RegWrite_En && (rd != 5'b0)) begin
            // Write only if Enable is HIGH and dest is NOT x0
            registers[rd] <= Write_Data;
        end
    end

endmodule
