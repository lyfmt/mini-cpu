`timescale 1ns / 1ps
`include "defines.vh"

// 五级流水线：IF -> ID -> EX -> M -> WB。
//
// 命名约定：信号以所在的段为前缀。
//   - 流水线寄存器的输出以"使用它的段"为前缀：IF/ID 的输出是 id_*，ID/EX 是 ex_*，
//     EX/M 是 m_*，M/WB 是 wb_*。例如 ex_pc 就是"EX 段那条指令的 PC"。
//   - 各段内部的组合信号用同一前缀，例如 ex_fwdA、m_redirect。
//   - 控制信号沿用课程名字：ex_ALUctr、m_MemWr、wb_RegWr ……
// 每个流水线寄存器装三类东西：数据、控制信号、身份信息（rd/rs1/rs2、有效位、PC、指令）。
// 气泡 = 有效位和全部控制信号清零（其余字段也清零，波形更干净）。复位时所有流水线寄存器都是气泡。
module cpu_core (
    input  wire        clk,
    input  wire        rst,
    // 指令存储器
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,
    // 数据总线（数据存储器 + I/O），M 段使用
    output wire [31:0] dbus_addr,
    output wire        dbus_re,
    output wire        dbus_we,
    output wire [31:0] dbus_wdata,
    input  wire [31:0] dbus_rdata,
    // 计数事件
    output wire        retire,
    output wire        stall_evt,
    output wire        flush_evt
);

    // ==================================================================
    // 流水线寄存器（集中声明，因为后面的段会反过来用到前面的字段）
    // ==================================================================
    // PC（IF 段）
    reg [31:0] if_pc;

    // IF/ID
    reg        id_valid;
    reg [31:0] id_pc;
    reg [31:0] id_inst;

    // ID/EX
    reg        ex_valid;
    reg [31:0] ex_pc;
    reg [31:0] ex_inst;
    reg [4:0]  ex_rs1, ex_rs2, ex_rd;    // rs1/rs2 供 EX 段的转发单元比较
    reg [31:0] ex_busA, ex_busB, ex_imm;
    reg        ex_ALUASrc;
    reg [1:0]  ex_ALUBSrc;
    reg [3:0]  ex_ALUctr;
    reg        ex_Branch, ex_Jump, ex_MemRead, ex_MemWr, ex_MemtoReg, ex_RegWr;

    // EX/M
    reg        m_valid;
    reg [31:0] m_pc;
    reg [31:0] m_inst;
    reg [4:0]  m_rs2, m_rd;              // rs2 供 M 段的 DiSrc 比较
    reg [31:0] m_aluout;                 // 运算结果（load/store 的地址）
    reg [31:0] m_target;                 // 跳转目标
    reg        m_cond;                   // 条件成立
    reg [31:0] m_busB;                   // store 数据（转发之后的 busB）
    reg        m_Branch, m_Jump, m_MemRead, m_MemWr, m_MemtoReg, m_RegWr;

    // M/WB
    reg        wb_valid;
    /* verilator lint_off UNUSEDSIGNAL */  // PC、指令只供调试和测试平台观察
    reg [31:0] wb_pc;
    reg [31:0] wb_inst;
    /* verilator lint_on UNUSEDSIGNAL */
    reg [4:0]  wb_rd;
    reg [31:0] wb_aluout;
    reg [31:0] wb_dout;                  // 存储器 / I/O 读出的数据
    reg        wb_MemtoReg, wb_RegWr;

    // 冒险控制与反馈
    wire        stall;       // load-use：PC、IF/ID 保持，ID/EX 进气泡
    wire        flush;       // 跳转冲刷：IF/ID、ID/EX、EX/M 进气泡
    wire        m_redirect;  // M 段跳转成立，PC 换成 m_target
    wire [31:0] wb_busW;     // WB 段最终写回值

    // ==================================================================
    // IF
    // ==================================================================
    wire [31:0] if_inst = imem_rdata;
    wire [31:0] if_pc_plus4 = if_pc + 32'd4;

    assign imem_addr = if_pc;

    // 优先级：重定向 > 停顿 > PC+4
    always @(posedge clk) begin
        if (rst)
            if_pc <= 32'b0;
        else if (m_redirect)
            if_pc <= m_target;
        else if (!stall)
            if_pc <= if_pc_plus4;
    end

    // ==================================================================
    // IF/ID
    // ==================================================================
    always @(posedge clk) begin
        if (rst || flush) begin
            id_valid <= 1'b0;
            id_pc    <= 32'b0;
            id_inst  <= 32'b0;  // 全 0 不是合法指令，译码为气泡
        end else if (!stall) begin
            id_valid <= 1'b1;
            id_pc    <= if_pc;
            id_inst  <= if_inst;
        end
    end

    // ==================================================================
    // ID
    // ==================================================================
    // RISC-V 的寄存器号位置固定，不必等译码就能读寄存器堆
    wire [4:0] id_rs1 = id_inst[19:15];
    wire [4:0] id_rs2 = id_inst[24:20];
    wire [4:0] id_rd  = id_inst[11:7];

    wire [2:0] id_ExtOp;
    wire       id_ALUASrc;
    wire [1:0] id_ALUBSrc;
    wire [3:0] id_ALUctr;
    wire       id_Branch, id_Jump, id_MemRead, id_MemWr, id_MemtoReg, id_RegWr;
    wire       id_UseRs1, id_UseRs2;

    control u_ctrl (
        .opcode   (id_inst[6:0]),
        .funct3   (id_inst[14:12]),
        .funct7   (id_inst[31:25]),
        .ExtOp    (id_ExtOp),
        .ALUASrc  (id_ALUASrc),
        .ALUBSrc  (id_ALUBSrc),
        .ALUctr   (id_ALUctr),
        .Branch   (id_Branch),
        .Jump     (id_Jump),
        .MemRead  (id_MemRead),
        .MemWr    (id_MemWr),
        .MemtoReg (id_MemtoReg),
        .RegWr    (id_RegWr),
        .UseRs1   (id_UseRs1),
        .UseRs2   (id_UseRs2)
    );

    wire [31:0] id_busA, id_busB;

    regfile u_rf (
        .clk (clk),
        .ra1 (id_rs1),
        .ra2 (id_rs2),
        .rd1 (id_busA),
        .rd2 (id_busB),
        .we  (wb_RegWr),
        .wa  (wb_rd),
        .wd  (wb_busW)
    );

    wire [31:0] id_imm;

    extender u_ext (
        .inst  (id_inst[31:7]),
        .ExtOp (id_ExtOp),
        .imm   (id_imm)
    );

    hazard_unit u_hzd (
        .id_rs1     (id_rs1),
        .id_rs2     (id_rs2),
        .id_UseRs1  (id_UseRs1),
        .id_UseRs2  (id_UseRs2),
        .id_MemWr   (id_MemWr),
        .ex_rd      (ex_rd),
        .ex_MemRead (ex_MemRead),
        .m_redirect (m_redirect),
        .stall      (stall),
        .flush      (flush)
    );

    // ==================================================================
    // ID/EX
    // ==================================================================
    // 课程数据通路里 ID/EX 前"选控制信号还是选 0"的选择器：停顿、冲刷、复位时写入气泡
    always @(posedge clk) begin
        if (rst || flush || stall) begin
            ex_valid    <= 1'b0;
            ex_pc       <= 32'b0;
            ex_inst     <= 32'b0;
            ex_rs1      <= 5'b0;
            ex_rs2      <= 5'b0;
            ex_rd       <= 5'b0;
            ex_busA     <= 32'b0;
            ex_busB     <= 32'b0;
            ex_imm      <= 32'b0;
            ex_ALUASrc  <= `ASRC_RS1;
            ex_ALUBSrc  <= `BSRC_RS2;
            ex_ALUctr   <= `ALU_ADD;
            ex_Branch   <= 1'b0;
            ex_Jump     <= 1'b0;
            ex_MemRead  <= 1'b0;
            ex_MemWr    <= 1'b0;
            ex_MemtoReg <= 1'b0;
            ex_RegWr    <= 1'b0;
        end else begin
            ex_valid    <= id_valid;
            ex_pc       <= id_pc;
            ex_inst     <= id_inst;
            ex_rs1      <= id_rs1;
            ex_rs2      <= id_rs2;
            ex_rd       <= id_rd;
            ex_busA     <= id_busA;
            ex_busB     <= id_busB;
            ex_imm      <= id_imm;
            ex_ALUASrc  <= id_ALUASrc;
            ex_ALUBSrc  <= id_ALUBSrc;
            ex_ALUctr   <= id_ALUctr;
            ex_Branch   <= id_Branch;
            ex_Jump     <= id_Jump;
            ex_MemRead  <= id_MemRead;
            ex_MemWr    <= id_MemWr;
            ex_MemtoReg <= id_MemtoReg;
            ex_RegWr    <= id_RegWr;
        end
    end

    // ==================================================================
    // EX
    // ==================================================================
    wire [1:0] ex_BusAFw, ex_BusBFw;
    wire       m_DiSrc;

    forward_unit u_fwd (
        .ex_rs1    (ex_rs1),
        .ex_rs2    (ex_rs2),
        .m_rd      (m_rd),
        .m_RegWr   (m_RegWr),
        .m_MemRead (m_MemRead),
        .m_rs2     (m_rs2),
        .m_MemWr   (m_MemWr),
        .wb_rd     (wb_rd),
        .wb_RegWr  (wb_RegWr),
        .BusAFw    (ex_BusAFw),
        .BusBFw    (ex_BusBFw),
        .DiSrc     (m_DiSrc)
    );

    // 转发选择器
    reg [31:0] ex_fwdA, ex_fwdB;
    always @(*) begin
        case (ex_BusAFw)
            `FW_M:   ex_fwdA = m_aluout;
            `FW_WB:  ex_fwdA = wb_busW;
            default: ex_fwdA = ex_busA;
        endcase
        case (ex_BusBFw)
            `FW_M:   ex_fwdB = m_aluout;
            `FW_WB:  ex_fwdB = wb_busW;
            default: ex_fwdB = ex_busB;
        endcase
    end

    // ALU 两端选择
    wire [31:0] ex_alu_a = (ex_ALUASrc == `ASRC_PC) ? ex_pc : ex_fwdA;
    reg  [31:0] ex_alu_b;
    always @(*) begin
        case (ex_ALUBSrc)
            `BSRC_IMM: ex_alu_b = ex_imm;
            `BSRC_4:   ex_alu_b = 32'd4;
            default:   ex_alu_b = ex_fwdB;
        endcase
    end

    wire [31:0] ex_aluout;
    wire        ex_zero;

    alu u_alu (
        .a      (ex_alu_a),
        .b      (ex_alu_b),
        .ALUctr (ex_ALUctr),
        .y      (ex_aluout),
        .zero   (ex_zero)
    );

    // 目标加法器：beq、jal 的跳转目标
    wire [31:0] ex_target = ex_pc + ex_imm;
    // 条件成立：基础版本只有 beq，即 rs1 - rs2 == 0
    wire        ex_cond = ex_zero;

    // ==================================================================
    // EX/M
    // ==================================================================
    always @(posedge clk) begin
        if (rst || flush) begin
            m_valid    <= 1'b0;
            m_pc       <= 32'b0;
            m_inst     <= 32'b0;
            m_rd       <= 5'b0;
            m_rs2      <= 5'b0;
            m_aluout   <= 32'b0;
            m_target <= 32'b0;
            m_cond     <= 1'b0;
            m_busB     <= 32'b0;
            m_Branch   <= 1'b0;
            m_Jump     <= 1'b0;
            m_MemRead  <= 1'b0;
            m_MemWr    <= 1'b0;
            m_MemtoReg <= 1'b0;
            m_RegWr    <= 1'b0;
        end else begin
            m_valid    <= ex_valid;
            m_pc       <= ex_pc;
            m_inst     <= ex_inst;
            m_rd       <= ex_rd;
            m_rs2      <= ex_rs2;
            m_aluout   <= ex_aluout;
            m_target <= ex_target;
            m_cond     <= ex_cond;
            // 存进 EX/M 的 store 数据取转发选择器之后的 busB（ALUBSrc 选择器之前），
            // 否则"运算后隔一条 store"会把旧值写进存储器（设计文档第五节）
            m_busB     <= ex_fwdB;
            m_Branch   <= ex_Branch;
            m_Jump     <= ex_Jump;
            m_MemRead  <= ex_MemRead;
            m_MemWr    <= ex_MemWr;
            m_MemtoReg <= ex_MemtoReg;
            m_RegWr    <= ex_RegWr;
        end
    end

    // ==================================================================
    // M
    // ==================================================================
    // 跳转在 M 段决定：选择信号全部来自寄存器，时序宽松
    assign m_redirect = (m_Branch & m_cond) | m_Jump;

    // DiSrc：load 后紧跟 store 时，用 WB 段的写回值修正 store 数据
    wire [31:0] m_DataIn = m_DiSrc ? wb_busW : m_busB;

    assign dbus_addr  = m_aluout;
    assign dbus_re    = m_MemRead;
    assign dbus_we    = m_MemWr;
    assign dbus_wdata = m_DataIn;

    wire [31:0] m_dout = dbus_rdata;

    // ==================================================================
    // M/WB
    // ==================================================================
    always @(posedge clk) begin
        if (rst) begin
            wb_valid    <= 1'b0;
            wb_pc       <= 32'b0;
            wb_inst     <= 32'b0;
            wb_rd     <= 5'b0;
            wb_aluout   <= 32'b0;
            wb_dout     <= 32'b0;
            wb_MemtoReg <= 1'b0;
            wb_RegWr  <= 1'b0;
        end else begin
            wb_valid    <= m_valid;
            wb_pc       <= m_pc;
            wb_inst     <= m_inst;
            wb_rd     <= m_rd;
            wb_aluout   <= m_aluout;
            wb_dout     <= m_dout;
            wb_MemtoReg <= m_MemtoReg;
            wb_RegWr  <= m_RegWr;
        end
    end

    // ==================================================================
    // WB
    // ==================================================================
    assign wb_busW  = wb_MemtoReg ? wb_dout : wb_aluout;

    // ==================================================================
    // 计数事件
    // ==================================================================
    assign retire    = wb_valid;
    assign stall_evt = stall;
    assign flush_evt = flush;

endmodule
