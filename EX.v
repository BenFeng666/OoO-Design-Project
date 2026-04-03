module ex_mem (
    input wire clk,
    input wire rst,
    input wire zero,
    input wire negative,
    input wire [31:0] alu_result,
    input wire MemRead,
    input wire MemWrite,
    input wire MemtoReg,
    input wire rg_WE,
    input wire [4:0] rg_addr,
    input wire [31:0] address,
    input wire [31:0] write_data,
    input wire [31:0] rs2,
    output reg mem_rg_WE,
    output reg mem_zero,
    output reg mem_negative,
    output reg [31:0] mem_alu_result,
    output reg mem_MemRead,
    output reg mem_MemWrite,
    output reg mem_MemtoReg,
    output reg [31:0] mem_address,
    output reg [4:0] mem_rg_addr,
    output reg [31:0] mem_write_data
   
 
);



always @(posedge clk or negedge rst) begin
    if (!rst)
    begin
        mem_zero <= 1'b0;
        mem_negative <= 1'b0;
        mem_alu_result <= 32'b0;
        mem_MemRead <=1'b0;
        mem_MemWrite <= 1'b0;
        mem_MemtoReg <= 1'b0;
        mem_address <= 32'b0;
        mem_write_data <= 32'b0;
        mem_rg_WE <= 1'b0;
        mem_rg_addr <= 5'b0;
        


    end
    else 
    begin
        mem_zero <= zero;
        mem_negative <= negative;
        mem_alu_result <= alu_result;
        mem_MemRead <= MemRead;
        mem_MemWrite <= MemWrite;
        mem_MemtoReg <= MemtoReg;
        mem_address <= address;
        mem_write_data <= write_data; // or maybe writedata depending on the future top layer wiring
        mem_rg_WE <= rg_WE;
        mem_rg_addr <= rg_addr;

        

    end


end
endmodule
