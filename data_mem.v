module data_mem (
    input wire clk,
    input wire rst,
    input wire mem_read,
    input wire mem_write,
    input wire [31:0] address,
    input wire [31:0] write_data,
    output reg [31:0] read_data
);

reg [31:0] data_mem [256];
integer i;

always @(posedge clk or negedge rst)
begin
    

    if (!rst)
    begin
        for (i=0; i<256; i++)
        begin
            data_mem[i]<=32'b0;
        end
        read_data<=32'b0;
    end
    else begin

        if (mem_write)
        begin
            data_mem[address[9:2]] <= write_data;
        end

        if (mem_read)
        begin
            read_data  <= data_mem [address[9:2]];
        end
    end


end


endmodule
