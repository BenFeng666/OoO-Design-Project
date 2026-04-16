module PC (
    input wire clk,
    input wire rst,
    input wire stall,
    input wire [31:0] next_inst,
    output reg [31:0] pc
);

always @(posedge clk or negedge rst) begin
    if (!rst)
        pc <= 32'b0;
    else if (!stall)
        pc <= next_inst;
end

endmodule
