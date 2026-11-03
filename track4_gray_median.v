`timescale 1ns/1ps
// Rounded BT.601 integer gray, followed by a pipelined 3x3 median.
// Latency: gray(2) + window(2) + odd/even sorting network(9) = 13 clocks.
// Original gray and median share the same window center and sync signals.
module track4_gray_median #(
    parameter integer WIDTH=1920, HEIGHT=1080, ENABLE_MEDIAN=1, RUNTIME_CONTROL=0
) (
    input wire clk,rst_n,i_vs,i_hs,i_de,
    input wire [7:0] i_r,i_g,i_b,
    input wire i_enable_median,
    output wire o_vs,o_hs,o_de,
    output wire [7:0] o_gray,o_filtered,
    output wire [23:0] o_rgb
);
    reg [23:0] rgb_a,rgb_b;
    reg [15:0] r_weight,g_weight,b_weight;
    wire [15:0] gray_sum=r_weight+g_weight+b_weight+16'd128;
    reg [7:0] gray;
    reg [2:0] sync_a,sync_b;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_weight<=0; g_weight<=0; b_weight<=0;
            gray<=0; sync_a<=0; sync_b<=0;
            rgb_a<=0; rgb_b<=0;
        end else begin
            r_weight<=i_r*16'd77; g_weight<=i_g*16'd150; b_weight<=i_b*16'd29;
            gray<=gray_sum[15:8];
            sync_a<={i_vs,i_hs,i_de}; sync_b<=sync_a;
            rgb_a<={i_r,i_g,i_b}; rgb_b<=rgb_a;
        end
    end
    wire wvs,whs,wde,valid;
    wire [31:0] p00,p01,p02,p10,p11,p12,p20,p21,p22;
    track4_window3x3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.BITS(32)) window (
        .clk(clk),.rst_n(rst_n),.i_vs(sync_b[2]),.i_hs(sync_b[1]),
        .i_de(sync_b[0]),.i_pixel({rgb_b,gray}),.o_vs(wvs),.o_hs(whs),.o_de(wde),
        .o_valid(valid),.o_right_half(),
        .p00(p00),.p01(p01),.p02(p02),.p10(p10),.p11(p11),.p12(p12),
        .p20(p20),.p21(p21),.p22(p22)
    );
    wire [71:0] sorted[0:9];
    wire [35:0] metadata[0:9];
    assign sorted[0]={p22[7:0],p21[7:0],p20[7:0],p12[7:0],p11[7:0],
                      p10[7:0],p02[7:0],p01[7:0],p00[7:0]};
    assign metadata[0]={wvs,whs,wde,valid,p11[7:0],p11[31:8]};
    genvar s,k;
    generate for (s=0;s<9;s=s+1) begin: sort_stage
        reg [71:0] values;
        reg [35:0] meta;
        assign sorted[s+1]=values;
        assign metadata[s+1]=meta;
        always @(posedge clk or negedge rst_n)
            if (!rst_n) meta<=0; else meta<=metadata[s];
        for (k=0;k<9;k=k+1) begin: compare_lane
            if (((k%2)==(s%2)) && (k<8)) begin: low_lane
                always @(posedge clk)
                    values[k*8+:8]<=(sorted[s][k*8+:8]<sorted[s][(k+1)*8+:8])
                        ? sorted[s][k*8+:8] : sorted[s][(k+1)*8+:8];
            end else if ((k>0) && (((k-1)%2)==(s%2))) begin: high_lane
                always @(posedge clk)
                    values[k*8+:8]<=(sorted[s][k*8+:8]>sorted[s][(k-1)*8+:8])
                        ? sorted[s][k*8+:8] : sorted[s][(k-1)*8+:8];
            end else begin: pass_lane
                always @(posedge clk) values[k*8+:8]<=sorted[s][k*8+:8];
            end
        end
    end endgenerate
    wire median_enabled=RUNTIME_CONTROL ? i_enable_median : (ENABLE_MEDIAN!=0);
    assign {o_vs,o_hs,o_de}=metadata[9][35:33];
    assign o_gray=metadata[9][32] ? metadata[9][31:24] : 8'd0;
    assign o_rgb=metadata[9][32] ? metadata[9][23:0] : 24'd0;
    assign o_filtered=metadata[9][32]
        ? (median_enabled ? sorted[9][32+:8] : metadata[9][31:24]) : 8'd0;
endmodule
