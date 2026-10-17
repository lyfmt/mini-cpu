`timescale 1ns / 1ps

// 主控制器穷举单元测试：opcode × funct3 × funct7 全部 2^17 种组合，
// 与这里独立写出的译码表（RV32I 子集 + qmul）逐个字段对照：
//   - 合法性：非法编码必须输出全部为默认值的气泡控制信号；
//   - 合法指令：ExtOp、ALUASrc、ALUBSrc、ALUctr、TargetSrc、BrOp、Branch、Jump、
//     MemRead、MemWr、MemtoReg、RegWr、UseRs1、UseRs2 全部比较（"无关"的字段也按默认值比较）。
// 参数 HAS_QMUL 传给被测的 control；为 0 时 qmul 也必须是非法编码。
// HAS_QMUL 的两种取值需各运行一次。
module tb_control;
    parameter HAS_QMUL = 1;

    reg  [6:0] op, f7;
    reg  [2:0] f3;
    wire [2:0] ExtOp, BrOp;
    wire       ALUASrc, TargetSrc, Branch, Jump, MemRead, MemWr, MemtoReg, RegWr, UseRs1, UseRs2;
    wire [1:0] ALUBSrc;
    wire [3:0] ALUctr;

    control #(.HAS_QMUL(HAS_QMUL)) dut (
        .opcode(op), .funct3(f3), .funct7(f7),
        .ExtOp(ExtOp), .ALUASrc(ALUASrc), .ALUBSrc(ALUBSrc), .ALUctr(ALUctr),
        .TargetSrc(TargetSrc), .BrOp(BrOp), .Branch(Branch), .Jump(Jump),
        .MemRead(MemRead), .MemWr(MemWr), .MemtoReg(MemtoReg), .RegWr(RegWr),
        .UseRs1(UseRs1), .UseRs2(UseRs2));

    // 期望值。编码直接写数字，不引用 defines.vh，免得和被测代码共用同一个错误。
    reg [2:0] e_ExtOp, e_BrOp;
    reg       e_ALUASrc, e_TargetSrc, e_Branch, e_Jump, e_MemRead, e_MemWr, e_MemtoReg, e_RegWr, e_U1, e_U2;
    reg [1:0] e_ALUBSrc;
    reg [3:0] e_ALUctr;
    reg       legal;

    integer i, errs, nlegal;
    reg [16:0] k;

    initial begin
        errs = 0;
        nlegal = 0;
        for (i = 0; i < (1 << 17); i = i + 1) begin
            k  = i;
            op = k[6:0];
            f3 = k[9:7];
            f7 = k[16:10];
            #1;
            // 默认值 = 气泡
            e_ExtOp = 3'd0; e_ALUASrc = 1'b0; e_ALUBSrc = 2'b00; e_ALUctr = 4'b0000;
            e_TargetSrc = 1'b0; e_BrOp = 3'b000; e_Branch = 1'b0; e_Jump = 1'b0;
            e_MemRead = 1'b0; e_MemWr = 1'b0; e_MemtoReg = 1'b0; e_RegWr = 1'b0;
            e_U1 = 1'b0; e_U2 = 1'b0;
            legal = 1'b0;
            case (op)
                7'b0110011: begin   // R 型
                    legal = (f7 == 7'h00) || (f7 == 7'h20 && (f3 == 3'd0 || f3 == 3'd5));
                    e_ALUctr = {f7[5], f3}; e_RegWr = 1; e_U1 = 1; e_U2 = 1;
                end
                7'b0010011: begin   // 立即数运算
                    legal = (f3 == 3'd1) ? (f7 == 7'h00) :
                            (f3 == 3'd5) ? (f7 == 7'h00 || f7 == 7'h20) : 1'b1;
                    e_ExtOp = 3'd0; e_ALUBSrc = 2'b01; e_RegWr = 1; e_U1 = 1;
                    e_ALUctr = (f3 == 3'd5) ? {f7[5], f3} : {1'b0, f3};
                end
                7'b0110111: begin   // lui
                    legal = 1; e_ExtOp = 3'd3; e_ALUBSrc = 2'b01; e_ALUctr = 4'b1111; e_RegWr = 1;
                end
                7'b0010111: begin   // auipc
                    legal = 1; e_ExtOp = 3'd3; e_ALUASrc = 1; e_ALUBSrc = 2'b01; e_RegWr = 1;
                end
                7'b0000011: begin   // lw
                    legal = (f3 == 3'd2);
                    e_ALUBSrc = 2'b01; e_MemRead = 1; e_MemtoReg = 1; e_RegWr = 1; e_U1 = 1;
                end
                7'b0100011: begin   // sw
                    legal = (f3 == 3'd2);
                    e_ExtOp = 3'd1; e_ALUBSrc = 2'b01; e_MemWr = 1; e_U1 = 1; e_U2 = 1;
                end
                7'b1100011: begin   // 条件分支
                    legal = (f3 != 3'd2 && f3 != 3'd3);
                    e_ExtOp = 3'd2; e_BrOp = f3; e_Branch = 1; e_U1 = 1; e_U2 = 1;
                end
                7'b1101111: begin   // jal
                    legal = 1; e_ExtOp = 3'd4; e_ALUASrc = 1; e_ALUBSrc = 2'b10; e_Jump = 1; e_RegWr = 1;
                end
                7'b1100111: begin   // jalr
                    legal = (f3 == 3'd0);
                    e_ALUASrc = 1; e_ALUBSrc = 2'b10; e_TargetSrc = 1; e_Jump = 1; e_RegWr = 1; e_U1 = 1;
                end
                7'b0001011: begin   // custom-0：只有 qmul
                    legal = (HAS_QMUL != 0) && f3 == 3'd0 && f7 == 7'h00;
                    e_ALUctr = 4'b1001; e_RegWr = 1; e_U1 = 1; e_U2 = 1;
                end
                default: legal = 1'b0;
            endcase
            if (!legal) begin
                e_ExtOp = 3'd0; e_ALUASrc = 1'b0; e_ALUBSrc = 2'b00; e_ALUctr = 4'b0000;
                e_TargetSrc = 1'b0; e_BrOp = 3'b000; e_Branch = 1'b0; e_Jump = 1'b0;
                e_MemRead = 1'b0; e_MemWr = 1'b0; e_MemtoReg = 1'b0; e_RegWr = 1'b0;
                e_U1 = 1'b0; e_U2 = 1'b0;
            end
            nlegal = nlegal + legal;
            if ({ExtOp, ALUASrc, ALUBSrc, ALUctr, TargetSrc, BrOp, Branch, Jump,
                 MemRead, MemWr, MemtoReg, RegWr, UseRs1, UseRs2} !==
                {e_ExtOp, e_ALUASrc, e_ALUBSrc, e_ALUctr, e_TargetSrc, e_BrOp, e_Branch, e_Jump,
                 e_MemRead, e_MemWr, e_MemtoReg, e_RegWr, e_U1, e_U2}) begin
                if (errs < 10)
                    $display("ERR op=%b f3=%b f7=%b legal=%b: got ExtOp=%0d A=%b B=%b ALUctr=%b T=%b BrOp=%b Br=%b J=%b MR=%b MW=%b M2R=%b RW=%b U=%b%b",
                             op, f3, f7, legal, ExtOp, ALUASrc, ALUBSrc, ALUctr, TargetSrc, BrOp, Branch, Jump,
                             MemRead, MemWr, MemtoReg, RegWr, UseRs1, UseRs2);
                errs = errs + 1;
            end
        end
        $display("control exhaustive (HAS_QMUL=%0d): %0d encodings, %0d legal, %0d errors", HAS_QMUL, i, nlegal, errs);
        if (errs == 0) $display("UNIT PASS tb_control HAS_QMUL=%0d", HAS_QMUL);
        else           $display("UNIT FAIL tb_control HAS_QMUL=%0d (%0d errors)", HAS_QMUL, errs);
        $finish;
    end
endmodule
