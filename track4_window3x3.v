`timescale 1ns/1ps
// Causal 3x3 window, one pixel/clock. WIDTH >= 3; active-high VS.
// Synchronous RAMs, two register stages for pixels and all sync signals.
// The first BORDER rows/columns are masked; RAM does not need resetting.
module track4_window3x3 #(
    parameter integer WIDTH=1920, HEIGHT=1080, BITS=8, BORDER=2
) (
    input wire clk,rst_n,i_vs,i_hs,i_de,
    input wire [BITS-1:0] i_pixel,
    output reg o_vs,o_hs,o_de,o_valid,o_right_half,
    output reg [BITS-1:0] p00,p01,p02,p10,p11,p12,p20,p21,p22
);
    localparam XW=$clog2(WIDTH), YW=$clog2(HEIGHT);
    reg [BITS-1:0] line1[0:WIDTH-1],line2[0:WIDTH-1];
    reg [BITS-1:0] rd1,rd2,pixel_d,t0,t1,m0,m1,b0,b1;
    reg [XW-1:0] x,x_d;
    reg [YW-1:0] y,y_d;
    reg vs_d,hs_d,de_d;
    // Read first; second row write follows the read by one cycle.
    always @(posedge clk) begin
        if (rst_n && i_de && !i_vs) begin
            rd1<=line1[x]; rd2<=line2[x]; line1[x]<=i_pixel;
        end
        if (rst_n && de_d && !vs_d) line2[x_d]<=rd1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x<=0; y<=0; x_d<=0; y_d<=0;
            vs_d<=0; hs_d<=0; de_d<=0; pixel_d<=0;
            o_vs<=0; o_hs<=0; o_de<=0; o_valid<=0; o_right_half<=0;
            t0<=0; t1<=0; m0<=0; m1<=0; b0<=0; b1<=0;
            p00<=0; p01<=0; p02<=0; p10<=0; p11<=0; p12<=0;
            p20<=0; p21<=0; p22<=0;
        end else begin
            vs_d<=i_vs; hs_d<=i_hs; de_d<=i_de;
            pixel_d<=i_pixel; x_d<=x; y_d<=y;
            if (i_vs) begin x<=0; y<=0; end
            else if (i_de) begin
                if (x==WIDTH-1) begin
                    x<=0;
                    if (y!=HEIGHT-1) y<=y+1'b1;
                end else x<=x+1'b1;
            end
            o_vs<=vs_d; o_hs<=hs_d; o_de<=de_d;
            o_valid<=de_d && !vs_d && (x_d>=BORDER) && (y_d>=BORDER);
            o_right_half<=(x_d>=WIDTH/2);
            if (de_d && !vs_d) begin
                p00<=t0; p01<=t1; p02<=rd2;
                p10<=m0; p11<=m1; p12<=rd1;
                p20<=b0; p21<=b1; p22<=pixel_d;
                t0<=t1; t1<=rd2; m0<=m1; m1<=rd1; b0<=b1; b1<=pixel_d;
            end
        end
    end
endmodule
