`timescale 1ns/1ps
// Sobel /4, Prewitt /4 or Roberts /2, saturated to 0..255. Six stages:
// window(2), weighted sides, absolute differences, sum, threshold.
// Original gray travels through the same window center as filtered gray.
module track4_sobel #(
    parameter integer WIDTH=1920, HEIGHT=1080, EDGE_THRESHOLD=80, BORDER=4,
    parameter integer RUNTIME_CONTROL=0, ADAPTIVE_THRESHOLD=0, NOISE_FLOOR=1
) (
    input wire clk,rst_n,i_vs,i_hs,i_de,
    input wire [7:0] i_gray,i_original,
    input wire [23:0] i_rgb,
    input wire [10:0] i_threshold,
    input wire i_adaptive,
    input wire [1:0] i_operator,
    output wire o_vs,o_hs,o_de,
    output wire [7:0] o_gray,
    output reg [7:0] o_edge,
    output wire o_right_half,
    output wire [23:0] o_rgb
);
    wire wvs,whs,wde,valid,right_half;
    wire [39:0] p00,p01,p02,p10,p11,p12,p20,p21,p22;
    track4_window3x3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.BITS(40),.BORDER(BORDER)) window (
        .clk(clk),.rst_n(rst_n),.i_vs(i_vs),.i_hs(i_hs),.i_de(i_de),
        .i_pixel({i_rgb,i_original,i_gray}),.o_vs(wvs),.o_hs(whs),.o_de(wde),
        .o_valid(valid),.o_right_half(right_half),
        .p00(p00),.p01(p01),.p02(p02),.p10(p10),.p11(p11),.p12(p12),
        .p20(p20),.p21(p21),.p22(p22)
    );
    reg [9:0] left_sum,right_sum,top_sum,bottom_sum,abs_x,abs_y;
    reg [10:0] magnitude;
    reg [7:0] roberts_x,roberts_y;
    reg roberts0,roberts1;
    wire [10:0] gradient_sum={1'b0,abs_x}+{1'b0,abs_y};
    wire [10:0] normalized=roberts1 ? gradient_sum>>1 : gradient_sum>>2;
    reg [36:0] meta0,meta1,meta2,meta3;
    wire [10:0] requested_threshold=RUNTIME_CONTROL ? i_threshold : EDGE_THRESHOLD;
    wire [10:0] threshold=(requested_threshold>255) ? 11'd255 : requested_threshold;
    wire adaptive=RUNTIME_CONTROL ? i_adaptive : (ADAPTIVE_THRESHOLD!=0);
    // Dark pixels use a lower threshold; a floor limits sensor-noise edges.
    wire [8:0] brightness={1'b0,p11[7:0]}+9'd64;
    reg [19:0] threshold_product;
    reg [10:0] threshold0,threshold1,threshold2;
    reg adaptive0;
    // In adaptive mode, cap the local threshold from the last complete frame's
    // strongest gradient. This follows contrast changes instead of erasing all
    // lines when the scene becomes dimmer. A flat input still produces no edge.
    reg [7:0] frame_peak,contrast_limit;
    reg [31:0] frame_pixels;
    reg frame_vs_d,frame_started;
    wire [7:0] peak_now=(magnitude>frame_peak) ? magnitude[7:0] : frame_peak;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_peak<=0; contrast_limit<=255; frame_pixels<=0;
            frame_vs_d<=0; frame_started<=0;
        end else begin
            frame_vs_d<=meta2[36];
            if (meta2[36] && !frame_vs_d) begin
                if (frame_started && frame_pixels==WIDTH*HEIGHT)
                    contrast_limit<=(frame_peak<8) ? 8'd1 : {2'd0,frame_peak[7:2]};
                frame_peak<=0; frame_pixels<=0; frame_started<=1;
            end else if (meta2[34] && !meta2[36] && frame_started) begin
                if (frame_pixels<WIDTH*HEIGHT+1) frame_pixels<=frame_pixels+1'b1;
                if (meta2[32]) frame_peak<=peak_now;
            end
        end
    end
    wire [11:0] scaled_threshold=threshold_product[19:8];
    wire [10:0] bounded_threshold=(scaled_threshold>255) ? 11'd255 :
        (scaled_threshold<NOISE_FLOOR) ? NOISE_FLOOR : scaled_threshold[10:0];
    wire [10:0] adaptive_threshold=(bounded_threshold>contrast_limit)
        ? {3'd0,contrast_limit} : bounded_threshold;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            left_sum<=0; right_sum<=0; top_sum<=0; bottom_sum<=0;
            abs_x<=0; abs_y<=0; magnitude<=0; o_edge<=0;
            meta0<=0; meta1<=0; meta2<=0; meta3<=0;
            threshold_product<=0; threshold0<=0; threshold1<=0; threshold2<=0;
            adaptive0<=0;
            roberts_x<=0; roberts_y<=0; roberts0<=0; roberts1<=0;
        end else begin
            left_sum<={2'b0,p00[7:0]}+
                ((i_operator==1) ? {2'b0,p10[7:0]} : {1'b0,p10[7:0],1'b0})+{2'b0,p20[7:0]};
            right_sum<={2'b0,p02[7:0]}+
                ((i_operator==1) ? {2'b0,p12[7:0]} : {1'b0,p12[7:0],1'b0})+{2'b0,p22[7:0]};
            top_sum<={2'b0,p00[7:0]}+
                ((i_operator==1) ? {2'b0,p01[7:0]} : {1'b0,p01[7:0],1'b0})+{2'b0,p02[7:0]};
            bottom_sum<={2'b0,p20[7:0]}+
                ((i_operator==1) ? {2'b0,p21[7:0]} : {1'b0,p21[7:0],1'b0})+{2'b0,p22[7:0]};
            roberts_x<=(p00[7:0]>=p11[7:0]) ? p00[7:0]-p11[7:0] : p11[7:0]-p00[7:0];
            roberts_y<=(p01[7:0]>=p10[7:0]) ? p01[7:0]-p10[7:0] : p10[7:0]-p01[7:0];
            roberts0<=(i_operator==2); roberts1<=roberts0;
            abs_x<=roberts0 ? {2'b0,roberts_x} :
                ((right_sum>=left_sum) ? right_sum-left_sum : left_sum-right_sum);
            abs_y<=roberts0 ? {2'b0,roberts_y} :
                ((bottom_sum>=top_sum) ? bottom_sum-top_sum : top_sum-bottom_sum);
            magnitude<=(normalized>255) ? 11'd255 : normalized;
            threshold_product<=threshold*brightness;
            threshold0<=threshold;
            adaptive0<=adaptive;
            threshold1<=adaptive0 && (threshold0!=0) ? adaptive_threshold : threshold0;
            threshold2<=threshold1;
            o_edge<=meta2[32] && magnitude!=0 && (magnitude>=threshold2) ? 8'hff : 8'h00;
            meta0<={wvs,whs,wde,right_half,valid,p11[39:16],p11[15:8]};
            meta1<=meta0; meta2<=meta1; meta3<=meta2;
        end
    end
    assign {o_vs,o_hs,o_de,o_right_half}=meta3[36:33];
    assign o_gray=meta3[32] ? meta3[7:0] : 8'd0;
    assign o_rgb=meta3[32] ? meta3[31:8] : 24'd0;
endmodule
