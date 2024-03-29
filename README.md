# scd4x-spin 
------------

This is a P8X32A/Propeller, P2X8C4M64P/Propeller 2 driver object for the Sensirion SCD-4x CO2 sensors

**IMPORTANT**: This software is meant to be used with the [spin-standard-library](https://github.com/avsa242/spin-standard-library) (P8X32A) or [p2-spin-standard-library](https://github.com/avsa242/p2-spin-standard-library) (P2X8C4M64P). Please install the applicable library first before attempting to use this code, otherwise you will be missing several files required to build the project.

## Salient Features

* SCD-40, SCD-41 supported
* I2C connection at up to 100kHz
* Read serial number
* Read CO2 concentration, temperature, RH
* Set compensation for local altitude above sea level, or ambient pressure
* Automatic or manual CO2 calibration
* Set temperature bias/offset
* Continuous (SCD40, SCD41), continuous low-power (SCD40, SCD41)
or single-shot (SCD41 only) measurement modes
* Power down sensor (SCD41 only)
* Save configuration settings to sensor EEPROM
* Sensor built-in self-test


## Requirements

P1/SPIN1:
* spin-standard-library
* 1 extra core/cog for the PASM I2C engine (none if the SPIN I2C engine is used)
* sensor.temp.common.spinh (source: spin-standard-library)
* sensor.rh.common.spinh (source: spin-standard-library)
* sensor.co2.common.spinh (source: spin-standard-library)

P2/SPIN2:
* p2-spin-standard-library
* sensor.temp.common.spin2h (source: p2-spin-standard-library)
* sensor.rh.common.spin2h (source: p2-spin-standard-library)
* sensor.co2.common.spin2h (source: p2-spin-standard-library)


## Compiler Compatibility

| Processor | Language | Compiler               | Backend      | Status                |
|-----------|----------|------------------------|--------------|-----------------------|
| P1        | SPIN1    | FlexSpin (6.2.1)       | Bytecode     | OK                    |
| P1        | SPIN1    | FlexSpin (6.2.1)       | Native/PASM  | OK                    |
| P2        | SPIN2    | FlexSpin (6.2.1)       | NuCode       | FTBFS                 |
| P2        | SPIN2    | FlexSpin (6.2.1)       | Native/PASM2 | OK                    |

(other versions or toolchains not listed are __not supported__, and _may or may not_ work)


## Hardware compatibility

* Tested with Adafruit SCD40
* Tested with Adafruit SCD41


## Limitations

* Very early in development - may malfunction, or outright fail to build
* Range of allowed values for ambient pressure compensation isn't verified (not available in datasheet), so it was copied from the SCD30

