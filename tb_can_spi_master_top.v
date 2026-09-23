`timescale 1ns / 1ps

module tb_can_spi_master_top();

    // System Signals
    reg        clk_50mhz;
    reg        rst_n;
    reg        can_rx;
    
    // SPI Master Bus (Driven by DUT)
    wire       sck;
    wire       mosi;
    wire       cs_n;

    // DUT Instantiation
    can_spi_master_top dut (
        .clk_50mhz(clk_50mhz),
        .rst_n(rst_n),
        .can_rx(can_rx),
        .sck(sck),
        .mosi(mosi),
        .cs_n(cs_n)
    );

    // 50 MHz Ideal Clock 
    always #10 clk_50mhz = ~clk_50mhz;

    // -------------------------------------------------------------------------
    // AUTOMATIC SPI SNIFFER (Runs in background)
    // -------------------------------------------------------------------------
    reg [111:0] spi_rx_packet;
    reg         spi_done;
    integer     spi_idx; 
    
    always @(negedge cs_n) begin
        spi_done = 1'b0;
        spi_rx_packet = 112'd0;
        $display("[%0t] [SPI] Transaction Started (CS_N Low)", $time);
        
        for (spi_idx = 0; spi_idx < 112; spi_idx = spi_idx + 1) begin
            @(posedge sck); // Sample on rising edge
            spi_rx_packet = {spi_rx_packet[110:0], mosi};
        end
        
        @(posedge cs_n);
        spi_done = 1'b1;
        $display("[%0t] [SPI] Transaction Complete. Captured: 0x%028X", $time, spi_rx_packet);
    end

    // -------------------------------------------------------------------------
    // CAN FRAME INJECTOR 
    // -------------------------------------------------------------------------
    reg [14:0] current_crc;
    
    task push_crc(input bit_in);
        reg crc_msb;
        begin
            crc_msb = current_crc[14];
            current_crc = {current_crc[13:0], 1'b0};
            if (crc_msb ^ bit_in) current_crc = current_crc ^ 15'h4599; 
        end
    endtask

    task send_can_bit(input bit_val);
        begin
            can_rx = bit_val;
            #2000; // 500 kbps bit time
        end
    endtask

    reg       last_bit;
    integer   consec_cnt;

    task reset_stuffing();
        begin
            consec_cnt = 0;
            last_bit   = 1'bx;
        end
    endtask

    task stuff_and_send(input bit_val);
        begin
            if (consec_cnt == 5) begin
                send_can_bit(~last_bit);
                last_bit   = ~last_bit;
                consec_cnt = 1;
            end
            send_can_bit(bit_val);
            if (bit_val === last_bit) consec_cnt = consec_cnt + 1;
            else begin
                consec_cnt = 1;
                last_bit   = bit_val;
            end
        end
    endtask

    task send_can_frame(
        input [10:0] id,
        input        rtr,
        input [3:0]  dlc,
        input [63:0] data
    );
        integer i;
        begin
            $display("\n[%0t] [CAN] Injecting Frame -> ID: 0x%03X, DLC: %0d", $time, id, dlc);
            
            // Calculate Expected CRC-15
            current_crc = 15'd0;
            push_crc(1'b0); // SOF
            for (i = 10; i >= 0; i = i - 1) push_crc(id[i]);
            push_crc(rtr);
            push_crc(1'b0); // IDE
            push_crc(1'b0); // r0
            for (i = 3; i >= 0; i = i - 1) push_crc(dlc[i]);
            if (!rtr && dlc > 0) begin
                for (i = (dlc * 8) - 1; i >= 0; i = i - 1) push_crc(data[i]);
            end
            
            // Physical Transmit with Stuffing
            reset_stuffing();
            stuff_and_send(1'b0); // SOF
            for (i = 10; i >= 0; i = i - 1) stuff_and_send(id[i]);
            stuff_and_send(rtr);
            stuff_and_send(1'b0); // IDE
            stuff_and_send(1'b0); // r0
            for (i = 3; i >= 0; i = i - 1) stuff_and_send(dlc[i]);
            if (!rtr && dlc > 0) begin
                for (i = (dlc * 8) - 1; i >= 0; i = i - 1) stuff_and_send(data[i]);
            end
            for (i = 14; i >= 0; i = i - 1) stuff_and_send(current_crc[i]);

            // EOF and Intermission
            send_can_bit(1'b1); // CRC Delim
            send_can_bit(1'b1); // ACK
            send_can_bit(1'b1); // ACK Delim
            repeat(7) send_can_bit(1'b1); // EOF
            repeat(3) send_can_bit(1'b1); // Intermission

            can_rx = 1'b1;
            #10000; 
        end
    endtask

    // -------------------------------------------------------------------------
    // MAIN TEST SEQUENCE
    // -------------------------------------------------------------------------
    initial begin
        // GTKWave VCD Dump Initialization
        $dumpfile("can_spi_waveform.vcd");
        $dumpvars(0, tb_can_spi_master_top);

        // Initialize
        clk_50mhz = 0;
        rst_n     = 0;
        can_rx    = 1'b1;
        spi_done  = 1'b0;

        // Apply ASIC Reset
        #200; 
        rst_n = 1; 
        #1000;

        // Inject Test Frame: ID 0x123, 8 bytes of data
        send_can_frame(11'h123, 1'b0, 4'd8, 64'h11223344_55667788);
        
        // Wait for the SPI Master FSM to burst the data out
        wait(spi_done == 1'b1);
        
        // Verify final packet formatting
        if (spi_rx_packet === 112'hAA_12_30_08_1122334455667788_5555)
            $display("[%0t] [PASS] Formatted SPI Output verified successfully.", $time);
        else
            $display("[%0t] [FAIL] SPI Output mismatch. Got: %028X", $time, spi_rx_packet);

        #50000;
        $finish;
    end

endmodule