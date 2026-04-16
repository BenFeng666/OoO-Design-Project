module ALU0(
    input wire clk,
    input wire rst,
    input wire start,
    input wire [31:0] A,
    input wire [31:0] B,
    input wire [3:0] ctrl,
    input wire [2:0] in_tag,

    output reg [31:0] wb_value,
    output reg [2:0]  wb_tag,
    output reg zero,
    output reg negative,
    output reg busy,
    output reg done
);

reg [1:0]  mul_cnt;
reg [31:0] mul_A;
reg [31:0] mul_B;
reg [2:0]  mul_tag;
wire [31:0] mul_res;

assign mul_res = mul_A * mul_B;

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        wb_value  <= 32'b0;
        wb_tag    <= 3'b0;
        zero      <= 1'b1;
        negative  <= 1'b0;
        busy      <= 1'b0;
        done      <= 1'b0;
        mul_cnt   <= 2'b0;
        mul_A     <= 32'b0;
        mul_B     <= 32'b0;
        mul_tag   <= 3'b0;
    end else begin
        done <= 1'b0;

        if (busy) begin
            if (mul_cnt == 2'd2) begin
                wb_value  <= mul_res;
                wb_tag    <= mul_tag;
                zero      <= (mul_res == 32'b0);
                negative  <= mul_res[31];
                busy      <= 1'b0;
                done      <= 1'b1;
                mul_cnt   <= 2'b0;
            end else begin
                mul_cnt <= mul_cnt + 1'b1;
            end
        end else if (start && ctrl == 4'b1011) begin
            busy    <= 1'b1;
            mul_cnt <= 2'd0;
            mul_A   <= A;
            mul_B   <= B;
            mul_tag <= in_tag;
        end
    end
end

endmodule
