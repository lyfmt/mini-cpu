`timescale 1ns / 1ps

// mini-cpu 测试平台。
//
// plusargs：
//   +IMEM=<path> +DMEM=<path>   必需，程序镜像（$readmemh 格式，各 1024 行）
//   +EXPECT=<path>              可选，期望轨迹，在线逐条比对
//   +TRACE=<path>               可选，把 CPU 轨迹写到文件（只有 R、M 行）
//   +MAXCYCLES=<n>              可选，默认 2000000，超时判 FAIL
//   +PIPE                       可选，每周期打印一行流水线时空图
//
// 参数 HAS_QMUL（默认 1）原样传给 cpu_top；为 0 时 CPU 不带模乘单元，qmul 按非法指令处理。
// 在命令行上改：iverilog -Ptb_top.HAS_QMUL=0，ModelSim vsim -gHAS_QMUL=0。
//
// 轨迹采集（每个周期的时钟上升沿、寄存器更新之前采样）：
//   先 WB 段的 R 事件（有效、RegWr=1、rd!=0），再 M 段的 M 事件（有效、MemWr=1），即程序顺序。
// M 段写 FINISH 的那个周期结束后停止；最后一行固定是 RESULT 行。
module tb_top #(
    parameter HAS_QMUL = 1
);

    // ------------------------------------------------------------------
    // 时钟、复位、被测设计
    // ------------------------------------------------------------------
    reg clk = 1'b0;
    reg rst = 1'b1;

    always #5 clk = ~clk;

    wire        finish;
    wire        mark;
    wire [31:0] io_wdata;

    cpu_top #(
        .HAS_QMUL (HAS_QMUL)
    ) u_cpu (
        .clk      (clk),
        .rst      (rst),
        .finish   (finish),
        .mark     (mark),
        .io_wdata (io_wdata)
    );

    // ------------------------------------------------------------------
    // 观察的内部信号
    // ------------------------------------------------------------------
    wire [31:0] if_pc      = u_cpu.u_core.if_pc;
    wire        id_valid   = u_cpu.u_core.id_valid;
    wire [31:0] id_pc      = u_cpu.u_core.id_pc;
    wire        ex_valid   = u_cpu.u_core.ex_valid;
    wire [31:0] ex_pc      = u_cpu.u_core.ex_pc;
    wire        m_valid    = u_cpu.u_core.m_valid;
    wire [31:0] m_pc       = u_cpu.u_core.m_pc;
    wire        m_MemWr    = u_cpu.u_core.m_MemWr;
    wire [31:0] m_addr     = u_cpu.u_core.dbus_addr;
    wire [31:0] m_wdata    = u_cpu.u_core.dbus_wdata;
    wire [31:0] m_target   = u_cpu.u_core.m_target;
    wire        wb_valid   = u_cpu.u_core.wb_valid;
    wire [31:0] wb_pc      = u_cpu.u_core.wb_pc;
    wire        wb_RegWr   = u_cpu.u_core.wb_RegWr;
    wire [4:0]  wb_rd      = u_cpu.u_core.wb_rd;
    wire [31:0] wb_busW    = u_cpu.u_core.wb_busW;
    wire [1:0]  BusAFw     = u_cpu.u_core.ex_BusAFw;
    wire [1:0]  BusBFw     = u_cpu.u_core.ex_BusBFw;
    wire        DiSrc      = u_cpu.u_core.m_DiSrc;
    wire        stall      = u_cpu.u_core.stall;
    wire        flush      = u_cpu.u_core.flush;

    wire [31:0] hw_cycles  = u_cpu.u_io.cycle_cnt;
    wire [31:0] hw_instret = u_cpu.u_io.instret_cnt;
    wire [31:0] hw_stalls  = u_cpu.u_io.stall_cnt;
    wire [31:0] hw_flushes = u_cpu.u_io.flush_cnt;

    // ------------------------------------------------------------------
    // 状态
    // ------------------------------------------------------------------
    reg [8*1024-1:0] imem_file, dmem_file, expect_file, trace_file;
    reg              have_expect, have_trace, pipe_en;
    integer          max_cycles;
    integer          exp_fd, trc_fd, fd;
    integer          cyc;            // 复位释放以来的周期号，与硬件 CYCLE 一致
    reg              done;

    // 0 = 运行中，1 = PASS，2 = FAIL。仿真结束后可在仿真器里读取它判定结果（如 ModelSim 的 examine）。
    reg [1:0]        result_status;

    // 最近读入的一条期望事件
    reg [63:0]       e_typ;
    reg [31:0]       e_pc, e_a, e_d;
    reg              e_ok;
    integer          scan_n;

    // ------------------------------------------------------------------
    // 结束
    // ------------------------------------------------------------------
    task close_files;
        begin
            if (have_trace)  $fclose(trc_fd);
            if (have_expect) $fclose(exp_fd);
            have_trace  = 1'b0;
            have_expect = 1'b0;
        end
    endtask

    // RESULT 行里的计数器取硬件计数器当拍的值；复位释放前就失败时记 0
    reg started;

    function [31:0] cnt;
        input [31:0] v;
        cnt = started ? v : 32'd0;
    endfunction

    task end_pass;
        begin
            done = 1'b1;
            result_status = 2'd1;
            close_files;
            $display("RESULT: PASS cycles=%0d instret=%0d stalls=%0d flushes=%0d",
                     cnt(hw_cycles), cnt(hw_instret), cnt(hw_stalls), cnt(hw_flushes));
            $finish(0);
        end
    endtask

    // 失败原因。原因串直接写在 $display 的格式里，不经过 reg，各仿真器打印一致。
    localparam F_MISMATCH            = 0;
    localparam F_EXTRA_EVENT         = 1;
    localparam F_MISSING_EVENT       = 2;
    localparam F_TIMEOUT             = 3;
    localparam F_NO_IMEM_PLUSARG     = 4;
    localparam F_NO_DMEM_PLUSARG     = 5;
    localparam F_CANNOT_OPEN_IMEM    = 6;
    localparam F_CANNOT_OPEN_DMEM    = 7;
    localparam F_CANNOT_OPEN_EXPECT  = 8;
    localparam F_CANNOT_OPEN_TRACE   = 9;

    task end_fail;
        input integer why;
        reg [31:0] c, i, st, fl;
        begin
            done = 1'b1;
            result_status = 2'd2;
            close_files;
            c  = cnt(hw_cycles);
            i  = cnt(hw_instret);
            st = cnt(hw_stalls);
            fl = cnt(hw_flushes);
            case (why)
                F_MISMATCH:            $display("RESULT: FAIL mismatch cycles=%0d instret=%0d stalls=%0d flushes=%0d", c, i, st, fl);
                F_EXTRA_EVENT:         $display("RESULT: FAIL extra_event cycles=%0d instret=%0d stalls=%0d flushes=%0d", c, i, st, fl);
                F_MISSING_EVENT:       $display("RESULT: FAIL missing_event cycles=%0d instret=%0d stalls=%0d flushes=%0d", c, i, st, fl);
                F_TIMEOUT:             $display("RESULT: FAIL timeout cycles=%0d instret=%0d stalls=%0d flushes=%0d", c, i, st, fl);
                F_NO_IMEM_PLUSARG:     $display("RESULT: FAIL no_imem_plusarg cycles=%0d instret=%0d stalls=%0d flushes=%0d", c, i, st, fl);
                F_NO_DMEM_PLUSARG:     $display("RESULT: FAIL no_dmem_plusarg cycles=%0d instret=%0d stalls=%0d flushes=%0d", c, i, st, fl);
                F_CANNOT_OPEN_IMEM:    $display("RESULT: FAIL cannot_open_imem cycles=%0d instret=%0d stalls=%0d flushes=%0d", c, i, st, fl);
                F_CANNOT_OPEN_DMEM:    $display("RESULT: FAIL cannot_open_dmem cycles=%0d instret=%0d stalls=%0d flushes=%0d", c, i, st, fl);
                F_CANNOT_OPEN_EXPECT:  $display("RESULT: FAIL cannot_open_expect cycles=%0d instret=%0d stalls=%0d flushes=%0d", c, i, st, fl);
                F_CANNOT_OPEN_TRACE:   $display("RESULT: FAIL cannot_open_trace cycles=%0d instret=%0d stalls=%0d flushes=%0d", c, i, st, fl);
                default:               $display("RESULT: FAIL unknown cycles=%0d instret=%0d stalls=%0d flushes=%0d", c, i, st, fl);
            endcase
            $finish(0);
        end
    endtask

    // FINISH 写入非 0：失败原因里带上结果码
    task end_fail_code;
        input [31:0] code;
        begin
            done = 1'b1;
            result_status = 2'd2;
            close_files;
            $display("RESULT: FAIL finish_code=%0d cycles=%0d instret=%0d stalls=%0d flushes=%0d",
                     code, cnt(hw_cycles), cnt(hw_instret), cnt(hw_stalls), cnt(hw_flushes));
            $finish(0);
        end
    endtask

    // ------------------------------------------------------------------
    // 轨迹
    // ------------------------------------------------------------------
    task show_event;
        input            is_expected;   // 1 = 期望事件，0 = 实际事件
        input [7:0]      typ;
        input [31:0]     pc, a, d;
        begin
            if (is_expected)
                $write("  expected: ");
            else
                $write("  actual:   ");
            if (typ == "M")
                $display("M %h %h %h", pc, a, d);
            else
                $display("%s %h %h %h", typ, pc, a[7:0], d);
        end
    endtask

    task read_expect;
        begin
            e_ok   = 1'b0;
            e_typ  = 64'b0;
            scan_n = $fscanf(exp_fd, "%s %h %h %h\n", e_typ, e_pc, e_a, e_d);
            if (scan_n == 4)
                e_ok = 1'b1;
        end
    endtask

    // 输出一条 CPU 事件：写 TRACE 文件，并与期望轨迹比对
    task emit;
        input [7:0]  typ;
        input [31:0] pc, a, d;
        reg          match;
        begin
            if (have_trace) begin
                if (typ == "M")
                    $fdisplay(trc_fd, "M %h %h %h", pc, a, d);
                else
                    $fdisplay(trc_fd, "R %h %h %h", pc, a[7:0], d);
            end
            if (have_expect) begin
                read_expect;
                if (!e_ok)
                    match = 1'b0;
                else if (e_typ == "X")  // 读计数器的 load：只比 pc 和 rd
                    match = (typ == "R") && (e_pc === pc) && (e_a === a);
                else
                    match = (e_typ == typ) && (e_pc === pc) && (e_a === a) && (e_d === d);
                if (!match) begin
                    $display("MISMATCH at cycle %0d pc=%h", cyc, pc);
                    if (e_ok)
                        show_event(1'b1, e_typ[7:0], e_pc, e_a, e_d);
                    else
                        $display("  expected: <end of trace>");
                    show_event(1'b0, typ, pc, a, d);
                    if (e_ok)
                        end_fail(F_MISMATCH);
                    else
                        end_fail(F_EXTRA_EVENT);     // 期望轨迹已用完，CPU 还在产生事件
                end
            end
        end
    endtask

    // ------------------------------------------------------------------
    // 流水线时空图
    // ------------------------------------------------------------------
    // 有效时给出 8 位十六进制 PC，气泡给出 "--------"
    function [63:0] pc_str;
        input        valid;
        input [31:0] pc;
        integer      k;
        reg   [3:0]  nib;
        begin
            if (!valid) begin
                pc_str = "--------";
            end else begin
                for (k = 0; k < 8; k = k + 1) begin
                    nib = pc[k*4 +: 4];
                    if (^nib === 1'bx)
                        pc_str[k*8 +: 8] = "x";
                    else if (nib < 4'd10)
                        pc_str[k*8 +: 8] = "0" + nib;
                    else
                        pc_str[k*8 +: 8] = "a" + nib - 4'd10;
                end
            end
        end
    endfunction

    // 一行一个周期：五级的 PC（气泡为 --------），当拍的 BusAFw/BusBFw/DiSrc/stall/flush，
    // 行尾再用标记重复一遍当拍生效的机制，便于肉眼和 grep 查找：
    //   A<-M / A<-WB、B<-M / B<-WB：转发来源；DiSrc：store 数据用 WB 写回值修正；
    //   STALL：load-use 停顿；FLUSH->目标：跳转成立，冲刷前三级。
    // 注意转发选择只按寄存器号判断，不看 EX 段那条指令是否真的读这个操作数
    // （例如 ori 的 rs2 字段其实是立即数），这种转发不影响结果，照样标出。
    task print_pipe;
        begin
            $write("PIPE %6d | IF %s | ID %s | EX %s | M %s | WB %s | FwA %b FwB %b DiSrc %b stall %b flush %b |",
                   cyc,
                   pc_str(1'b1, if_pc), pc_str(id_valid, id_pc), pc_str(ex_valid, ex_pc),
                   pc_str(m_valid, m_pc), pc_str(wb_valid, wb_pc),
                   BusAFw, BusBFw, DiSrc, stall, flush);
            if (BusAFw == 2'b10) $write(" A<-M");
            if (BusAFw == 2'b01) $write(" A<-WB");
            if (BusBFw == 2'b10) $write(" B<-M");
            if (BusBFw == 2'b01) $write(" B<-WB");
            if (DiSrc)           $write(" DiSrc");
            if (stall)           $write(" STALL");
            if (flush)           $write(" FLUSH->%h", m_target);
            $write("\n");
        end
    endtask

    // ------------------------------------------------------------------
    // 初始化：读 plusargs、载入镜像、复位
    // ------------------------------------------------------------------
    initial begin
        done          = 1'b0;
        started       = 1'b0;
        result_status = 2'd0;
        cyc           = 0;
        have_expect   = 1'b0;
        have_trace    = 1'b0;

        if (!$value$plusargs("MAXCYCLES=%d", max_cycles))
            max_cycles = 2000000;
        pipe_en = $test$plusargs("PIPE");

        if (!$value$plusargs("IMEM=%s", imem_file))
            end_fail(F_NO_IMEM_PLUSARG);
        if (!done && !$value$plusargs("DMEM=%s", dmem_file))
            end_fail(F_NO_DMEM_PLUSARG);

        // 先确认文件能打开，$readmemh 打不开文件只给警告
        if (!done) begin
            fd = $fopen(imem_file, "r");
            if (fd == 0) begin
                $display("cannot open IMEM file %0s", imem_file);
                end_fail(F_CANNOT_OPEN_IMEM);
            end else
                $fclose(fd);
        end
        if (!done) begin
            fd = $fopen(dmem_file, "r");
            if (fd == 0) begin
                $display("cannot open DMEM file %0s", dmem_file);
                end_fail(F_CANNOT_OPEN_DMEM);
            end else
                $fclose(fd);
        end
        if (!done) begin
            $readmemh(imem_file, u_cpu.u_imem.mem);
            $readmemh(dmem_file, u_cpu.u_dmem.mem);
        end

        if (!done && $value$plusargs("EXPECT=%s", expect_file)) begin
            exp_fd = $fopen(expect_file, "r");
            if (exp_fd == 0) begin
                $display("cannot open EXPECT file %0s", expect_file);
                end_fail(F_CANNOT_OPEN_EXPECT);
            end else
                have_expect = 1'b1;
        end
        if (!done && $value$plusargs("TRACE=%s", trace_file)) begin
            trc_fd = $fopen(trace_file, "w");
            if (trc_fd == 0) begin
                $display("cannot open TRACE file %0s", trace_file);
                end_fail(F_CANNOT_OPEN_TRACE);
            end else
                have_trace = 1'b1;
        end

        // 同步复位保持 3 个时钟沿，在下降沿释放
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst     = 1'b0;
        started = 1'b1;
    end

    // ------------------------------------------------------------------
    // 每周期：时空图、采集事件、MARK、FINISH、超时
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst && !done) begin
            if (pipe_en)
                print_pipe;

            if (wb_valid && wb_RegWr && wb_rd != 5'd0)
                emit("R", wb_pc, {27'b0, wb_rd}, wb_busW);

            if (!done && m_valid && m_MemWr)
                emit("M", m_pc, m_addr, m_wdata);

            if (!done && mark)
                $display("MARK %h cycles=%0d instret=%0d stalls=%0d flushes=%0d",
                         io_wdata, hw_cycles, hw_instret, hw_stalls, hw_flushes);

            if (!done && finish) begin
                if (have_expect) begin
                    read_expect;
                    if (e_ok) begin
                        $display("MISMATCH at cycle %0d: program finished but the expected trace continues", cyc);
                        show_event(1'b1, e_typ[7:0], e_pc, e_a, e_d);
                        end_fail(F_MISSING_EVENT);   // 程序已结束，期望轨迹还没用完
                    end
                end
                if (!done) begin
                    if (io_wdata == 32'd0) begin
                        end_pass;
                    end else begin
                        end_fail_code(io_wdata);
                    end
                end
            end

            if (!done && cyc + 1 >= max_cycles) begin
                $display("TIMEOUT after %0d cycles", max_cycles);
                end_fail(F_TIMEOUT);
            end

            cyc = cyc + 1;
        end
    end

endmodule
