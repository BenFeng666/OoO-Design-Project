module wb_mux (
    input wire select,
    input wire [31:0] alu_result,
    input wire [31:0] mem_data,
    output reg [31:0] wb_data
);

always @(*) begin
    if (!select) begin
        wb_data = alu_result;
    end
    else if (select) begin
        wb_data = mem_data;
        end

end
endmodule
