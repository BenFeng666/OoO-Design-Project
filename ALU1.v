module ALU1(
    input wire [31:0] A,
    input wire [31:0] B,
    input wire [3:0] ctrl,
    output reg [31:0] result,
    output reg zero,
    output reg negative
);

always @(*) begin
    case (ctrl)
        4'b0000: result = A + B;                             // add
        4'b0001: result = A - B;                             // sub
        4'b0010: result = A & B;                             // and
        4'b0011: result = A | B;                             // or
        4'b0100: result = A ^ B;                             // xor
        4'b0101: result = A << B[4:0];                       // sll
        4'b0110: result = A >> B[4:0];                       // srl
        4'b0111: result = $signed(A) >>> B[4:0];             // sra
        4'b1000: result = ($signed(A) < $signed(B)) ? 32'd1 : 32'd0; // slt
        4'b1001: result = (A < B) ? 32'd1 : 32'd0;           // sltu
        4'b1010: result = B;                                 // lui: pass imm
        4'b1011: result = A * B;                             // mul (harmless if unused here)
        default: result = 32'b0;
    endcase

    zero = (result == 32'b0);
    negative = result[31];
end

endmodule
