module mcu (
    input wire [31:0] instruction,
    output reg WE, //write enable for reg file
    output reg ALUSrc, // for the second ALU MUX
    output reg MemRead, // for datamemory read
    output reg MemWrite, // for writing memory
    output reg MemtoReg, // select writeback source from
    output reg Branch, // for later branch instruction (not for now)
    output reg jump // for j type instruction
);

always @(*) 
begin
  
  case (instruction[6:0])
    7'b0110011: begin 
        WE=1; // write enable
        ALUSrc=0; // not using imm value
        MemRead=0; // no need to read from memory
        MemtoReg=0; // result from alu
        Branch = 0; // not a conditional branch
        jump =0; // not jumping
        MemWrite =0; //not writing memory

        end//R type
    7'b0010011: begin 
        WE=1; 
        ALUSrc=1; 
        MemRead=0;
        MemtoReg=0;
        Branch = 0;
        jump =0;
        MemWrite =0;
        end//I type 
    7'b0100011: begin 
        WE=0; 
        ALUSrc=1;  
        MemRead=0;
        MemtoReg=0; // result from memory
        Branch = 0;
        jump =0;
        MemWrite =1;
        end//S type
    7'b1100011: begin 
        WE=0; 
        ALUSrc=0; 
        MemRead=0;
        MemtoReg=0;
        Branch = 1; // conditional branch
        jump =0;
        MemWrite =0;
        end//B type
    7'b0110111: begin 
        WE=1; 
        ALUSrc=0; 
        MemRead=0;
        MemtoReg=0;
        Branch = 0;
        jump =0;
        MemWrite =0; 
        end//u type
    7'b1101111: begin 
        WE=1; 
        ALUSrc=0; 
        MemRead=0;
        MemtoReg=0;
        Branch = 0; 
        jump =1;
        MemWrite =0;
        end//j type
    7'b0000011: begin 
        WE=1; 
        ALUSrc=1; 
        MemRead=1;
        MemtoReg=1; 
        Branch = 0;
        jump =0;
        MemWrite =0;
        end // for storing I type (not yet)
    default: begin
        WE=0; 
        ALUSrc=0; 
        MemRead=0;
        MemtoReg=0; 
        Branch = 0;
        jump =0;
        MemWrite =0;
        end
  endcase



end
endmodule
