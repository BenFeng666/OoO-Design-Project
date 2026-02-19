module ProgramCounter (
    input wire clk,
    input wire reset,
    input wire PCSrc,              // The branch selection signal (0 = PC+4, 1 = Branch)
    input wire [31:0] PC_Branch,   // The calculated branch target address (from EX stage)
    input wire PC_Write_En,        // Optional: To freeze PC during Stalls (1 = Update, 0 = Stall)
    
    output reg [31:0] PC,          // The current Program Counter value
    output wire [31:0] PC_Plus_4   // PC + 4 (sent to next stage for JAL/JALR)
);

    // 1. Calculate the next sequential PC continuously
    assign PC_Plus_4 = PC + 32'd4;

    // 2. Sequential Logic: Update PC on the rising edge of the clock
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Reset Vector: Where the CPU starts (usually 0x00000000)
            PC <= 32'h00000000; 
        end 
        else if (PC_Write_En) begin
            // MUX Logic: Choose between Branch Target or Next Instruction
            if (PCSrc) 
                PC <= PC_Branch;  // Branch Taken (Jump to calculated address)
            else
                PC <= PC_Plus_4;  // Branch Not Taken (Move to next line)
        end
        // If PC_Write_En is 0, PC keeps its old value (Stall)
    end

endmodule
