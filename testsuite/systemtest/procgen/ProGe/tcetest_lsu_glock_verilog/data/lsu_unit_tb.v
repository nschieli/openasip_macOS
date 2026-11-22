// Unit testbench: the legacy OpenASIP LSU (fu_ldh_ldhu_ldq_ldqu_ldw_sth_stq_stw_always_3) under random global-lock (glock) spans.
// The testbench plays the TTA core: it issues random word stores/loads, holds an op on the ports while glock is high (the op completes
// when glock drops), and reads each load result LAT unlocked cycles after the op was accepted. The data memory is a 1-port synchronous
// RAM; by default (MEMMODEL 3) it is stalled by glock like every other unit (no access, output held while glock is high). Every load
// result is checked against a reference model.
// Plusargs: +STALL=0|1 +SEED=n +OPS=n. Prints "PASS" or "FAIL <n> mismatches".
`ifndef MEMMODEL
`define MEMMODEL 3
`endif
`ifndef LAT
`define LAT 3
`endif
`timescale 1ns / 1ps
module lsu_unit_tb;
    localparam AW = 12, MW = AW - 2, LAT = `LAT;
    reg clk = 0; always #5 clk = ~clk;
    reg rstx = 0, glock = 0;
    reg [AW-1:0] t1data = 0; reg t1load = 0; reg [2:0] t1op = 0; reg [31:0] o1data = 0; reg o1load = 0;
    wire [31:0] r1, dout, mask; wire [MW-1:0] addr; wire en_x, wr_x;
    fu_ldh_ldhu_ldq_ldqu_ldw_sth_stq_stw_always_3 #(.dataw(32), .addrw(AW)) dut(
        .t1data(t1data), .t1load(t1load), .t1opcode(t1op), .o1data(o1data), .o1load(o1load), .r1data(r1),
        .data_in(q_out), .data_out(dout), .addr(addr), .mem_en_x(en_x), .wr_en_x(wr_x), .wr_mask_x(mask),
        .glock(glock), .clk(clk), .rstx(rstx));
    // 1-port sync RAM. `MEMMODEL 0 (GARBAGE): output is garbage while glock is high. `MEMMODEL 1 (SHARED): while the core is locked the
    // port serves another master (random reads), so the output register changes; when the core runs again the port serves the LSU.
    reg [31:0] mem [0:(1<<MW)-1]; reg [31:0] q, junk;
    wire [31:0] q_out = (`MEMMODEL == 0 && glock) ? junk : q;
    always @(posedge clk) begin
        junk <= $random;
        if (`MEMMODEL == 3 && glock) ;   // MEMMODEL 3 (FROZEN): the memory port is stalled by glock too (no access, output held)
        else if (`MEMMODEL == 1 && glock) q <= mem[junk[MW-1:0]];
        else if (!en_x) begin if (!wr_x) mem[addr] <= (dout & ~mask) | (mem[addr] & mask); q <= mem[addr]; end
    end
    reg [31:0] model [0:(1<<MW)-1];
    integer i, ops, stall, seed, left, n, bad, pend_age [0:7], npend;
    reg [31:0] pend_exp [0:7]; reg [31:0] lf;
    localparam OPC_LDW = 3'd4, OPC_STW = 3'd7;
    initial begin
        if (!$value$plusargs("STALL=%d", stall)) stall = 0;
        if (!$value$plusargs("SEED=%d", seed)) seed = 1;
        if (!$value$plusargs("OPS=%d", ops)) ops = 4000;
        lf = seed * 32'h9e3779b1 + 1; left = 0; bad = 0; npend = 0;
        for (i = 0; i < (1<<MW); i = i + 1) begin mem[i] = i * 32'h01000193; model[i] = mem[i]; end
        repeat (3) @(negedge clk); rstx = 1;
        n = 0;
        while (n < ops || npend > 0) begin
            @(negedge clk);
            lf = {lf[30:0], lf[31] ^ lf[21] ^ lf[1] ^ lf[0]};
            if (stall && left == 0 && (lf[3:0] == 4'd5)) left = 1 + lf[11:8];
            if (left > 0) begin glock = 1; left = left - 1; end
            else begin
                glock = 0;
                // results due this unlocked cycle (accepted LAT unlocked cycles ago)
                for (i = 0; i < npend; i = i + 1) pend_age[i] = pend_age[i] + 1;
                if (npend > 0 && pend_age[0] == LAT) begin
                    if (r1 !== pend_exp[0]) begin bad = bad + 1; if (bad <= 5) $display("MISMATCH load got %h want %h", r1, pend_exp[0]); end
                    for (i = 0; i < npend - 1; i = i + 1) begin pend_age[i] = pend_age[i+1]; pend_exp[i] = pend_exp[i+1]; end
                    npend = npend - 1;
                end
                // next op (the op on the ports at an unlocked cycle is accepted now)
                if (n < ops) begin
                    t1data = {lf[17:8], 2'b00}; o1data = lf ^ 32'h5a5a0000;
                    if (lf[20]) begin t1op = OPC_STW; o1load = 1; t1load = 1; model[lf[17:8]] = o1data; end
                    else begin t1op = OPC_LDW; o1load = 0; t1load = 1; pend_exp[npend] = model[lf[17:8]]; pend_age[npend] = 0; npend = npend + 1; end
                    n = n + 1;
                end else begin t1load = 0; o1load = 0; end
            end
        end
        if (bad == 0) $display("PASS %0d ops (stall=%0d seed=%0d)", ops, stall, seed); else $display("FAIL %0d mismatches (stall=%0d seed=%0d)", bad, stall, seed);
        $finish;
    end
endmodule
