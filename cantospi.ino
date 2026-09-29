#include <Arduino.h>
#include <string.h>
#include "driver/spi_slave.h"
#include "driver/spi_common.h"
#include "driver/twai.h"

// ---------- Active Pins ----------
#define CAN_TX_PIN GPIO_NUM_5
#define SPI_MOSI 13
#define SPI_SCLK 14
#define SPI_CS   15

// FPGA outputs a 112-bit packet (14 bytes)
#define SPI_PACKET_SIZE 14
WORD_ALIGNED_ATTR uint8_t spi_rx_buf[SPI_PACKET_SIZE];

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\nESP32 CAN Transmit + SPI Slave Test");

  // 1. Configure SPI Slave (Receive Only)
  spi_bus_config_t buscfg;
  memset(&buscfg, 0, sizeof(buscfg));
  buscfg.mosi_io_num = SPI_MOSI;
  buscfg.miso_io_num = -1;       // Completely disabled
  buscfg.sclk_io_num = SPI_SCLK;
  buscfg.quadwp_io_num = -1;
  buscfg.quadhd_io_num = -1;
  buscfg.max_transfer_sz = 32;

  spi_slave_interface_config_t slvcfg;
  memset(&slvcfg, 0, sizeof(slvcfg));
  slvcfg.spics_io_num = SPI_CS;
  slvcfg.queue_size = 1;
  slvcfg.mode = 0; 

  spi_slave_initialize(VSPI_HOST, &buscfg, &slvcfg, SPI_DMA_CH_AUTO);
  Serial.println("SPI Slave initialized on Pins 13, 14, 15.");

  // 2. Configure CAN (TWAI)
  twai_general_config_t g_config = TWAI_GENERAL_CONFIG_DEFAULT(CAN_TX_PIN, GPIO_NUM_4, TWAI_MODE_NO_ACK);
  twai_timing_config_t t_config = TWAI_TIMING_CONFIG_500KBITS();
  twai_filter_config_t f_config = TWAI_FILTER_CONFIG_ACCEPT_ALL();

  twai_driver_install(&g_config, &t_config, &f_config);
  twai_start();
  Serial.println("CAN Driver initialized on Pin 5.");

  Serial.println("\nType 's' in the serial monitor and press Enter to start.");
}

void loop() {
  if (Serial.available() > 0) {
    char incoming = Serial.read();
    if (incoming == 's' || incoming == 'S') {
      
      // A. Queue the SPI listener FIRST
      spi_slave_transaction_t t;
      memset(&t, 0, sizeof(t));
      t.length = SPI_PACKET_SIZE * 8; 
      t.rx_buffer = spi_rx_buf;
      t.tx_buffer = NULL; // Explicitly disabled
      
      spi_slave_queue_trans(VSPI_HOST, &t, portMAX_DELAY);

      // B. Transmit the CAN Frame
      twai_message_t message;
      message.identifier = 0x123;
      message.extd = 0;
      message.data_length_code = 8;
      uint8_t payload[8] = {0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88};
      memcpy(message.data, payload, 8);

      if (twai_transmit(&message, pdMS_TO_TICKS(1000)) == ESP_OK) {
        Serial.println("\n-> CAN Sent (ID: 0x123). Waiting for SPI reply...");
      }

      // C. Wait for the SPI transaction from the FPGA to complete (2-second timeout)
      spi_slave_transaction_t *completed = nullptr;
      esp_err_t result = spi_slave_get_trans_result(VSPI_HOST, &completed, pdMS_TO_TICKS(2000));

      if (result == ESP_OK) {
        Serial.print("<- SUCCESS: Received 14 bytes from FPGA: ");
        for (int i = 0; i < SPI_PACKET_SIZE; i++) {
          Serial.printf("%02X ", spi_rx_buf[i]);
        }
        Serial.println();
        
        if (spi_rx_buf[0] == 0xAA && spi_rx_buf[12] == 0x55 && spi_rx_buf[13] == 0x55) {
          Serial.println("<- VERIFIED: Packet headers and footers match perfectly!");
        }
      } else {
        Serial.printf("<- ERROR: SPI Receive Timed Out (Code: %d).\n", result);
      }
    }
  }
}