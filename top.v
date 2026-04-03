module top (
    input wire clk,
    input wire rst

);


// =========================
// IF stage wires
// =========================
wire [31:0] pc;
wire [31:0] next_pc;
wire [31:0] pc4;
wire [31:0] instruction;

// =========================
// IF/ID pipeline register wires
// =========================
wire [31:0] id_instruction;
wire [31:0] id_pc;
wire [31:0] id_pc4;

// =========================
// ID stage wires
// =========================
wire [31:0] rs1_data;
wire [31:0] rs2_data;
wire [31:0] imm;
wire [3:0]  alu_ctrl;

wire        WE;
wire        ALUSrc;
wire        MemRead;
wire        MemWrite;
wire        MemtoReg;
wire        Branch;
wire        jump;

// =========================
// ID/EX pipeline register wires
// =========================
wire [31:0] ex_rs1;
wire [31:0] ex_rs2;
wire [31:0] ex_imm;
wire [3:0]  ex_ctrl;
wire        ex_ALUSrc;
wire        ex_MemRead;
wire        ex_MemWrite;
wire        ex_MemtoReg;
wire        ex_Branch;
wire        ex_jump;
wire [4:0]  ex_rg_addr;
wire        ex_rg_WE;
wire [31:0] ex_pc;

// =========================
// EX stage wires
// =========================
wire [31:0] alu_in2;
wire [31:0] alu_result;
wire        zero;
wire        negative;

// =========================
// EX/MEM pipeline register wires
// =========================
wire        mem_zero;
wire        mem_negative;
wire [31:0] mem_alu_result;
wire        mem_MemRead;
wire        mem_MemWrite;
wire        mem_MemtoReg;
wire [31:0] mem_write_data;
wire [4:0]  mem_rg_addr;
wire        mem_rg_WE;

// =========================
// MEM stage wires
// =========================
wire [31:0] mem_data;

// =========================
// MEM/WB pipeline register wires
// =========================
wire        wb_rg_WE;
wire [4:0]  wb_rg_addr;
wire [31:0] wb_alu_result;
wire [31:0] wb_mem_data;
wire        wb_MemtoReg;

// =========================
// WB stage wires
// =========================
wire [31:0] wb_data;

// =========================
// PC control wires
// =========================
wire [31:0] branch_target;
wire [31:0] jal_target;
wire [1:0]  pc_sel;


assign pc4 = pc + 32'd4; // next instruction
assign branch_target = ex_pc + ex_imm;
assign jal_target    = ex_pc + ex_imm;

assign pc_sel = (ex_jump) ? 2'b11 :
                (ex_Branch && zero) ? 2'b01 :
                2'b00;


mcu u_mcu (
    .instruction(id_instruction),
    .WE(WE),
    .ALUSrc(ALUSrc),
    .MemRead(MemRead),
    .MemWrite(MemWrite),
    .MemtoReg(MemtoReg),
    .Branch(Branch),
    .jump(jump)
);


// IF/ID
IF_ID u_if_id (
    .clk(clk),
    .rst(rst),
    .PC(pc),
    .instruction(instruction),
    .PC_4(pc4),
    .ID_instruction(id_instruction),
    .ID_PC(id_pc),
    .ID_PC_4(id_pc4)
);

PC u_pc (
    .clk(clk),
    .rst(rst),
    .next_inst(next_pc),
    .pc(pc)
);

PC_mux u_pc_mux (
    .PC4(pc4),
    .branch_target(branch_target),
    .jal_target(jal_target),
    .pc_sel(pc_sel),
    .next_pc(next_pc)
);

// ID/EX
ID_EX u_id_ex (
    .clk(clk),
    .rst(rst),
    .rs1(rs1_data),
    .rs2(rs2_data),
    .imm(imm),
    .ALUSrc(ALUSrc),
    .MemRead(MemRead),
    .MemWrite(MemWrite),
    .MemtoReg(MemtoReg),
    .Branch(Branch),
    .jump(jump),
    .ctrl(alu_ctrl),
    .rg_addr(id_instruction[11:7]),
    .rg_WE(WE),
    .ex_rs1(ex_rs1),
    .ex_rs2(ex_rs2),
    .ex_imm(ex_imm),
    .ex_ctrl(ex_ctrl),
    .ex_ALUSrc(ex_ALUSrc),
    .ex_MemRead(ex_MemRead),
    .ex_MemWrite(ex_MemWrite),
    .ex_MemtoReg(ex_MemtoReg),
    .ex_Branch(ex_Branch),
    .ex_rg_addr(ex_rg_addr),
    .ex_rg_WE(ex_rg_WE),
    .ex_jump(ex_jump),
    .pc(id_pc),
    .ex_pc(ex_pc)
);


imm_gen u_imm_gen (
    .instruction(id_instruction),
    .imm(imm)
);

instruction_mem u_imem (
    .addr(pc),
    .instruction(instruction)
);

reg_file u_reg_file (
    .clk(clk),
    .we(wb_rg_WE),
    .rst(rst),
    .rs1_addr(id_instruction[19:15]),
    .rs2_addr(id_instruction[24:20]),
    .rd_addr(wb_rg_addr),
    .rd_data(wb_data),
    .rs1_data(rs1_data),
    .rs2_data(rs2_data)
);

// EX/MEM
ex_mem u_ex_mem (
    .clk(clk),
    .rst(rst),
    .zero(zero),
    .negative(negative),
    .alu_result(alu_result),
    .MemRead(ex_MemRead),
    .MemWrite(ex_MemWrite),
    .MemtoReg(ex_MemtoReg),
    .rg_WE(ex_rg_WE),
    .rg_addr(ex_rg_addr),
    .address(alu_result),
    .write_data(ex_rs2),
    .rs2(ex_rs2),
    .mem_rg_WE(mem_rg_WE),
    .mem_zero(mem_zero),
    .mem_negative(mem_negative),
    .mem_alu_result(mem_alu_result),
    .mem_MemRead(mem_MemRead),
    .mem_MemWrite(mem_MemWrite),
    .mem_MemtoReg(mem_MemtoReg),
    .mem_address(),          // only if you still keep this port
    .mem_rg_addr(mem_rg_addr),
    .mem_write_data(mem_write_data)
);

data_mem u_data_mem (
    .clk(clk),
    .rst(rst),
    .mem_read(mem_MemRead),
    .mem_write(mem_MemWrite),
    .address(mem_alu_result),
    .write_data(mem_write_data),
    .read_data(mem_data)
);

ALU u_alu (
    .A(ex_rs1),
    .B(ex_ALUSrc ? ex_imm : ex_rs2),
    .ctrl(ex_ctrl),
    .result(alu_result),
    .zero(zero),
    .negative(negative)
);

ALU_ctrl u_alu_ctrl (
    .instruction(id_instruction),
    .ctrl(alu_ctrl)
);

// MEM/WB
mem_wb u_mem_wb (
    .clk(clk),
    .rst(rst),
    .alu_result(mem_alu_result),
    .mem_data(mem_data),
    .MemtoReg(mem_MemtoReg),
    .reg_WE(mem_rg_WE),
    .rg_addr(mem_rg_addr),
    .wb_rg_WE(wb_rg_WE),
    .wb_rg_addr(wb_rg_addr),
    .wb_alu_result(wb_alu_result),
    .wb_mem_data(wb_mem_data),
    .wb_MemtoReg(wb_MemtoReg) );



wb_mux u_wb_mux (
    .select(wb_MemtoReg),
    .alu_result(wb_alu_result),
    .mem_data(wb_mem_data),
    .wb_data(wb_data)
);

endmodule
