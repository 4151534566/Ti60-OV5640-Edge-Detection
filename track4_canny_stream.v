`ifndef TRACK4_CANNY_STREAM_V
`define TRACK4_CANNY_STREAM_V
`timescale 1ns/1ps
// Streaming Canny, one pixel per clock. No DDR transactions or frame buffer.
// 3x3 Gaussian -> gradient/direction -> NMS -> dual thresholds -> two
// synchronous 8-neighbour propagation passes. Weak chains beyond two links
// from a strong seed are intentionally NOT full-frame hysteresis.
// Latency 19 clocks; five window centers. Input already has median border 2.
module track4_canny_stream #(
    parameter integer WIDTH=1920, HEIGHT=1080, EDGE_THRESHOLD=8,
    parameter integer RUNTIME_CONTROL=0, ADAPTIVE_THRESHOLD=0
) (
    input wire clk,rst_n,i_vs,i_hs,i_de,
    input wire [7:0] i_gray,i_original,
    input wire [23:0] i_rgb,
    input wire [10:0] i_threshold,
    input wire i_adaptive,
    input wire [1:0] i_operator,
    output wire o_vs,o_hs,o_de,
    output wire [7:0] o_gray,o_edge,
    output wire o_right_half,
    output wire [23:0] o_rgb
);
    // Operator 0 is Canny. 1/2 retain Prewitt/Roberts threshold views,
    // transported through the same window centers and timing as Canny.
    wire canny=(i_operator==0);
    wire avs,ahs,ade,av;
    wire [39:0] a00,a01,a02,a10,a11,a12,a20,a21,a22;
    track4_window3x3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.BITS(40),.BORDER(4)) gaussian_window (
        .clk(clk),.rst_n(rst_n),.i_vs(i_vs),.i_hs(i_hs),.i_de(i_de),
        .i_pixel({i_rgb,i_original,i_gray}),.o_vs(avs),.o_hs(ahs),.o_de(ade),
        .o_valid(av),.o_right_half(),
        .p00(a00),.p01(a01),.p02(a02),.p10(a10),.p11(a11),.p12(a12),
        .p20(a20),.p21(a21),.p22(a22)
    );
    reg [9:0] ga,gb,gc;
    reg [7:0] gaussian,center0;
    reg [35:0] gm0,gm1;
    wire [11:0] gaussian_sum={2'd0,ga}+{1'd0,gb,1'b0}+{2'd0,gc}+12'd8;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin ga<=0;gb<=0;gc<=0;gaussian<=0;center0<=0;gm0<=0;gm1<=0; end
        else begin
            ga<={2'd0,a00[7:0]}+{1'd0,a01[7:0],1'b0}+{2'd0,a02[7:0]};
            gb<={2'd0,a10[7:0]}+{1'd0,a11[7:0],1'b0}+{2'd0,a12[7:0]};
            gc<={2'd0,a20[7:0]}+{1'd0,a21[7:0],1'b0}+{2'd0,a22[7:0]};
            center0<=a11[7:0];
            gaussian<=gm0[32] ? (canny ? gaussian_sum[11:4] : center0) : 8'd0;
            gm0<={avs,ahs,ade,av,a11[39:8]}; gm1<=gm0;
        end
    end

    wire bvs,bhs,bde,bv;
    wire [39:0] b00,b01,b02,b10,b11,b12,b20,b21,b22;
    track4_window3x3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.BITS(40),.BORDER(6)) gradient_window (
        .clk(clk),.rst_n(rst_n),.i_vs(gm1[35]),.i_hs(gm1[34]),.i_de(gm1[33]),
        .i_pixel({gm1[32] ? gm1[31:0] : 32'd0,gaussian}),
        .o_vs(bvs),.o_hs(bhs),.o_de(bde),.o_valid(bv),.o_right_half(),
        .p00(b00),.p01(b01),.p02(b02),.p10(b10),.p11(b11),.p12(b12),
        .p20(b20),.p21(b21),.p22(b22)
    );
    reg [9:0] ls,rs,ts,bs,ax,ay;
    reg [7:0] rx,ry,mag;
    reg rob0,rob1,sx,sy;
    reg [1:0] direction;
    reg [35:0] bm0,bm1,bm2;
    wire [10:0] mag_sum={1'b0,ax}+{1'b0,ay};
    wire [10:0] norm=rob1 ? mag_sum>>1 : mag_sum>>2;
    // tan(22.5 degrees) ~= 106/256. All comparisons are unsigned.
    wire [17:0] xtan=ax*18'd106, ytan=ay*18'd106;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ls<=0;rs<=0;ts<=0;bs<=0;ax<=0;ay<=0;rx<=0;ry<=0;mag<=0;
            rob0<=0;rob1<=0;sx<=0;sy<=0;direction<=0;bm0<=0;bm1<=0;bm2<=0;
        end else begin
            ls<={2'd0,b00[7:0]}+((i_operator==1)?{2'd0,b10[7:0]}:{1'd0,b10[7:0],1'b0})+{2'd0,b20[7:0]};
            rs<={2'd0,b02[7:0]}+((i_operator==1)?{2'd0,b12[7:0]}:{1'd0,b12[7:0],1'b0})+{2'd0,b22[7:0]};
            ts<={2'd0,b00[7:0]}+((i_operator==1)?{2'd0,b01[7:0]}:{1'd0,b01[7:0],1'b0})+{2'd0,b02[7:0]};
            bs<={2'd0,b20[7:0]}+((i_operator==1)?{2'd0,b21[7:0]}:{1'd0,b21[7:0],1'b0})+{2'd0,b22[7:0]};
            rx<=(b00[7:0]>=b11[7:0])?b00[7:0]-b11[7:0]:b11[7:0]-b00[7:0];
            ry<=(b01[7:0]>=b10[7:0])?b01[7:0]-b10[7:0]:b10[7:0]-b01[7:0];
            rob0<=(i_operator==2);rob1<=rob0;
            ax<=rob0 ? {2'd0,rx} : ((rs>=ls)?rs-ls:ls-rs);
            ay<=rob0 ? {2'd0,ry} : ((bs>=ts)?bs-ts:ts-bs);
            sx<=(rs<ls);sy<=(bs<ts);
            mag<=bm1[32] ? ((norm>255)?8'd255:norm[7:0]) : 8'd0;
            direction<=({ay,8'd0}<=xtan) ? 2'd0 :
                       ({ax,8'd0}<=ytan) ? 2'd2 : ((sx==sy)?2'd1:2'd3);
            bm0<={bvs,bhs,bde,bv,b11[39:8]};bm1<=bm0;bm2<=bm1;
        end
    end

    wire cvs,chs,cde,cv;
    wire [41:0] c00,c01,c02,c10,c11,c12,c20,c21,c22;
    track4_window3x3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.BITS(42),.BORDER(8)) nms_window (
        .clk(clk),.rst_n(rst_n),.i_vs(bm2[35]),.i_hs(bm2[34]),.i_de(bm2[33]),
        .i_pixel({direction,mag,bm2[32] ? bm2[31:0] : 32'd0}),
        .o_vs(cvs),.o_hs(chs),.o_de(cde),.o_valid(cv),.o_right_half(),
        .p00(c00),.p01(c01),.p02(c02),.p10(c10),.p11(c11),.p12(c12),
        .p20(c20),.p21(c21),.p22(c22)
    );
    reg [7:0] before_mag,after_mag;
    always @* begin
        case(c11[41:40])
            0: begin before_mag=c10[39:32];after_mag=c12[39:32];end
            1: begin before_mag=c00[39:32];after_mag=c22[39:32];end
            2: begin before_mag=c01[39:32];after_mag=c21[39:32];end
            default: begin before_mag=c02[39:32];after_mag=c20[39:32];end
        endcase
    end
    wire [10:0] requested=RUNTIME_CONTROL ? i_threshold : EDGE_THRESHOLD;
    wire [7:0] high_setting=(requested>255)?8'd255:((requested==0)?8'd1:requested[7:0]);
    wire adaptive=RUNTIME_CONTROL ? i_adaptive : (ADAPTIVE_THRESHOLD!=0);
    reg [16:0] threshold_product;
    reg [7:0] nms_mag,high0;
    reg adaptive0;
    reg [35:0] cm0;
    reg [36:0] classified;
    wire [8:0] scaled=threshold_product[16:8];
    wire [7:0] half_high=(high0>>1)+{7'd0,high0[0]};
    // Bounded brightness adaptation never falls below half the selected T.
    // No previous-frame peak feedback: flat/noisy frames cannot collapse T.
    wire [7:0] high_local=adaptive0 ? ((scaled<half_high)?half_high:
                                  (scaled>high0)?high0:scaled[7:0]) : high0;
    wire [7:0] low_local=(high_local>>1)+{7'd0,high_local[0]};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            threshold_product<=0;nms_mag<=0;high0<=1;adaptive0<=0;cm0<=0;classified<=0;
        end else begin
            // Asymmetric tie break suppresses the double edge of a plateau.
            nms_mag<=cv && (!canny || (c11[39:32]>before_mag && c11[39:32]>=after_mag))
                ? c11[39:32] : 8'd0;
            threshold_product<=high_setting*({1'b0,c11[7:0]}+9'd128);
            high0<=high_setting;adaptive0<=adaptive;
            cm0<={cvs,chs,cde,cv,c11[31:0]};
            classified<={cm0[35:33],
                cm0[32] && nms_mag!=0 && nms_mag>=(canny?low_local:high_local),
                cm0[32] && nms_mag!=0 && nms_mag>=high_local,
                cm0[32]?cm0[31:0]:32'd0};
        end
    end

    wire [36:0] link[0:2];
    assign link[0]=classified;
    genvar pass;
    generate for(pass=0;pass<2;pass=pass+1) begin: hysteresis
        wire vs,hs,de,valid;
        wire [33:0] p00,p01,p02,p10,p11,p12,p20,p21,p22;
        track4_window3x3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.BITS(34),.BORDER(10+2*pass)) window (
            .clk(clk),.rst_n(rst_n),.i_vs(link[pass][36]),.i_hs(link[pass][35]),.i_de(link[pass][34]),
            .i_pixel(link[pass][33:0]),.o_vs(vs),.o_hs(hs),.o_de(de),
            .o_valid(valid),.o_right_half(),
            .p00(p00),.p01(p01),.p02(p02),.p10(p10),.p11(p11),.p12(p12),
            .p20(p20),.p21(p21),.p22(p22)
        );
        wire seed=p00[32]|p01[32]|p02[32]|p10[32]|p11[32]|p12[32]|p20[32]|p21[32]|p22[32];
        reg [36:0] result;
        always @(posedge clk or negedge rst_n)
            if (!rst_n) result<=0;
            else result<={vs,hs,de,valid && p11[33],
                valid && (p11[32] || (canny && p11[33] && seed)),
                valid?p11[31:0]:32'd0};
        assign link[pass+1]=result;
    end endgenerate
    assign {o_vs,o_hs,o_de}=link[2][36:34];
    assign o_edge=link[2][32]?8'hff:8'd0;
    // Packet metadata throughout is {RGB, original gray}.
    assign o_gray=link[2][7:0];
    assign o_rgb=link[2][31:8];
    assign o_right_half=1'b0; // Downstream compositor determines screen halves.
endmodule
`endif
