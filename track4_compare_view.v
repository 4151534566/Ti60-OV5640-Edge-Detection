`timescale 1ns/1ps
`ifndef TRACK4_COMPARE_VIEW_V
`define TRACK4_COMPARE_VIEW_V
// Replay one raster line later so both halves show the complete same row.
// Compare: 2:1 horizontal box filter, no vertical reduction or enlargement.
module track4_compare_view #(
    parameter integer WIDTH=1920, HEIGHT=1080, H_BLANK=280
) (
    input wire clk,rst_n,i_vs,i_hs,i_de,
    input wire [23:0] i_rgb,i_live_rgb,
    input wire i_edge,
    input wire [2:0] i_mode,
    output reg o_vs,o_hs,o_de,
    output reg [23:0] o_rgb
);
    localparam integer HALF=WIDTH/2, LINE_CYCLES=WIDTH+H_BLANK;
    localparam integer DELAY_DEPTH=LINE_CYCLES-1, DW=$clog2(DELAY_DEPTH);
    localparam integer TILE=10, PW=WIDTH/TILE, PH=HEIGHT/TILE, DEPTH=PW*PH;
    localparam integer AW=$clog2(DEPTH), XW=$clog2(WIDTH), YW=$clog2(HEIGHT);
    localparam integer PIP_W=PW*2, PIP_H=PH*2;
    localparam integer PIP_X=WIDTH-PIP_W-24, PIP_Y=HEIGHT-PIP_H-24;
    reg [XW-1:0] x,display_x;
    reg [YW-1:0] y,display_y;
    reg [3:0] tile_x,tile_y;
    reg vs_d,frame_started,write_bank,read_bank,complete_frame,preview_valid;
    reg [AW-1:0] write_addr;
    reg horizontal_edge;
    reg [PW-1:0] edge_rows;
    wire tile_row=horizontal_edge | i_edge;
    wire tile_edge=tile_row | ((tile_y==0) ? 1'b0 : edge_rows[PW-1]);
    wire tile_end=i_de && !i_vs && frame_started && (tile_x==TILE-1);
    wire write_en=tile_end && (tile_y==TILE-1) && !complete_frame;
    wire [16:0] write_data={tile_edge,i_rgb[23:19],i_rgb[15:10],i_rgb[7:3]};
    reg [16:0] bank0[0:DEPTH-1],bank1[0:DEPTH-1];
    reg [16:0] read0,read1;

    // The RAM read register plus DELAY_DEPTH cycles equals one complete line.
    // Delay sync and live pixels together, including the final active row.
    reg [31:0] delay_memory[0:DELAY_DEPTH-1];
    reg [DW-1:0] delay_addr;
    reg [DW:0] delay_fill;
    reg [31:0] replay;
    always @(posedge clk) begin
        if (rst_n) begin
            delay_memory[delay_addr]<={preview_valid,i_mode,read_bank,i_vs,i_hs,i_de,i_live_rgb};
            replay<=(delay_fill==DELAY_DEPTH) ? delay_memory[delay_addr] : 32'd0;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin delay_addr<=0; delay_fill<=0; end
        else begin
            delay_addr<=(delay_addr==DELAY_DEPTH-1) ? 0 : delay_addr+1'b1;
            if (delay_fill<DELAY_DEPTH) delay_fill<=delay_fill+1'b1;
        end
    end
    wire replay_valid=rst_n && (delay_fill==DELAY_DEPTH);
    wire replay_vs=replay_valid && replay[26];
    wire replay_hs=replay_valid && replay[25];
    wire replay_de=replay_valid && replay[24];
    wire [2:0] replay_mode=replay[30:28];
    wire compare_mode=(replay_mode==0 || replay_mode==5);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin display_x<=0; display_y<=0; end
        else if (replay_vs) begin display_x<=0; display_y<=0; end
        else if (replay_de) begin
            if (display_x==WIDTH-1) begin display_x<=0; display_y<=display_y+1'b1; end
            else display_x<=display_x+1'b1;
        end
    end

    // Preserve RGB888 and coverage of each two-pixel horizontal footprint.
    reg [25:0] line0[0:HALF-1],line1[0:HALF-1];
    reg [25:0] line_read0,line_read1;
    reg [23:0] first_rgb;
    reg first_edge;
    wire [8:0] pair_r={1'b0,first_rgb[23:16]}+{1'b0,i_rgb[23:16]}+9'd1;
    wire [8:0] pair_g={1'b0,first_rgb[15:8]}+{1'b0,i_rgb[15:8]}+9'd1;
    wire [8:0] pair_b={1'b0,first_rgb[7:0]}+{1'b0,i_rgb[7:0]}+9'd1;
    wire [1:0] coverage={1'b0,first_edge}+{1'b0,i_edge};
    wire [25:0] pair_data={coverage,pair_r[8:1],pair_g[8:1],pair_b[8:1]};
    wire right_view=(display_x>=HALF);
    wire [XW-1:0] pair_addr=right_view ? display_x-HALF : display_x;
    always @(posedge clk) begin
        if (rst_n && i_de && !i_vs) begin
            if (!x[0]) begin first_rgb<=i_rgb; first_edge<=i_edge; end
            else if (y[0]) line1[x>>1]<=pair_data;
            else line0[x>>1]<=pair_data;
        end
        if (rst_n && replay_de && compare_mode) begin
            if (display_y[0]) line_read1<=line1[pair_addr];
            else line_read0<=line0[pair_addr];
        end
    end

    wire in_pip=(replay_mode==3) && display_x>=PIP_X && display_x<PIP_X+PIP_W &&
        display_y>=PIP_Y && display_y<PIP_Y+PIP_H;
    wire pip_border=(replay_mode==3) && display_x>=PIP_X-2 && display_x<PIP_X+PIP_W+2 &&
        display_y>=PIP_Y-2 && display_y<PIP_Y+PIP_H+2 && !in_pip;
    wire [XW-1:0] pip_x=display_x-PIP_X;
    wire [YW-1:0] pip_y=display_y-PIP_Y;
    wire [AW-1:0] read_addr=(pip_y>>1)*PW+(pip_x>>1);
    wire read_en=replay_de && replay[31] && in_pip;
    always @(posedge clk) begin
        if (rst_n && write_en) begin
            if (write_bank) bank1[write_addr]<=write_data;
            else bank0[write_addr]<=write_data;
        end
        if (rst_n && read_en) begin
            if (replay[27]) read1<=bank1[read_addr];
            else read0<=bank0[read_addr];
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x<=0; y<=0; tile_x<=0; tile_y<=0; vs_d<=0; frame_started<=0;
            write_bank<=0; read_bank<=1; complete_frame<=0; preview_valid<=0;
            write_addr<=0; horizontal_edge<=0; edge_rows<=0;
        end else begin
            vs_d<=i_vs;
            if (i_vs) begin
                x<=0; y<=0; tile_x<=0; tile_y<=0; horizontal_edge<=0;
                if (!vs_d) begin
                    frame_started<=1; write_addr<=0; complete_frame<=0;
                    if (complete_frame) begin
                        read_bank<=write_bank; write_bank<=~write_bank; preview_valid<=1;
                    end
                end
            end else if (i_de) begin
                if (x==WIDTH-1) begin
                    x<=0;
                    if (y<HEIGHT-1) y<=y+1'b1;
                    tile_x<=0;
                    tile_y<=(tile_y==TILE-1) ? 0 : tile_y+1'b1;
                end else x<=x+1'b1;
                if (x!=WIDTH-1) tile_x<=(tile_x==TILE-1) ? 0 : tile_x+1'b1;
                if (tile_x==TILE-1) begin
                    horizontal_edge<=0;
                    edge_rows<={edge_rows[PW-2:0],tile_edge};
                end else horizontal_edge<=tile_row;
                if (write_en) begin
                    if (write_addr==DEPTH-1) complete_frame<=1;
                    else write_addr<=write_addr+1'b1;
                end
            end
        end
    end

    reg vs0,hs0,de0,bank_sel0,line_sel0;
    reg [2:0] view0;
    reg [23:0] live0;
    // 0 live, 1 pending PIP, 2 pair color, 3 pair gray, 4 PIP edge,
    // 6 PIP border, 7 pair edge coverage.
    reg [2:0] view;
    always @* begin
        view=0;
        if (compare_mode) view=right_view ? 7 : ((replay_mode==0) ? 3 : 2);
        if (in_pip) view=replay[31] ? 4 : 1;
        if (pip_border) view=6;
    end
    reg [16:0] sample;
    reg [25:0] line_sample;
    reg vs1,hs1,de1;
    reg [2:0] view1;
    reg [23:0] live1;
    wire [7:0] r=line_sample[23:16],g=line_sample[15:8],b=line_sample[7:0];
    wire [15:0] gray_sum=r*16'd77+g*16'd150+b*16'd29+16'd128;
    wire [7:0] gray=gray_sum[15:8];
    wire [7:0] edge_gray=(line_sample[25:24]==2) ? 8'd0 :
        (line_sample[25:24]==1) ? 8'd128 : 8'd255;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vs0<=0; hs0<=0; de0<=0; bank_sel0<=0; line_sel0<=0; live0<=0; view0<=0;
            vs1<=0; hs1<=0; de1<=0; sample<=0; line_sample<=0; live1<=0; view1<=0;
            o_vs<=0; o_hs<=0; o_de<=0; o_rgb<=0;
        end else begin
            vs0<=replay_vs; hs0<=replay_hs; de0<=replay_de; live0<=replay[23:0];
            bank_sel0<=replay[27]; line_sel0<=display_y[0]; view0<=view;
            sample<=bank_sel0 ? read1 : read0;
            line_sample<=line_sel0 ? line_read1 : line_read0;
            vs1<=vs0; hs1<=hs0; de1<=de0; live1<=live0; view1<=view0;
            o_vs<=vs1; o_hs<=hs1; o_de<=de1;
            if (!de1) o_rgb<=0;
            else case (view1)
                1: o_rgb<=24'h101010;
                2: o_rgb<={r,g,b};
                3: o_rgb<={gray,gray,gray};
                4: o_rgb<=sample[16] ? 24'h000000 : 24'hffffff;
                6: o_rgb<=24'h00c8a0;
                7: o_rgb<={edge_gray,edge_gray,edge_gray};
                default: o_rgb<=live1;
            endcase
        end
    end
endmodule
`endif
