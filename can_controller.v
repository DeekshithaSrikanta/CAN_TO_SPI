`timescale 1ns / 1ps

module can_controller (
    input  wire        clk_50mhz,
    input  wire        rst_n,
    input  wire        rxd,
    
    output reg         frame_valid,
    output reg  [10:0] id,
    output reg  [3:0]  dlc,
    output wire [63:0] data,
    output reg         frame_error
);

    // -------------------------------------------------------------------------
    // State Machine Parameters (Moved to top for global scope visibility)
    // -------------------------------------------------------------------------
    localparam ST_IDLE      = 4'd0;
    localparam ST_ID        = 4'd1;
    localparam ST_RTR       = 4'd2;
    localparam ST_IDE       = 4'd3;
    localparam ST_R0        = 4'd4;
    localparam ST_DLC       = 4'd5;
    localparam ST_DATA      = 4'd6;
    localparam ST_CRC       = 4'd7;
    localparam ST_CRC_DELIM = 4'd8;
    localparam ST_EOF_WAIT  = 4'd9;

    reg [3:0] state;

    // -------------------------------------------------------------------------
    // 1. Bit Timing Unit (Synchronization & Oversampling)
    // -------------------------------------------------------------------------
    reg rxd_sync1, rxd_sync2, rxd_sync2_d;
    always @(posedge clk_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            rxd_sync1   <= 1'b1;
            rxd_sync2   <= 1'b1;
            rxd_sync2_d <= 1'b1;
        end else begin
            rxd_sync1   <= rxd;
            rxd_sync2   <= rxd_sync1;
            rxd_sync2_d <= rxd_sync2;
        end
    end
    
    wire falling_edge = !rxd_sync2 && rxd_sync2_d;
    reg [2:0] prescaler;
    reg [4:0] tq_count;
    
    wire tq_tick = (prescaler == 3'd4);
    wire sample_enable = (tq_tick && tq_count == 5'd15); 
    
    // Updated to use the clean parameter name
    wire is_idle = (state == ST_IDLE); 
    
    always @(posedge clk_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            prescaler <= 3'd0;
            tq_count  <= 5'd1;
        end else begin
            if (falling_edge && is_idle) begin 
                prescaler <= 3'd0;
                tq_count  <= 5'd1;
            end else if (tq_tick) begin
                prescaler <= 3'd0;
                if (tq_count == 5'd20) tq_count <= 5'd1;
                else tq_count <= tq_count + 5'd1;
            end else begin
                prescaler <= prescaler + 3'd1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 2. Destuffer
    // -------------------------------------------------------------------------
    reg [2:0] consec_cnt;
    reg       prev_bit;
    reg       destuffed_bit;
    reg       valid_bit_en;
    reg       stuff_err_flag;
    
    // Destuffing active from ST_ID to ST_CRC
    wire destuff_en = (state >= ST_ID && state <= ST_CRC); 

    always @(posedge clk_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            consec_cnt     <= 3'd1;
            prev_bit       <= 1'b1;
            valid_bit_en   <= 1'b0;
            stuff_err_flag <= 1'b0;
            destuffed_bit  <= 1'b1;
        end else begin
            valid_bit_en   <= 1'b0;
            stuff_err_flag <= 1'b0;

            if (sample_enable) begin
                if (!destuff_en) begin
                    consec_cnt    <= 3'd1;
                    prev_bit      <= rxd_sync2;
                    destuffed_bit <= rxd_sync2;
                    valid_bit_en  <= 1'b1;
                end else begin
                    if (consec_cnt == 3'd5) begin
                        if (rxd_sync2 == prev_bit) stuff_err_flag <= 1'b1;
                        consec_cnt <= 3'd1;
                        prev_bit   <= rxd_sync2;
                    end else begin
                        if (rxd_sync2 == prev_bit) consec_cnt <= consec_cnt + 3'd1;
                        else consec_cnt <= 3'd1;
                        
                        prev_bit      <= rxd_sync2;
                        destuffed_bit <= rxd_sync2;
                        valid_bit_en  <= 1'b1;
                    end
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // 3. CRC-15 LFSR (Polynomial: x^15 + x^14 + x^10 + x^8 + x^7 + x^4 + x^3 + 1)
    // -------------------------------------------------------------------------
    reg [14:0] calc_crc;
    reg [14:0] rx_crc;
    
    // CRC accumulates from ST_ID through ST_DATA
    wire crc_enable = (state >= ST_ID && state <= ST_DATA); 
    
    wire crc_feedback = calc_crc[14] ^ destuffed_bit;
    wire [14:0] next_crc = {calc_crc[13:0], 1'b0} ^ (crc_feedback ? 15'h4599 : 15'h0000);

    always @(posedge clk_50mhz or negedge rst_n) begin
        if (!rst_n) calc_crc <= 15'd0;
        else if (valid_bit_en) begin
            if (state == ST_IDLE) calc_crc <= 15'd0; // Reset at SOF
            else if (crc_enable) calc_crc <= next_crc;
        end
    end

    // -------------------------------------------------------------------------
    // 4. Protocol Engine FSM
    // -------------------------------------------------------------------------
    reg [6:0] bit_cnt;
    reg [63:0] data_reg;
    reg rtr_bit;

    assign data = (dlc == 0) ? 64'h0 : (data_reg << ((8 - dlc) * 8));
    wire [3:0] next_dlc = {dlc[2:0], destuffed_bit};

    always @(posedge clk_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            bit_cnt     <= 7'd0;
            id          <= 11'd0;
            dlc         <= 4'd0;
            data_reg    <= 64'd0;
            rx_crc      <= 15'd0;
            frame_valid <= 1'b0;
            frame_error <= 1'b0;
            rtr_bit     <= 1'b0;
        end else begin
            frame_valid <= 1'b0;
            frame_error <= 1'b0;

            if (stuff_err_flag) begin
                frame_error <= 1'b1;
                state       <= ST_IDLE; 
            end else if (valid_bit_en) begin
                case (state)
                    ST_IDLE: begin
                        if (destuffed_bit == 1'b0) begin 
                            state   <= ST_ID;
                            bit_cnt <= 7'd10;
                        end
                    end
                    ST_ID: begin
                        id <= {id[9:0], destuffed_bit};
                        if (bit_cnt == 0) state <= ST_RTR;
                        else bit_cnt <= bit_cnt - 7'd1;
                    end
                    ST_RTR: begin
                        rtr_bit <= destuffed_bit;
                        state   <= ST_IDE;
                    end
                    ST_IDE: state <= ST_R0; 
                    ST_R0: begin
                        state   <= ST_DLC;
                        bit_cnt <= 7'd3;
                    end
                    ST_DLC: begin
                        dlc <= next_dlc;
                        if (bit_cnt == 0) begin
                            if (rtr_bit || next_dlc == 4'd0 || next_dlc > 4'd8) begin
                                state   <= ST_CRC; 
                                bit_cnt <= 7'd14;
                            end else begin
                                state   <= ST_DATA;
                                bit_cnt <= (next_dlc * 7'd8) - 7'd1;
                            end
                        end else bit_cnt <= bit_cnt - 7'd1;
                    end
                    ST_DATA: begin
                        data_reg <= {data_reg[62:0], destuffed_bit};
                        if (bit_cnt == 0) begin
                            state   <= ST_CRC;
                            bit_cnt <= 7'd14;
                        end else bit_cnt <= bit_cnt - 7'd1;
                    end
                    ST_CRC: begin
                        rx_crc <= {rx_crc[13:0], destuffed_bit};
                        if (bit_cnt == 0) state <= ST_CRC_DELIM;
                        else bit_cnt <= bit_cnt - 7'd1;
                    end
                    ST_CRC_DELIM: begin
                        if (rx_crc != calc_crc) begin // Active CRC Validation Check
                            frame_error <= 1'b1;
                            state       <= ST_IDLE;
                        end else begin
                            state   <= ST_EOF_WAIT;
                            bit_cnt <= 7'd8; // ACK + ACK Delim + 7-bit EOF
                        end
                    end
                    ST_EOF_WAIT: begin
                        if (bit_cnt == 0) begin
                            frame_valid <= 1'b1; 
                            state       <= ST_IDLE;
                        end else bit_cnt <= bit_cnt - 7'd1;
                    end
                    default: state <= ST_IDLE;
                endcase
            end
        end
    end
endmodule