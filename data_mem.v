module data_mem (
    input wire clk,
    input wire rst,
    input wire mem_read,
    input wire mem_write,
    input wire [31:0] address,
    input wire [31:0] write_data,
    output reg [31:0] read_data
);

reg [31:0] data_mem [0:255];
integer i;

// synchronous write, async reset
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        for (i = 0; i < 256; i = i + 1)
            data_mem[i] <= 32'b0;
    end
    else begin
        if (mem_write)
            data_mem[address[9:2]] <= write_data;
    end
end

// combinational read
always @(*) begin
    if (mem_read)
        read_data = data_mem[address[9:2]];
    else
        read_data = 32'b0;
end

endmodule
