module reg_file(
    input wire clk,
    input wire we,
    input wire rst,
    input wire [4:0] rs1_addr,
    input wire [4:0] rs2_addr,
    input wire [4:0] rd_addr,
    input wire [31:0] rd_data,
    output reg [31:0] rs1_data,
    output reg [31:0] rs2_data

);
reg [31:0] store_unit [31:0];
integer i;

always @(posedge clk , negedge rst )
begin
  if (!rst)
  begin
    for (i=0;i<32;i++) begin
        
            store_unit[i]<=32'b0;
        
    end
  end

  else if (we) // if we then we are wb mode, we write back to the rd_addr
  begin
    store_unit[rd_addr] <=rd_data; 
    store_unit[0] <=32'b0; // x0=0 always
  end

end

always @(*) begin
    rs1_data = store_unit[rs1_addr];
    rs2_data = store_unit[rs2_addr];
end

endmodule
