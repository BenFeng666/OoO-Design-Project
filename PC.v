module PC (
    input wire clk,
    input wire rst,
    input wire [31:0] next_inst,
    output reg [31:0] pc 
);

always  @(posedge clk , negedge rst)
begin
    if (!rst)
    begin 
        pc<=32'b0;
    end
    else begin
    pc <= next_inst;
    end

end
endmodule
