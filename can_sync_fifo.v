`timescale 1ns / 1ps

module can_sync_fifo #(
    parameter DATA_WIDTH = 79,
    parameter DEPTH_WIDTH = 2 // 4 entries
)(
    input  wire                  clk_50mhz,
    input  wire                  rst_n,
    
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire                  fifo_full,
    
    input  wire                  rd_en,
    output reg  [DATA_WIDTH-1:0] rd_data, // ASIC Registered Output
    output wire                  fifo_empty
);

    reg [DATA_WIDTH-1:0] mem [0:(1<<DEPTH_WIDTH)-1];
    reg [DEPTH_WIDTH:0]  count;
    reg [DEPTH_WIDTH-1:0] wr_ptr;
    reg [DEPTH_WIDTH-1:0] rd_ptr;

    assign fifo_full  = (count == (1 << DEPTH_WIDTH));
    assign fifo_empty = (count == 0);

    always @(posedge clk_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            count   <= 0;
            wr_ptr  <= 0;
            rd_ptr  <= 0;
            rd_data <= 0;
        end else begin
            // Write Logic
            if (wr_en && !fifo_full) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr      <= wr_ptr + 1'b1;
            end
            
            // Read Logic (Registered Output)
            if (rd_en && !fifo_empty) begin
                rd_data <= mem[rd_ptr];
                rd_ptr  <= rd_ptr + 1'b1;
            end
            
            // Count Management
            if ((wr_en && !fifo_full) && !(rd_en && !fifo_empty))
                count <= count + 1'b1;
            else if (!(wr_en && !fifo_full) && (rd_en && !fifo_empty))
                count <= count - 1'b1;
        end
    end
endmodule