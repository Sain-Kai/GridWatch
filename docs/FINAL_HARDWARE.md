# GridWatch — Final Physical Hardware

## Inventory
- 1× ESP32 DevKit — main monitoring node (handles sensing, OLED, reasoning & direct Wi-Fi HTTP)
- 1× NodeMCU ESP8266 — optional (only needed if running legacy ESP-NOW gateway mode)
- 1× ESP32 DevKit — spare/expansion
- 1× K-type thermocouple + MAX6675
- 1× DHT11
- 1× FSR + 10 kΩ voltage-divider resistor
- 2× IR sensors
- 1× SSD1306 I²C OLED (0x3C expected)
- 1× small demo fan

## ESP32 DevKit pin map

| Signal | ESP32 pin |
|---|---:|
| MAX6675 SCK | GPIO18 |
| MAX6675 CS | GPIO5 |
| MAX6675 SO | GPIO19 |
| IR1 tamper beam | GPIO32 |
| IR2 fan rotation | GPIO33 |
| FSR divider output | GPIO34 / ADC1 |
| Load Potentiometer | GPIO35 / ADC1 |
| DHT11 data | GPIO17 |
| Fan driver control | GPIO16 |
| Alert LED | GPIO4 |
| OLED SDA | GPIO21 |
| OLED SCL | GPIO22 |

## Wiring

### MAX6675

```text
MAX6675 VCC → ESP32 3.3V
MAX6675 GND → ESP32 GND
MAX6675 SCK → GPIO18
MAX6675 CS  → GPIO5
MAX6675 SO  → GPIO19
```

Connect the K-type thermocouple to the MAX6675 T+ / T- terminals. Do not use a grounded thermocouple with this isolated-input arrangement.

### DHT11

```text
DHT11 VCC  → 3.3V
DHT11 DATA → GPIO17
DHT11 GND  → GND
```

A bare DHT11 typically needs a pull-up resistor on DATA; many breakout modules already include one.

### FSR voltage divider

```text
3.3V
 |
FSR
 |
 +---- GPIO34
 |
10kΩ
 |
GND
```

The firmware threshold `FSR_TAMPER_THRESHOLD` is a starting calibration value and should be tuned on the assembled hardware.

### Load Potentiometer (Simulated Load / CT stand-in)

```text
Potentiometer Pin 1 (Outer) → ESP32 3.3V
Potentiometer Pin 2 (Wiper) → GPIO35 / ADC1
Potentiometer Pin 3 (Outer) → ESP32 GND
```

Turning the dial simulates transformer load from 0% to 100%, updating the counterfactual expected-temperature model dynamically.

### IR sensors

IR1 is the tamper/interruption sensor. Current firmware expects:

```text
beam clear    → HIGH
beam broken   → LOW
```

IR2 is the fan-rotation evidence sensor. Its exact idle/high/low behavior must match the physical module and placement; the firmware counts state transitions rather than trusting a single level.

### OLED

```text
OLED VCC → 3.3V
OLED GND → GND
OLED SDA → GPIO21
OLED SCL → GPIO22
```

The firmware uses address `0x3C`.

### Alert LED

```text
GPIO4 → 220Ω resistor → LED anode
LED cathode → GND
```

## Fan Driver Circuit (Active Diagnostics)

To actively command the 5V DC cooling fan and verify rotation with IR2, wire an NPN transistor (BC547 or 2N2222):

```text
               +5V (from 5V rail or external 5V supply)
                |
                +----+
                |    |
             [Fan] [1N4007 Diode: Cathode (band) to +5V, Anode to Collector]
                |    |
                +----+
                |
             Collector
GPIO16 ──[1kΩ]──Base   (BC547 / 2N2222)
             Emitter
                |
               GND (Common Ground between ESP32 and Fan Power)
```

**Crucial Safety Rules**:
1. Never connect the fan motor directly to GPIO16 (ESP32 pins can only deliver 12-20mA, while a fan draws 100-300mA and induces flyback spikes).
2. The 1N4007 diode MUST be connected in reverse parallel across the fan motor leads (silver band towards +5V) to clamp back-EMF inductive voltage spikes when the transistor switches off.
3. Once wired, toggle `#define FAN_DRIVER_ENABLED 1` in `esp32_node.ino`. If you test before assembling the fan driver, leave `#define FAN_DRIVER_ENABLED 0`.

## Power architecture — verify before energizing

The current project does not prescribe a battery topology until the cells and charge/protection arrangement are known.

Do not connect two 18650 cells to a single-cell TP4056 as a 2S pack. Verify whether the cells are 1S2P or 2S and use a charger/BMS appropriate to that topology.

Before connecting the ESP32/ESP8266:

```text
measure regulator output with a multimeter
confirm the intended rail (3.3V or 5V) and polarity
confirm common ground
```

## Software fault logic

```text
invalid thermocouple → SENSOR_FAULT
critical valid temperature → CRITICAL_OVERHEAT
IR1 broken + FSR corroboration → TAMPER
IR1 broken alone → POSSIBLE_TAMPER
thermal deviation/rise concern + fan driver disabled → THERMAL_WARNING
thermal deviation/rise concern + fan driver enabled + IR2 verified → THERMAL_WARNING
thermal deviation/rise concern + fan driver enabled + no IR2 evidence → COOLING_FAILURE
otherwise → NORMAL
```

The ESP32 independently scans for SSID `Sain` and selects its 2.4 GHz AP channel before starting ESP-NOW. This removes the need to guess the router channel in firmware.
