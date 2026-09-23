`timescale 1ns / 1ps

module spi_master_tx (
    input  wire         clk_50mhz,
    input  wire         rst_n,
    input  wire [111:0] spi_data,
    input  wire         data_valid,
    input  wire         fifo_empty,
    
    output reg          sck,
    output reg          mosi,
    output reg          cs_n,
    output reg          fifo_rd_en
);

    localparam ST_IDLE      = 3'd0;
    localparam ST_POP_FIFO  = 3'd1;
    localparam ST_LOAD_FIFO = 3'd2;
    localparam ST_TX        = 3'd3;
    localparam ST_DONE      = 3'd4;
    localparam ST_WAIT_FIFO = 3'd5;

    reg [2:0]   state; // Expanded to 3 bits for new states
    reg [6:0]   bit_cnt;
    reg [3:0]   baud_cnt; 
    reg [111:0] shift_reg;

    always @(posedge clk_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            cs_n       <= 1'b1;
            sck        <= 1'b0;
            mosi       <= 1'b1;
            fifo_rd_en <= 1'b0;
            bit_cnt    <= 7'd0;
            baud_cnt   <= 4'd0;
            shift_reg  <= 112'd0;
        end else begin
            fifo_rd_en <= 1'b0; // Default off

            case (state)
                ST_IDLE: begin
                    sck      <= 1'b0;
                    cs_n     <= 1'b1;
                    mosi     <= 1'b1;
                    baud_cnt <= 4'd0;
                    
                    // 1. Initiate the FIFO read
                    if (!fifo_empty) begin
                        fifo_rd_en <= 1'b1; 
                        state      <= ST_POP_FIFO;
                    end
                end

                ST_POP_FIFO: begin
                    // 2. fifo_rd_en is high during this cycle.
                    // The FIFO will clock it in at the end of this state.
                    state <= ST_LOAD_FIFO;
                end

                ST_LOAD_FIFO: begin
                    // 3. FIFO rd_data is now valid. spi_data is stable.
                    shift_reg <= spi_data;
                    bit_cnt   <= 7'd111;
                    cs_n      <= 1'b0;
                    mosi      <= spi_data[111];
                    state     <= ST_TX;
                end

                ST_TX: begin
                    if (baud_cnt == 4'd9) begin
                        baud_cnt <= 4'd0;
                        sck      <= 1'b0; 
                        
                        if (bit_cnt == 0) begin
                            state <= ST_DONE;
                        end else begin
                            shift_reg <= {shift_reg[110:0], 1'b0};
                            mosi      <= shift_reg[110]; 
                            bit_cnt   <= bit_cnt - 7'd1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 4'd1;
                        if (baud_cnt == 4'd4) sck <= 1'b1; 
                    end
                end

                ST_DONE: begin
                    if (baud_cnt == 4'd9) begin
                        baud_cnt   <= 4'd0; 
                        cs_n       <= 1'b1;
                        // fifo_rd_en REMOVED from here to prevent double-popping
                        state      <= ST_WAIT_FIFO;
                    end else begin
                        baud_cnt <= baud_cnt + 4'd1;
                    end
                end
                
                ST_WAIT_FIFO: begin
                    sck   <= 1'b0;
                    state <= ST_IDLE;
                end
                
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule