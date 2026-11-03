`timescale 1ns/1ps
`ifndef TRACK4_EDGE_CLEANUP_V
`define TRACK4_EDGE_CLEANUP_V
// Remove isolated edge pixels, then dilate 3x3 for a downscaled display.
// RGB/gray/raw edges travel through the same two window centers (six clocks).
module track4_edge_cleanup #(
    parameter integer WIDTH=1920, HEIGHT=1080, BORDER=6
) (
    input wire clk,rst_n,i_vs,i_hs,i_de,
    input wire [7:0] i_edge,i_gray,
    input wire [23:0] i_rgb,
    output reg o_vs,o_hs,o_de,o_right_half,
    output reg [7:0] o_edge,o_raw_edge,o_clean_edge,o_gray,
    output reg [23:0] o_rgb
);
    wire avs,ahs,ade,avalid;
    wire [32:0] a00,a01,a02,a10,a11,a12,a20,a21,a22;
    track4_window3x3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.BITS(33),.BORDER(BORDER)) neighbors (
        .clk(clk),.rst_n(rst_n),.i_vs(i_vs),.i_hs(i_hs),.i_de(i_de),
        .i_pixel({i_edge[0],i_gray,i_rgb}),.o_vs(avs),.o_hs(ahs),.o_de(ade),
        .o_valid(avalid),.o_right_half(),
        .p00(a00),.p01(a01),.p02(a02),.p10(a10),.p11(a11),.p12(a12),
        .p20(a20),.p21(a21),.p22(a22)
    );
    wire [3:0] top_count={3'd0,a00[32]}+{3'd0,a01[32]}+{3'd0,a02[32]};
    wire [3:0] mid_count={3'd0,a10[32]}+{3'd0,a11[32]}+{3'd0,a12[32]};
    wire [3:0] bot_count={3'd0,a20[32]}+{3'd0,a21[32]}+{3'd0,a22[32]};
    wire [3:0] count=top_count+mid_count+bot_count;
    reg cvs,chs,cde;
    reg [33:0] cleaned;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin cvs<=0; chs<=0; cde<=0; cleaned<=0; end
        else begin
            cvs<=avs; chs<=ahs; cde<=ade;
            cleaned<=avalid ? {a11[32] && (count>=2),a11} : 34'd0;
        end
    end
    wire bvs,bhs,bde,bvalid,bhalf;
    wire [33:0] b00,b01,b02,b10,b11,b12,b20,b21,b22;
    track4_window3x3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.BITS(34),.BORDER(BORDER+2)) dilation (
        .clk(clk),.rst_n(rst_n),.i_vs(cvs),.i_hs(chs),.i_de(cde),
        .i_pixel(cleaned),.o_vs(bvs),.o_hs(bhs),.o_de(bde),
        .o_valid(bvalid),.o_right_half(bhalf),
        .p00(b00),.p01(b01),.p02(b02),.p10(b10),.p11(b11),.p12(b12),
        .p20(b20),.p21(b21),.p22(b22)
    );
    wire bold=b00[33]|b01[33]|b02[33]|b10[33]|b11[33]|b12[33]|b20[33]|b21[33]|b22[33];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_vs<=0; o_hs<=0; o_de<=0; o_right_half<=0;
            o_edge<=0; o_raw_edge<=0; o_clean_edge<=0; o_gray<=0; o_rgb<=0;
        end else begin
            o_vs<=bvs; o_hs<=bhs; o_de<=bde; o_right_half<=bhalf;
            o_edge<=bvalid && bold ? 8'hff : 8'd0;
            o_raw_edge<=bvalid && b11[32] ? 8'hff : 8'd0;
            o_clean_edge<=bvalid && b11[33] ? 8'hff : 8'd0;
            o_gray<=bvalid ? b11[31:24] : 8'd0;
            o_rgb<=bvalid ? b11[23:0] : 24'd0;
        end
    end
endmodule
`endif
