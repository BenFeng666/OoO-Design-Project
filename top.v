module top module (
    input clk,
    input rst

);

ALU u_alu (
    .A(rs1_data),
    .B(alu_in2),
    .ctrl(alu_ctrl),
    .result(alu_result),
    .zero(zero),
    .negative(negative)
);

ALU_ctrl u_alu_ctrl (
    .instruction(instruction),
    .ctrl(alu_ctrl)
);

mcu u_mcu (
    .instruction(instruction),
    .WE(WE),
    .ALUSrc(ALUSrc),
    .MemRead(MemRead),
    .MemWrite(MemWrite),
    .MemtoReg(MemtoReg),
    .Branch(Branch),
    .jump(jump)
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

data_mem u_data_mem (
    .clk(clk),
    .rst(rst),
    .mem_read(MemRead),
    .mem_write(MemWrite),
    .address(alu_result),
    .write_data(rs2_data),
    .read_data(mem_data)
);

imm_gen u_imm_gen (
    .instruction(instruction),
    .imm(imm)
);

instruction_mem u_imem (
    .addr(pc),
    .instruction(instruction)
);

reg_file u_reg_file (
    .clk(clk),
    .we(WE),
    .rst(rst),
    .rs1_addr(instruction[19:15]),
    .rs2_addr(instruction[24:20]),
    .rd_addr(instruction[11:7]),
    .rd_data(wb_data),
    .rs1_data(rs1_data),
    .rs2_data(rs2_data)
);

wb_mux u_wb_mux (
    .select(MemtoReg),
    .alu_result(alu_result),
    .mem_data(mem_data),
    .wb_data(wb_data)
);



