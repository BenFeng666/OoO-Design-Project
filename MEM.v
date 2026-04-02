module mem_wb (
    input wire clk,
    input wire rst,
    input wire [31:0] alu_result,
    input wire [31:0] mem_data,
    input wire MemtoReg,
    input wire reg_WE,
    input wire [4:0]rg_addr,
    output reg wb_rg_WE,
    output reg [4:0] wb_rg_addr,
    output reg [31:0] wb_alu_result,
    output reg [31:0] wb_mem_data,
    output reg wb_MemtoReg

);

always @(posedge clk or negedge rst)begin
  if (!rst) begin
    wb_alu_result <= 32'b0;
    wb_mem_data <= 32'b0;
    wb_MemtoReg <= 1'b0;
    wb_rg_addr <= 5'b0;
    wb_rg_WE <=1'b0;
  end

  else begin
    wb_alu_result <= alu_result;
    wb_mem_data <= mem_data;
    wb_MemtoReg <= MemtoReg;
    wb_rg_addr <= rg_addr;
    wb_rg_WE <= reg_WE;
  end

end
endmodule
