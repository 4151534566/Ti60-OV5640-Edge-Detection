`timescale 1ns/1ps
// Count source frame events, rather than the repeated HDMI output frames.
module track4_frame_meter #(
    parameter integer CLOCK_HZ=148500000
) (
    input wire camera_clk,camera_rst_n,camera_vs,
    input wire clk,rst_n,
    output reg [7:0] fps
);
    reg camera_vs_d,frame_toggle;
    always @(posedge camera_clk or negedge camera_rst_n) begin
        if (!camera_rst_n) begin camera_vs_d<=0; frame_toggle<=0; end
        else begin
            camera_vs_d<=camera_vs;
            if (camera_vs && !camera_vs_d) frame_toggle<=~frame_toggle;
        end
    end
    reg [2:0] toggle_sync;
    reg [31:0] seconds_count;
    reg [8:0] frames;
    wire frame_event=toggle_sync[2]^toggle_sync[1];
    wire [9:0] next_frames={1'b0,frames}+frame_event;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin toggle_sync<=0; seconds_count<=0; frames<=0; fps<=0; end
        else begin
            toggle_sync<={toggle_sync[1:0],frame_toggle};
            if (seconds_count==CLOCK_HZ-1) begin
                seconds_count<=0; fps<=(next_frames>255) ? 8'd255 : next_frames[7:0];
                frames<=0;
            end else begin
                seconds_count<=seconds_count+1'b1;
                if (frame_event && frames<511) frames<=frames+1'b1;
            end
        end
    end
endmodule
