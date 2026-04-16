module ALU_ctrl(
    input wire [31:0] instruction,
    output reg [3:0] ctrl
);

always @(*) begin
    ctrl = 4'b0000;

    case (instruction[6:0])

        // R-type
        7'b0110011: begin
            if (instruction[14:12] == 3'b000 && instruction[31:25] == 7'b0000000)
                ctrl = 4'b0000; // add
            else if (instruction[14:12] == 3'b000 && instruction[31:25] == 7'b0100000)
                ctrl = 4'b0001; // sub
            else if (instruction[14:12] == 3'b100 && instruction[31:25] == 7'b0000000)
                ctrl = 4'b0100; // xor
            else if (instruction[14:12] == 3'b000 && instruction[31:25] == 7'b0000001)
                ctrl = 4'b1011; // mul
            else if (instruction[14:12] == 3'b110 && instruction[31:25] == 7'b0000000)
                ctrl = 4'b0011; // or
            else if (instruction[14:12] == 3'b111 && instruction[31:25] == 7'b0000000)
                ctrl = 4'b0010; // and
            else if (instruction[14:12] == 3'b001 && instruction[31:25] == 7'b0000000)
                ctrl = 4'b0101; // sll
            else if (instruction[14:12] == 3'b101 && instruction[31:25] == 7'b0000000)
                ctrl = 4'b0110; // srl
            else if (instruction[14:12] == 3'b101 && instruction[31:25] == 7'b0100000)
                ctrl = 4'b0111; // sra
            else if (instruction[14:12] == 3'b010 && instruction[31:25] == 7'b0000000)
                ctrl = 4'b1000; // slt
            else if (instruction[14:12] == 3'b011 && instruction[31:25] == 7'b0000000)
                ctrl = 4'b1001; // sltu
        end

        // I-type arithmetic
        7'b0010011: begin
            if (instruction[14:12] == 3'b000)
                ctrl = 4'b0000; // addi
            else if (instruction[14:12] == 3'b100)
                ctrl = 4'b0100; // xori
            else if (instruction[14:12] == 3'b110)
                ctrl = 4'b0011; // ori
            else if (instruction[14:12] == 3'b111)
                ctrl = 4'b0010; // andi
            else if (instruction[14:12] == 3'b001 && instruction[31:25] == 7'b0000000)
                ctrl = 4'b0101; // slli
            else if (instruction[14:12] == 3'b101 && instruction[31:25] == 7'b0000000)
                ctrl = 4'b0110; // srli
            else if (instruction[14:12] == 3'b101 && instruction[31:25] == 7'b0100000)
                ctrl = 4'b0111; // srai
            else if (instruction[14:12] == 3'b010)
                ctrl = 4'b1000; // slti
            else if (instruction[14:12] == 3'b011)
                ctrl = 4'b1001; // sltiu
        end

        // load
        7'b0000011: begin
            ctrl = 4'b0000; // address = rs1 + imm
        end

        // store
        7'b0100011: begin
            ctrl = 4'b0000; // address = rs1 + imm
        end

        // branches
        7'b1100011: begin
            if (instruction[14:12] == 3'b000)
                ctrl = 4'b0001; // beq -> subtract compare
            else if (instruction[14:12] == 3'b001)
                ctrl = 4'b0001; // bne -> subtract compare
            else if (instruction[14:12] == 3'b100)
                ctrl = 4'b1000; // blt
            else if (instruction[14:12] == 3'b101)
                ctrl = 4'b1000; // bge uses signed compare too
            else if (instruction[14:12] == 3'b110)
                ctrl = 4'b1001; // bltu
            else if (instruction[14:12] == 3'b111)
                ctrl = 4'b1001; // bgeu uses unsigned compare too
        end

        // jal
        7'b1101111: begin
            ctrl = 4'b0000;
        end

        // jalr
        7'b1100111: begin
            ctrl = 4'b0000;
        end

        // lui
        7'b0110111: begin
            ctrl = 4'b1010;
        end

        // auipc
        7'b0010111: begin
            ctrl = 4'b0000;
        end

        default: begin
            ctrl = 4'b0000;
        end
    endcase
end

endmodule
