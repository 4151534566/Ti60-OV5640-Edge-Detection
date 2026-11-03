`ifndef TRACK4_SHAPE_RECOGNITION_V
`define TRACK4_SHAPE_RECOGNITION_V
`timescale 1ns/1ps
// Frame-level geometric recognizer fed by the aligned Canny edge stream.
// It keeps one bounded target model in registers and publishes it only at VS.
// Class codes: 0 none, 1 line, 2 vertical, 3 horizontal, 4 compact, 5 object.
module track4_shape_recognition #(
    parameter integer WIDTH=1920,
    parameter integer HEIGHT=1080,
    parameter integer MIN_EDGES=32
) (
    input wire clk,rst_n,
    input wire i_vs,i_hs,i_de,
    input wire i_edge,
    output wire o_box,
    output wire o_valid,
    output wire [2:0] o_class,
    output wire [7:0] o_confidence,
    output wire [11:0] o_center_x,o_center_y,
    output wire [11:0] o_min_x,o_max_x,o_min_y,o_max_y,
    output wire [31:0] o_edge_count
);
    reg [11:0] x,y;
    reg [31:0] edge_count;
    reg [11:0] min_x,max_x,min_y,max_y;
    reg seen_edge;
    reg vs_d;
    wire frame_start = i_vs && !vs_d;

    reg published_valid;
    reg [2:0] published_class;
    reg [7:0] published_confidence;
    reg [11:0] published_center_x,published_center_y;
    reg [11:0] published_min_x,published_max_x,published_min_y,published_max_y;
    reg [31:0] published_edge_count;

    wire frame_has_target = seen_edge && (edge_count >= MIN_EDGES) &&
                            (max_x >= min_x) && (max_y >= min_y);
    wire [12:0] box_width = {1'b0,max_x} - {1'b0,min_x} + 13'd1;
    wire [12:0] box_height = {1'b0,max_y} - {1'b0,min_y} + 13'd1;
    wire [25:0] box_area = box_width * box_height;
    wire [33:0] perimeter_est = ({21'd0,box_width} + {21'd0,box_height}) << 1;
    wire [33:0] edge_count_x4 = {2'b0,edge_count} << 2;

    // Geometric classifier.  The confidence is deliberately conservative:
    // sparse outlines and very small targets do not claim a precise shape.
    reg [2:0] frame_class;
    reg [7:0] frame_confidence;
    always @* begin
        frame_class=3'd5;
        frame_confidence=8'd48;
        if (!frame_has_target) begin
            frame_class=3'd0;
            frame_confidence=8'd0;
        end else if ((box_width<=13'd8) || (box_height<=13'd8) ||
                     (edge_count_x4 < perimeter_est)) begin
            frame_class=3'd1;
            frame_confidence=8'd72;
        end else if (box_height > (box_width<<1)) begin
            frame_class=3'd2;
            frame_confidence=8'd80;
        end else if (box_width > (box_height<<1)) begin
            frame_class=3'd3;
            frame_confidence=8'd80;
        end else if ((box_area!=0) && (edge_count_x4 >= box_area)) begin
            frame_class=3'd4;
            frame_confidence=8'd76;
        end else begin
            frame_class=3'd5;
            frame_confidence=8'd56;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x<=0; y<=0; edge_count<=0; vs_d<=0;
            min_x<=0; max_x<=0; min_y<=0; max_y<=0; seen_edge<=0;
            published_valid<=0; published_class<=0; published_confidence<=0;
            published_center_x<=0; published_center_y<=0;
            published_min_x<=0; published_max_x<=0; published_min_y<=0; published_max_y<=0;
            published_edge_count<=0;
        end else begin
            // VS can remain high for multiple clocks. Publish and clear once,
            // on its rising edge, then keep the result for the active frame.
            vs_d<=i_vs;
            if (frame_start) begin
                published_valid<=frame_has_target;
                published_class<=frame_class;
                published_confidence<=frame_confidence;
                published_center_x<=frame_has_target ? ((min_x+max_x)>>1) : 0;
                published_center_y<=frame_has_target ? ((min_y+max_y)>>1) : 0;
                published_min_x<=frame_has_target ? min_x : 0;
                published_max_x<=frame_has_target ? max_x : 0;
                published_min_y<=frame_has_target ? min_y : 0;
                published_max_y<=frame_has_target ? max_y : 0;
                published_edge_count<=frame_has_target ? edge_count : 0;
                x<=0; y<=0; edge_count<=0;
                min_x<=0; max_x<=0; min_y<=0; max_y<=0; seen_edge<=0;
            end else if (i_de) begin
                if (i_edge) begin
                    edge_count<=edge_count+1'b1;
                    if (!seen_edge) begin
                        min_x<=x; max_x<=x; min_y<=y; max_y<=y;
                        seen_edge<=1'b1;
                    end else begin
                        if (x<min_x) min_x<=x;
                        if (x>max_x) max_x<=x;
                        if (y<min_y) min_y<=y;
                        if (y>max_y) max_y<=y;
                    end
                end
                if (x==WIDTH-1) begin
                    x<=0;
                    if (y<HEIGHT-1) y<=y+1'b1;
                end else x<=x+1'b1;
            end
        end
    end

    assign o_valid=published_valid;
    assign o_class=published_class;
    assign o_confidence=published_confidence;
    assign o_center_x=published_center_x;
    assign o_center_y=published_center_y;
    assign o_min_x=published_min_x;
    assign o_max_x=published_max_x;
    assign o_min_y=published_min_y;
    assign o_max_y=published_max_y;
    assign o_edge_count=published_edge_count;
    assign o_box=i_de && published_valid &&
                 ((x==published_min_x || x==published_max_x) && y>=published_min_y && y<=published_max_y ||
                  (y==published_min_y || y==published_max_y) && x>=published_min_x && x<=published_max_x);
endmodule
`endif
