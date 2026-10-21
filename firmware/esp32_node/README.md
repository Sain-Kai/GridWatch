# GridWatch ESP32 node

Board: **ESP32 DevKit**.

## Hardware status
The thermal/tamper sensing stack is enabled. The fan driver is intentionally **disabled** until an external transistor/MOSFET driver is available. The firmware will never drive GPIO16 high while the driver is disabled.

Set `FAN_DRIVER_ENABLED` to `1` only after the fan is wired through a suitable driver and external supply.

The ESP32 automatically scans for the configured gateway SSID (`Sain`) at boot and locks ESP-NOW to the discovered 2.4 GHz AP channel, so the user does not need to enter the router channel manually.
