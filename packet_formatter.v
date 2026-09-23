`timescale 1ns / 1ps

module packet_formatter (
    input  wire [78:0]  rd_data,      
    input  wire         fifo_empty,
    output wire [111:0] spi_data,
    output wire         data_valid
);
    
    wire [10:0] id   = rd_data[78:68];
    wire [3:0]  dlc  = rd_data[67:64];
    wire [63:0] data = rd_data[63:0];

    assign spi_data = {
        8'hAA,                  
        1'b0, id[10:4],         
        id[3:0], 4'd0,          
        4'd0, dlc,              
        data,                   
        16'h5555                
    };

    assign data_valid = ~fifo_empty;

endmodule