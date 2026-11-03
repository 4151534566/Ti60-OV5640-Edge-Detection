`timescale 1ns/1ps
// T:0024 M:2 A:0 N:1 F:030 O:C E:0. F is camera VS events/s.
module track4_status_overlay #(
    parameter integer WIDTH=1920, HEIGHT=1080, SCALE=4
) (
    input wire clk,rst_n,i_vs,i_de,
    input wire [23:0] i_rgb,
    input wire [10:0] threshold,
    input wire [2:0] mode,
    input wire [1:0] operator_select,edge_style,
    input wire adaptive,median_enabled,
    input wire [7:0] fps,
    output wire [23:0] o_rgb
);
    reg [11:0] x,y;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin x<=0; y<=0; end
        else if (i_vs) begin x<=0; y<=0; end
        else if (i_de) begin
            if (x==WIDTH-1) begin x<=0; y<=y+1'b1; end
            else x<=x+1'b1;
        end
    end
    function [15:0] decimal;
        input [11:0] value;
        reg [15:0] bcd;
        integer i,j;
        begin
            bcd=0;
            for (i=11;i>=0;i=i-1) begin
                for (j=0;j<4;j=j+1)
                    if (bcd[j*4+:4]>=5) bcd[j*4+:4]=bcd[j*4+:4]+4'd3;
                bcd={bcd[14:0],value[i]};
            end
            decimal=bcd;
        end
    endfunction
    reg [15:0] threshold_bcd,fps_bcd;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin threshold_bcd<=0; fps_bcd<=0; end
        else if (i_vs) begin
            threshold_bcd<=decimal({1'b0,threshold});
            fps_bcd<=decimal({4'd0,fps});
        end
    end
    wire inside_box=(x>=24 && x<24+33*6*SCALE && y>=12 && y<12+9*SCALE);
    wire [11:0] text_x=(x-24)/SCALE;
    wire [11:0] text_y=(y-12)/SCALE;
    wire [5:0] char_index=text_x/6;
    wire [2:0] col=text_x%6;
    reg [6:0] character;
    always @* begin
        character=7'd32;
        case (char_index)
            0: character=7'd84;
            1,8,12,16,20,26,30: character=7'd58;
            2: character=7'd48+threshold_bcd[15:12];
            3: character=7'd48+threshold_bcd[11:8];
            4: character=7'd48+threshold_bcd[7:4];
            5: character=7'd48+threshold_bcd[3:0];
            7: character=7'd77;
            9: character=7'd48+mode;
            11: character=7'd65;
            13: character=7'd48+adaptive;
            15: character=7'd78;
            17: character=7'd48+median_enabled;
            19: character=7'd70;
            21: character=7'd48+fps_bcd[11:8];
            22: character=7'd48+fps_bcd[7:4];
            23: character=7'd48+fps_bcd[3:0];
            25: character=7'd79;
            27: character=(operator_select==1) ? 7'd80 : (operator_select==2) ? 7'd82 : 7'd67;
            29: character=7'd69;
            31: character=7'd48+edge_style;
            default: character=7'd32;
        endcase
    end
    function [34:0] glyph;
        input [6:0] c;
        begin
            case (c)
                48: glyph=35'b01110_10001_10011_10101_11001_10001_01110;
                49: glyph=35'b00100_01100_00100_00100_00100_00100_01110;
                50: glyph=35'b01110_10001_00001_00010_00100_01000_11111;
                51: glyph=35'b11110_00001_00001_01110_00001_00001_11110;
                52: glyph=35'b00010_00110_01010_10010_11111_00010_00010;
                53: glyph=35'b11111_10000_10000_11110_00001_00001_11110;
                54: glyph=35'b01110_10000_10000_11110_10001_10001_01110;
                55: glyph=35'b11111_00001_00010_00100_01000_01000_01000;
                56: glyph=35'b01110_10001_10001_01110_10001_10001_01110;
                57: glyph=35'b01110_10001_10001_01111_00001_00001_01110;
                58: glyph=35'b00000_00100_00100_00000_00100_00100_00000;
                65: glyph=35'b01110_10001_10001_11111_10001_10001_10001;
                67: glyph=35'b01111_10000_10000_10000_10000_10000_01111;
                69: glyph=35'b11111_10000_10000_11110_10000_10000_11111;
                70: glyph=35'b11111_10000_10000_11110_10000_10000_10000;
                77: glyph=35'b10001_11011_10101_10101_10001_10001_10001;
                78: glyph=35'b10001_11001_11001_10101_10011_10011_10001;
                79: glyph=35'b01110_10001_10001_10001_10001_10001_01110;
                80: glyph=35'b11110_10001_10001_11110_10000_10000_10000;
                82: glyph=35'b11110_10001_10001_11110_10100_10010_10001;
                83: glyph=35'b01111_10000_10000_01110_00001_00001_11110;
                84: glyph=35'b11111_00100_00100_00100_00100_00100_00100;
                default: glyph=0;
            endcase
        end
    endfunction
    wire [34:0] bitmap=glyph(character);
    wire ink=(text_y>=1 && text_y<=7 && col<5) && bitmap[34-(text_y-1)*5-col];
    assign o_rgb=!i_de ? 24'd0 : inside_box ? (ink ? 24'hffffff : 24'h101010) : i_rgb;
endmodule
