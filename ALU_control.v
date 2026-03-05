module ALU_ctrl(
    input wire [31:0] instruction,
    output reg [3:0] ctrl
);

always @(*) begin
    ctrl=4'b0000;
    case (instruction[6:0])
    7'b0110011: begin// R type

    if (instruction[14:12]==3'b000 && instruction[31:25]==7'b0000000)
    begin
        ctrl=4'b0000;//add
    end
    else if (instruction[14:12]==3'b000 && instruction[31:25]==7'b0100000)
    begin
        ctrl=4'b0001;//sub
    end
    else if (instruction[14:12]==3'b100 && instruction[31:25]==7'b0000000)
    begin
        ctrl=4'b0100;//^
    end 
    else if (instruction[14:12]==3'b110 && instruction[31:25]==7'b0000000)
    begin
        ctrl=4'b0011;//or
    end
    else if (instruction[14:12]==3'b111 && instruction[31:25]==7'b0000000)
    begin
        ctrl=4'b0010; //and
    end
    else if (instruction[14:12]==3'b001 && instruction[31:25]==7'b0000000)
    begin
        ctrl=4'b0101; //shift left
    end
    else if (instruction[14:12]==3'b101 && instruction[31:25]==7'b0000000)
    begin
        ctrl=4'b0110; //shift right
    end
    else if (instruction[14:12]==3'b101 && instruction[31:25]==7'b0100000)
    begin
        ctrl=4'b0111; //shift righ msb extend
    end
    else if (instruction[14:12]==3'b010 && instruction[31:25]==7'b0000000)
    begin
        ctrl=4'b1000; //less than signed
    end
    else if (instruction[14:12]==3'b011 && instruction[31:25]==7'b0000000)
    begin
        ctrl=4'b1001; //less than unsign
    end

    end

    7'b0010011: begin //I type
    if (instruction[14:12]==3'b000)
    begin
        ctrl=4'b0000;//add
    end
    //else if (instruction[14:12]==3'b000 && instruction[31:25]==7'b0010100)
    //begin
        //ctrl=4'b0001;//sub
    //end
    else if (instruction[14:12]==3'b100)
    begin
        ctrl=4'b0100;//^
    end 
    else if (instruction[14:12]==3'b110)
    begin
        ctrl=4'b0011;//or
    end
    else if (instruction[14:12]==3'b111)
    begin
        ctrl=4'b0010; //and
    end
    else if (instruction[14:12]==3'b001 && instruction[31:25]==7'b0000000)
    begin
        ctrl=4'b0101; //shift left
    end
    else if (instruction[14:12]==3'b101 && instruction[31:25]==7'b0000000)
    begin
        ctrl=4'b0110; //shift right
    end
    else if (instruction[14:12]==3'b101 && instruction[31:25]==7'b0100000)
    begin
        ctrl=4'b0111; //shift righ msb extend
    end
    else if (instruction[14:12]==3'b010 )
    begin
        ctrl=4'b1000; //less than signed
    end
    else if (instruction[14:12]==3'b011)
    begin
        ctrl=4'b1001; //less thanunsigned
    end
    end

    7'b0100011:; // don't support load in ALU yet

    7'b1100011:; // don't support B type yet
    7'b0110111:; // don't support J type yet
    7'b1101111:; // don't support U type yet
    default: ctrl = 4'b0000 ;
    

    endcase


end
endmodule
