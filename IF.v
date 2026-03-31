module IF_ID (
    input wire clk,
    input wire rst,
    input wire [31:0] PC,
    input wire [31:0]instruction,
    input wire [31:0] PC_4,
    output reg [31:0] ID_instruction,
    output reg [31:0] ID_PC,
    output reg [31:0] ID_PC_4
);



always @(posedge clk or negedge rst) begin
    if (!rst)
    begin
       ID_instruction <= 32'b0;
       ID_PC <= 32'b0;
       ID_PC_4 <= 32'b0; 
    end
    else 
    begin
    ID_instruction <= instruction;
    ID_PC <= PC;
    ID_PC_4 <= PC_4;
    end


end
endmodule
