`timescale 1ns / 1ps

module can_spi_master_top (
    input  wire clk_50mhz,  
    input  wire rst_n,      
    input  wire can_rx,     
    
    output wire sck,        
    output wire mosi,       
    output wire cs_n        
);

    wire        frame_valid, frame_error;
    wire [10:0] id;
    wire [3:0]  dlc;
    wire [63:0] data;
    
    wire        fifo_full, fifo_empty, fifo_rd_en;
    wire [78:0] fifo_rd_data;
    
    wire [111:0] spi_data;
    wire         data_valid;

    can_controller u_can_rx (
        .clk_50mhz(clk_50mhz),
        .rst_n(rst_n),
        .rxd(can_rx),
        .frame_valid(frame_valid),
        .id(id),
        .dlc(dlc),
        .data(data),
        .frame_error(frame_error)
    );

    wire [78:0] fifo_wr_data = {id, dlc, data};
    
    can_sync_fifo u_fifo (
        .clk_50mhz(clk_50mhz),
        .rst_n(rst_n),
        .wr_en(frame_valid & ~frame_error),
        .wr_data(fifo_wr_data),
        .fifo_full(fifo_full),
        
        .rd_en(fifo_rd_en),
        .rd_data(fifo_rd_data),
        .fifo_empty(fifo_empty)
    );

    packet_formatter u_formatter (
        .rd_data(fifo_rd_data),
        .fifo_empty(fifo_empty),
        .spi_data(spi_data),
        .data_valid(data_valid)
    );

    spi_master_tx u_spi_master (
        .clk_50mhz(clk_50mhz),
        .rst_n(rst_n),
        .spi_data(spi_data),
        .data_valid(data_valid),
        .fifo_empty(fifo_empty),
        
        .sck(sck),
        .mosi(mosi),
        .cs_n(cs_n),
        .fifo_rd_en(fifo_rd_en)
    );

endmodule