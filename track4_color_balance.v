`timescale 1ns/1ps
// Frame-latched chroma balance, black-level removal and a common exposure gain.
// Three clocks on RGB and sync. No changes to the sensor exposure registers.
module track4_color_balance #(
    parameter integer WIDTH=1920, HEIGHT=1080,
    parameter integer BLACK_LEVEL=14, EXPOSURE_GAIN=384,
    parameter GAMMA_FILE="rtl/track4_srgb.mem"
) (
    input wire clk,rst_n,i_vs,i_hs,i_de,
    input wire i_recalibrate,
    input wire [23:0] i_rgb,
    output reg o_vs,o_hs,o_de,
    output reg [23:0] o_rgb
);
    reg [9:0] gain_r,gain_g,gain_b;
    reg [17:0] product_r,product_g,product_b;
    reg [23:0] linear_rgb;
    reg [2:0] sync0,sync1;
    reg [7:0] gamma_lut[0:255];
    initial $readmemh(GAMMA_FILE,gamma_lut);
    function [7:0] saturate;
        input [17:0] product;
        reg [33:0] exposed;
        begin
            exposed=product*EXPOSURE_GAIN;
            saturate=(|exposed[33:24]) ? 8'd255 : exposed[23:16];
        end
    endfunction
    function [7:0] remove_black;
        input [7:0] pixel;
        begin remove_black=(pixel>BLACK_LEVEL) ? pixel-BLACK_LEVEL : 0; end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_r<=0; product_g<=0; product_b<=0;
            linear_rgb<=0; sync0<=0; sync1<=0;
            o_vs<=0; o_hs<=0; o_de<=0; o_rgb<=0;
        end else begin
            product_r<=remove_black(i_rgb[23:16])*gain_r+18'd128;
            product_g<=remove_black(i_rgb[15:8])*gain_g+18'd128;
            product_b<=remove_black(i_rgb[7:0])*gain_b+18'd128;
            linear_rgb<={saturate(product_r),saturate(product_g),saturate(product_b)};
            sync0<={i_vs,i_hs,i_de}; sync1<=sync0;
            {o_vs,o_hs,o_de}<=sync1;
            o_rgb<=sync1[0] ? {gamma_lut[linear_rgb[23:16]],
                gamma_lut[linear_rgb[15:8]],gamma_lut[linear_rgb[7:0]]} : 24'd0;
        end
    end
    wire [7:0] r=linear_rgb[23:16],g=linear_rgb[15:8],b=linear_rgb[7:0];
    wire [7:0] hi=(r>g) ? ((r>b) ? r : b) : ((g>b) ? g : b);
    wire [7:0] lo=(r<g) ? ((r<b) ? r : b) : ((g<b) ? g : b);
    localparam XW=$clog2(WIDTH), YW=$clog2(HEIGHT);
    reg [XW-1:0] x;
    reg [YW-1:0] y;
    reg vs_d,started,complete;
    reg [31:0] sum_r,sum_g,sum_b,samples;
    // Only near-neutral pixels may steer chroma. Never normalize a colored scene.
    wire neutral=hi>=32 && hi<240 && lo>=16 && (hi-lo)<=(hi>>2);
    wire sample_pixel=sync1[0] && !sync1[2] && started && !complete &&
        x>=16 && y>=16 && x[3:0]==0 && y[3:0]==0 && neutral;
    // Keep green at unity and match R/B to green, preserving scene brightness.
    wire [31:0] low_target=sum_g-(sum_g>>5),high_target=sum_g+(sum_g>>5);
    function [9:0] adjust;
        input [9:0] gain;
        input [31:0] total;
        begin
            if (total<low_target && gain<512) adjust=gain+10'd4;
            else if (total>high_target && gain>192) adjust=gain-10'd4;
            else adjust=gain;
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gain_r<=256; gain_g<=256; gain_b<=256;
            x<=0; y<=0; vs_d<=0; started<=0; complete<=0;
            sum_r<=0; sum_g<=0; sum_b<=0; samples<=0;
        end else if (i_recalibrate) begin
            gain_r<=256; gain_g<=256; gain_b<=256;
            x<=0; y<=0; vs_d<=0; started<=0; complete<=0;
            sum_r<=0; sum_g<=0; sum_b<=0; samples<=0;
        end else begin
            vs_d<=sync1[2];
            if (sync1[2]) begin
                x<=0; y<=0;
                if (!vs_d) begin
                    if (complete && samples>=16) begin
                        gain_r<=adjust(gain_r,sum_r);
                        gain_b<=adjust(gain_b,sum_b);
                    end
                    started<=1; complete<=0;
                    sum_r<=0; sum_g<=0; sum_b<=0; samples<=0;
                end
            end else if (sync1[0] && started && !complete) begin
                if (x==WIDTH-1) begin
                    x<=0;
                    if (y==HEIGHT-1) complete<=1;
                    else y<=y+1'b1;
                end else x<=x+1'b1;
                if (sample_pixel) begin
                    sum_r<=sum_r+r; sum_g<=sum_g+g; sum_b<=sum_b+b;
                    samples<=samples+1'b1;
                end
            end
        end
    end
endmodule
