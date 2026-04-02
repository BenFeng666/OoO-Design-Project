module ID_EX (
    input wire clk,
    input wire rst,
    input wire [31:0] rs1,
    input wire [31:0] rs2,
    input wire [31:0] imm,
    input wire ALUSrc,
    input wire MemRead,
    input wire MemWrite,
    input wire MemtoReg,
    input wire Branch,
    input wire jump,
    input wire [3:0] ctrl,
    input wire [4:0] rg_addr,
    input wire rg_WE,
    output reg [31:0] ex_rs1,
    output reg [31:0] ex_rs2,
    output reg [31:0] ex_imm,
    output reg [3:0] ex_ctrl,
    output reg ex_ALUSrc,
    output reg ex_MemRead,
    output reg ex_MemWrite,
    output reg ex_MemtoReg,
    output reg ex_Branch,
    output reg [4:0] ex_rg_addr,
    output reg rg_WE,
    output reg ex_jump

);



always @(posedge clk or negedge rst) begin
    if (!rst)
    begin
        ex_rs1 <= 32'b0;
        ex_rs2 <= 32'b0;
        ex_imm <= 32'b0;
        ex_ctrl <= 4'b0;
        ex_ALUSrc <=1'b0;
        ex_MemRead <=1'b0;
        ex_MemWrite <=1'b0;
        ex_MemtoReg <=1'b0;
        ex_Branch <=1'b0;
        ex_jump <=1'b0;
        ex_rg_addr <= 5'b0;
        ex_rg_WE <= 1'b0;

    end

    else 
    begin
        ex_rs1 <= rs1;
        ex_rs2 <= rs2;
        ex_imm <= imm;
        ex_ctrl <= ctrl;
        ex_ALUSrc <= ALUSrc;
        ex_MemRead <= MemRead;
        ex_MemWrite <= MemWrite;
        ex_MemtoReg <= MemtoReg;
        ex_Branch <= Branch;
        ex_jump <= jump;
        ex_rg_addr <= rg_addr;
        ex_rg_WE <= rg_WE;

    end


end
endmodule
