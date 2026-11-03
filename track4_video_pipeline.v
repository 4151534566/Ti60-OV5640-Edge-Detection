`include "track4_canny_stream.v"
`include "track4_shape_recognition.v"
`include "track4_edge_cleanup.v"
`include "track4_compare_view.v"
`timescale 1ns/1ps
// Controls commit during VS; RGB and gray follow both window centers.
// 38 algorithm + one raster line + 3 compositor stages. Source (x-8,y-8).
module track4_video_pipeline #(
    parameter integer WIDTH=1920, HEIGHT=1080, H_BLANK=280,
    parameter integer ENABLE_MEDIAN=0, EDGE_THRESHOLD=80, MODE=0,
    parameter integer RUNTIME_CONTROL=0, ADAPTIVE_THRESHOLD=0, SHADOW_LIFT=0, RECOGNITION_ENABLE=0
) (
    input wire clk,rst_n,i_vs,i_hs,i_de,
    input wire [7:0] i_r,i_g,i_b,
    input wire [10:0] i_threshold,
    input wire [2:0] i_mode,
    input wire [1:0] i_operator,i_edge_style,
    input wire i_enable_median,i_adaptive,
    output wire o_vs,o_hs,o_de,
    output wire [7:0] o_r,o_g,o_b,
    output wire [10:0] o_threshold,
    output wire [2:0] o_mode,
    output wire [1:0] o_operator,o_edge_style,
    output wire o_median_enabled,o_adaptive_enabled
);
    reg [10:0] threshold;
    reg [2:0] mode;
    reg [1:0] operator_select,edge_style;
    reg median_enabled,adaptive_enabled;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            threshold<=EDGE_THRESHOLD; mode<=(MODE>5) ? 0 : MODE;
            operator_select<=0; edge_style<=0;
            median_enabled<=ENABLE_MEDIAN!=0;
            adaptive_enabled<=ADAPTIVE_THRESHOLD!=0;
        end else if (i_vs && RUNTIME_CONTROL) begin
            threshold<=(i_threshold>255) ? 11'd255 : i_threshold;
            mode<=(i_mode>5) ? 3'd0 : i_mode;
            operator_select<=(i_operator>2) ? 0 : i_operator;
            edge_style<=(i_edge_style>2) ? 2 : i_edge_style;
            median_enabled<=i_enable_median;
            adaptive_enabled<=i_adaptive;
        end
    end
    assign o_threshold=threshold;
    assign o_mode=mode;
    assign o_operator=operator_select;
    assign o_edge_style=edge_style;
    assign o_median_enabled=median_enabled;
    assign o_adaptive_enabled=adaptive_enabled;

    function [7:0] lift;
        input [7:0] value;
        reg [9:0] expanded;
        begin
            if (!SHADOW_LIFT) expanded={2'b0,value};
            else if (value<64) expanded={2'b0,value}+{3'b0,value[7:1]};
            else if (value<128) expanded={2'b0,value}+10'd32;
            else expanded=({2'b0,value}+{1'b0,value,1'b0}+10'd255)>>2;
            lift=expanded[7:0];
        end
    endfunction

    wire mvs,mhs,mde,half,svs,shs,sde,cvs,chs,cde;
    wire [7:0] original,filtered,gray,bold_edge,clean_edge,sgray,sedge,raw_edge;
    wire [7:0] edge_pixel=(edge_style==0) ? raw_edge :
        (edge_style==1) ? clean_edge : bold_edge;
    wire [23:0] median_rgb,aligned_rgb,srgb;
    track4_gray_median #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.ENABLE_MEDIAN(ENABLE_MEDIAN),
        .RUNTIME_CONTROL(1)) median (
        .clk(clk),.rst_n(rst_n),.i_vs(i_vs),.i_hs(i_hs),.i_de(i_de),
        .i_r(lift(i_r)),.i_g(lift(i_g)),.i_b(lift(i_b)),
        .i_enable_median(median_enabled),.o_vs(mvs),.o_hs(mhs),.o_de(mde),
        .o_gray(original),.o_filtered(filtered),.o_rgb(median_rgb)
    );
    track4_canny_stream #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.EDGE_THRESHOLD(EDGE_THRESHOLD),
        .RUNTIME_CONTROL(1)) canny (
        .clk(clk),.rst_n(rst_n),.i_vs(mvs),.i_hs(mhs),.i_de(mde),
        .i_gray(filtered),.i_original(original),.i_rgb(median_rgb),
        .i_threshold(threshold),.i_adaptive(adaptive_enabled),.i_operator(operator_select),
        .o_vs(svs),.o_hs(shs),.o_de(sde),
        .o_gray(sgray),.o_edge(sedge),.o_right_half(),.o_rgb(srgb)
    );
    track4_edge_cleanup #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.BORDER(14)) cleanup (
        .clk(clk),.rst_n(rst_n),.i_vs(svs),.i_hs(shs),.i_de(sde),
        .i_gray(sgray),.i_edge(sedge),.i_rgb(srgb),
        .o_vs(cvs),.o_hs(chs),.o_de(cde),.o_right_half(half),
        .o_gray(gray),.o_edge(bold_edge),.o_raw_edge(raw_edge),
        .o_clean_edge(clean_edge),.o_rgb(aligned_rgb)
    );
    wire recognition_box,recognition_valid;
    wire [2:0] recognition_class;
    wire [7:0] recognition_confidence;
    wire [11:0] recognition_center_x,recognition_center_y;
    wire [11:0] recognition_min_x,recognition_max_x,recognition_min_y,recognition_max_y;
    wire [31:0] recognition_edge_count;
    track4_shape_recognition #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.MIN_EDGES(32)) recognizer (
        .clk(clk),.rst_n(rst_n),.i_vs(cvs),.i_hs(chs),.i_de(cde),
        .i_edge(edge_pixel[0]),.o_box(recognition_box),.o_valid(recognition_valid),
        .o_class(recognition_class),.o_confidence(recognition_confidence),
        .o_center_x(recognition_center_x),.o_center_y(recognition_center_y),
        .o_min_x(recognition_min_x),.o_max_x(recognition_max_x),
        .o_min_y(recognition_min_y),.o_max_y(recognition_max_y),
        .o_edge_count(recognition_edge_count)
    );
    wire recognition_overlay = RECOGNITION_ENABLE && (mode==3) && recognition_box;
    reg [23:0] recognition_color;
    always @* begin
        case (recognition_class)
            3'd1: recognition_color=24'h00d0ff;
            3'd2: recognition_color=24'h00ff80;
            3'd3: recognition_color=24'hffe000;
            3'd4: recognition_color=24'hff40c0;
            default: recognition_color=24'h40a0ff;
        endcase
    end
    reg [23:0] color;
    always @* begin
        case (mode)
            1: color={gray,gray,gray};
            2: color={~edge_pixel,~edge_pixel,~edge_pixel};
            3: color=recognition_overlay ? recognition_color : (edge_pixel[0] ? 24'hff0000 : aligned_rgb);
            4: color=aligned_rgb;
            5: color=half ? {~edge_pixel,~edge_pixel,~edge_pixel} : aligned_rgb;
            default: color=half ? {~raw_edge,~raw_edge,~raw_edge} : {gray,gray,gray};
        endcase
    end
    track4_compare_view #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.H_BLANK(H_BLANK)) compare_view (
        .clk(clk),.rst_n(rst_n),.i_vs(cvs),.i_hs(chs),.i_de(cde),
        .i_rgb(aligned_rgb),.i_live_rgb(color),.i_edge(edge_pixel[0]),
        .i_mode(mode),.o_vs(o_vs),.o_hs(o_hs),.o_de(o_de),.o_rgb({o_r,o_g,o_b})
    );
endmodule
