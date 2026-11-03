`timescale 1ns/1ps
module track4_controls #(
    parameter integer CLOCK_HZ=148500000, DEBOUNCE_MS=10,
    parameter integer LONG_PRESS_MS=700, REPEAT_DELAY_MS=450, REPEAT_MS=160,
    parameter integer MAX_REPEAT_MS=3000,
    parameter integer DEFAULT_THRESHOLD=8, DEFAULT_MODE=2,
    parameter integer DEFAULT_MEDIAN=0, DEFAULT_ADAPTIVE=1
) (
    input wire clk,rst_n,
    // KEY1 minus, KEY2 plus, KEY3 mode; all active low.
    input wire [2:0] key_n,
    output reg [10:0] threshold,
    output reg [2:0] mode,
    output reg median_enabled,adaptive_enabled,
    output reg [1:0] operator_select,edge_style
);
    localparam integer DB=(CLOCK_HZ/1000*DEBOUNCE_MS<1) ? 1 : CLOCK_HZ/1000*DEBOUNCE_MS;
    localparam integer LONG=(CLOCK_HZ/1000*LONG_PRESS_MS<1) ? 1 : CLOCK_HZ/1000*LONG_PRESS_MS;
    localparam integer DELAY=(CLOCK_HZ/1000*REPEAT_DELAY_MS<1) ? 1 : CLOCK_HZ/1000*REPEAT_DELAY_MS;
    localparam integer REPEAT=(CLOCK_HZ/1000*REPEAT_MS<1) ? 1 : CLOCK_HZ/1000*REPEAT_MS;
    localparam integer MAX_HOLD=(CLOCK_HZ/1000*MAX_REPEAT_MS<1) ? 1 : CLOCK_HZ/1000*MAX_REPEAT_MS;
    reg [2:0] sync0,sync1,stable_n,stable_d;
    wire [2:0] press=stable_d & ~stable_n;
    wire [2:0] release_key=~stable_d & stable_n;
    reg [2:0] repeat_pulse,long_pulse;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin sync0<=3'b111; sync1<=3'b111; stable_d<=3'b111; end
        else begin sync0<=key_n; sync1<=sync0; stable_d<=stable_n; end
    end
    genvar k;
    generate for (k=0;k<3;k=k+1) begin: button
        reg [31:0] debounce_count,hold_count,repeat_count;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                stable_n[k]<=1'b1; debounce_count<=0;
                hold_count<=0; repeat_count<=0;
                repeat_pulse[k]<=0; long_pulse[k]<=0;
            end else begin
                if (sync1[k]==stable_n[k]) debounce_count<=0;
                else if (debounce_count==DB-1) begin
                    stable_n[k]<=sync1[k]; debounce_count<=0;
                end else debounce_count<=debounce_count+1'b1;
                repeat_pulse[k]<=0; long_pulse[k]<=0;
                if (stable_n[k]) begin hold_count<=0; repeat_count<=0; end
                else begin
                    if (hold_count<MAX_HOLD || hold_count<LONG || hold_count<DELAY) hold_count<=hold_count+1'b1;
                    if (hold_count==LONG-1) long_pulse[k]<=1;
                    if (hold_count>=DELAY && hold_count<MAX_HOLD) begin
                        if (repeat_count==REPEAT-1) begin
                            repeat_count<=0; repeat_pulse[k]<=1;
                        end else repeat_count<=repeat_count+1'b1;
                    end
                end
            end
        end
    end endgenerate
    // Short single-key actions happen on release. A chord consumes all its
    // releases until every key is up, preventing accidental mode/T changes.
    wire chord=(stable_n==3'b100 || stable_n==3'b010 ||
                stable_n==3'b001 || stable_n==3'b000);
    reg combo_used,mode_long;
    reg [1:0] repeated;
    function [10:0] lower_threshold;
        input [10:0] value;
        begin
            if (value>128) lower_threshold=128;
            else if (value>64) lower_threshold=64;
            else if (value>32) lower_threshold=32;
            else if (value>24) lower_threshold=24;
            else if (value>16) lower_threshold=16;
            else if (value>8) lower_threshold=8;
            else if (value>4) lower_threshold=4;
            else if (value>2) lower_threshold=2;
            else lower_threshold=1;
        end
    endfunction
    function [10:0] higher_threshold;
        input [10:0] value;
        begin
            if (value<2) higher_threshold=2;
            else if (value<4) higher_threshold=4;
            else if (value<8) higher_threshold=8;
            else if (value<16) higher_threshold=16;
            else if (value<24) higher_threshold=24;
            else if (value<32) higher_threshold=32;
            else if (value<64) higher_threshold=64;
            else if (value<128) higher_threshold=128;
            else higher_threshold=255;
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            threshold<=DEFAULT_THRESHOLD; mode<=DEFAULT_MODE;
            median_enabled<=DEFAULT_MEDIAN!=0; adaptive_enabled<=DEFAULT_ADAPTIVE!=0;
            combo_used<=0; mode_long<=0; repeated<=0;
            operator_select<=0; edge_style<=0;
        end else begin
            if (stable_n==3'b111) combo_used<=0;
            if (press[0]) repeated[0]<=0;
            if (press[1]) repeated[1]<=0;
            if (press[2]) mode_long<=0;
            if (chord && !combo_used) begin
                combo_used<=1;
                case (stable_n)
                    3'b100: median_enabled<=~median_enabled; // KEY1+2
                    3'b010: edge_style<=(edge_style==2) ? 0 : edge_style+1'b1; // KEY1+3
                    3'b001: operator_select<=(operator_select==2) ? 0 : operator_select+1'b1; // KEY2+3
                    default: begin end
                endcase
            end else if (!combo_used && !chord) begin
                if (repeat_pulse[0] && stable_n==3'b110) begin
                    threshold<=lower_threshold(threshold); repeated[0]<=1;
                end else if (release_key[0] && !repeated[0] && stable_d==3'b110)
                    threshold<=lower_threshold(threshold);
                if (repeat_pulse[1] && stable_n==3'b101) begin
                    threshold<=higher_threshold(threshold); repeated[1]<=1;
                end else if (release_key[1] && !repeated[1] && stable_d==3'b101)
                    threshold<=higher_threshold(threshold);
                if (long_pulse[2] && stable_n==3'b011) begin
                    adaptive_enabled<=~adaptive_enabled; mode_long<=1;
                end
                if (release_key[2] && stable_d==3'b011 && !mode_long && !long_pulse[2])
                    mode<=(mode>=5) ? 3'd0 : mode+1'b1;
            end
        end
    end
endmodule
