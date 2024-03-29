{
    --------------------------------------------
    Filename: sensor.co2.scd4x.spin
    Author: Jesse Burt
    Description: Driver for the scd4x CO2 sensor
    Copyright (c) 2023
    Started Aug 6, 2022
    Updated Jul 15, 2023
    See end of file for terms of use.
    --------------------------------------------
}
#include "sensor.co2.common.spinh"
#include "sensor.temp.common.spinh"
#include "sensor.rh.common.spinh"

CON

    SLAVE_WR    = core#SLAVE_ADDR
    SLAVE_RD    = core#SLAVE_ADDR|1

    DEF_SCL     = 28
    DEF_SDA     = 29
    DEF_HZ      = 100_000
    DEF_ADDR    = 0
    I2C_MAX_FREQ= core#I2C_MAX_FREQ

    { Operating modes }
    STANDBY     = 0
    CONT        = 1
    CONT_LP     = 2

    { measurement mode }
    ALL         = 0
    RHT         = 1                         ' any non-zero value

    { default I/O settings; these can be overridden in the parent object }
    SCL         = DEF_SCL
    SDA         = DEF_SDA
    I2C_FREQ    = DEF_HZ
    I2C_ADDR    = DEF_ADDR

VAR

    long _co2
    long _temp
    long _rh
    long _presscomp
    byte _opmode, _meas_md

OBJ

{ decide: Bytecode I2C engine, or PASM? Default is PASM if BC isn't specified }
#ifdef SCD4X_I2C_BC
    i2c : "com.i2c.nocog"                       ' BC I2C engine
#else
    i2c : "com.i2c"                             ' PASM I2C engine
#endif
    core: "core.con.scd4x"                      ' hw-specific low-level const's
    time: "time"                                ' basic timing functions
    crc : "math.crc"                            ' CRC routines

PUB null{}
' This is not a top-level object

PUB start{}: status
' Start using default I/O settings
    return startx(SCL, SDA, I2C_FREQ)

PUB startx(SCL_PIN, SDA_PIN, I2C_HZ): status
' Start using custom IO pins and I2C bus frequency
    if ( lookdown(SCL_PIN: 0..31) and lookdown(SDA_PIN: 0..31) )
        if ( status := i2c.init(SCL_PIN, SDA_PIN, I2C_HZ) )
            time.usleep(core#T_POR)             ' wait for device startup
            return
    ' if this point is reached, something above failed
    ' Re-check I/O pin assignments, bus speed, connections, power
    ' Lastly - make sure you have at least one free core/cog 
    return FALSE

PUB stop{}
' Stop the driver
    i2c.deinit{}

PUB defaults{}
' Set factory defaults
'   * Reset all configuration settings stored in sensor EEPROM
'   * Erase manual and/or automatic calibration history
    command(core#FACT_RESET)

PUB preset_active{}
' Use power-on-reset defaults, then transition to continuous measurement
    reset{}
    opmode(CONT)

PUB adc2co2(adc_word): co2
' Convert ADC word to CO2 concentration, in PPM
    return adc_word * 10

PUB co2_alt_comp{}: alt
' Get altitude compensation value
'   Returns: meters
    alt := 0
    readreg(core#GET_SENS_ALT, 3, @alt)

PUB co2_set_alt_comp(alt)
' Compensate CO2 measurements based on altitude, in meters
'   Valid values: 0..65535 (clamped to range)
'   NOTE: opmode() must be set to STANDBY for this setting to take effect
    alt := 0 #> alt <# 65535
    writereg(core#SET_SENS_ALT, 3, @alt)

PUB co2_amb_press_comp{}: curr_press
' Get ambient pressure for use in on-sensor compensation
'   Returns: millibars
'   NOTE: Returns value cached in MCU RAM by set_amb_pressure()
    return _presscomp

PUB co2_set_amb_press_comp(press)
' Set ambient pressure, in millibars, for use in on-sensor compensation
'   Valid values:
'       0: disable compensation
'       700..1400 (* range unverified)
'   NOTE: This method may be called while the sensor is actively measuring
    if (press)
        press := 700 #> press <# 1400
    writereg(core#SET_AMB_PRESS, 2, @press)
    _presscomp := press

PUB auto_cal_ena(state): curr_state
' Enable automatic self-calibration
'   Valid values: TRUE (-1 or 1), *FALSE (0)
'   Any other value polls the chip and returns the current setting
'   NOTE: opmode() must be set to STANDBY for this setting to take effect
    case ||(state)
        0, 1:
            state := ||(state)
            writereg(core#SET_AUTOCAL, 2, @state)
        other:
            curr_state := 0
            readreg(core#GET_AUTOCAL, 2, @curr_state)
            return (curr_state == 1)

PUB co2_cal(ref_ppm): ppm | crc_rd
' Perform manual CO2 sensor calibration, given target CO2 concentration in ppm
'   NOTE: To successfully perform accurate calibration, follow these steps:
'       1. Operate the sensor in the end-application's desired opmode() for at least 3 minutes
'           in an environment with a uniform and constant CO2 concentration
'       2. Set opmode() to STANDBY
'       3. Call this method (optionally read return value)
'   Returns:
'       magnitude of correction, in ppm (for informational purposes only; no action
'           is required with this value)
'       $ffff if failed
    if (lookdown(ref_ppm: 0..65535))
        writereg(core#RE_CAL, 2, @ref_ppm)
    else
        return

    i2c.start{}
    i2c.write(SLAVE_RD)
    ppm := (i2c.rdword_msbf(i2c#ACK)-$8000)
    crc_rd := i2c.rd_byte(i2c#NAK)
    i2c.stop{}
    if (crc_rd == crc.sensirion_crc8(@ppm, 2))
        return ppm

PUB co2_data{}: f_co2
' CO2 data
'   Returns: CO2 ADC word
    if ( co2_data_rdy{} )
        read_meas{}
    return _co2

PUB co2_data_rdy{}: flag
' Flag indicating measurement data is ready
'   Returns: TRUE (-1) or FALSE (0)
    flag := 0
    readreg(core#GET_DRDY, 2, @flag)
    return ((flag & $7ff) <> 0)                 ' lower 11 bits set? data is ready

PUB measure{}
' Read measurement data
'   NOTE: opmode() must be set to STANDBY for this setting to take effect
'   NOTE: This only functions with the SCD41
    if (_opmode == STANDBY)
        if (_meas_md)
            command(core#MEAS_ONE_RHT)          ' measure RH, temp only
        else
            command(core#MEAS_ONE)              ' measure all

PUB meas_mode(mode)
' Set measurement mode (for one-shot measurements only)
'   ALL (0): perform all measurements (default)
'   non-zero: measure RH, temperature only
    if (mode)
        _meas_md := 1
    else
        _meas_md := 0

PUB opmode(mode): curr_mode
' Set operating mode
'   Valid values:
'   Any other value returns the current setting
    case mode
        CONT:                                   ' continuous/periodic measurements
            command(core#START_MEAS)
        CONT_LP:                                ' same, but low-power
            command(core#START_LP_MEAS)
        STANDBY:                                ' standby/idle
            command(core#STOP_MEAS)             '   (also enables single-shot meas. for SCD41)

    _opmode := mode

PUB powered(state)
' Power on sensor (*SCD41 only)
'   NOTE: opmode() must be set to STANDBY for this setting to take effect
    if (state)
        command(core#WAKE)                      ' power on
    else
        command(core#PWR_DN)                    ' power off

PUB reset{}
' Reset the device
    command(core#STOP_MEAS)
    command(core#REINIT)

PUB rh_data{}: rh_adc
' Relative humidity data
'   Returns: RH ADC word
    if ( co2_data_rdy{} )
        read_meas{}
    return _rh

PUB rh_word2pct(adc_word): rh
' Convert ADC word to relative humidity, in hundredths of a percent
    return (100 * (adc_word * 100) / core#ADC_MAX)

PUB save_settings{}
' Save configuration settings to sensor EEPROM
'   NOTE: opmode() must be set to STANDBY for this setting to take effect
'   NOTE: The sensor EEPROM's write endurance is >2000 cycles. Calling this method is
'       recommended only when required and when settings have actually changed.
'       Calibration (automatic and manual) is automatically stored in a separate sensor EEPROM
'       with an endurance matched to the sensor's lifetime.
    command(core#PERSIST_SET)

PUB self_test{}: status
' Perform sensor self-test
'   Returns:
'       0: no malfunction detected
'       non-zero: malfunction detected
'   NOTE: opmode() must be set to STANDBY for this setting to take effect
'   NOTE: This method takes approx 10sec to execute
    status := 0
    readreg(core#SELF_TEST, 2, @status)

PUB serial_num(ptr_buff)
' Read the 48-bit serial number of the device into ptr_buff
'   Format: MSW..MW..LSW [47..32][31..16][15..0]
'   NOTE: opmode() must be set to STANDBY before reading
'   NOTE: Buffer at ptr_buff must be at least 6 bytes in length
    readreg(core#GET_SN, 6, ptr_buff)

PUB temp_bias(tb): curr_bias
' Set temperature sensor bias/offset
'   Valid values: -10_00 .. 60_00 (-10C..60C, range unverified by datasheet)
'   Any other value returns the current setting
'   NOTE: opmode() must be set to STANDBY for this setting to take effect
    case tb
        -10_00..60_00:
            tb := (tb * core#ADC_MAX) / 175_00
            writereg(core#SET_TEMP_OFFS, 2, @tb)
        other:
            curr_bias := 0
            readreg(core#GET_TEMP_OFFS, 2, @curr_bias)
            return (175 * (curr_bias * 100)) / core#ADC_MAX
            return

PUB temp_data{}: temp_adc
' Temperature data
'   Returns: temperature ADC word
    if ( co2_data_rdy{} )
        read_meas{}
    return _temp

PUB temp_word2deg(adc_word): temp
' Convert ADC word to temperature, in hundredths of a degree in chosen scale
   case _temp_scale
        C:
            return ((175 * (adc_word * 100)) / core#ADC_MAX)-(45 * 100)
        F:
            return ((315 * (adc_word * 100)) / core#ADC_MAX)-(49 * 100)
        other:
            return FALSE

PRI command(cmd) | cmd_pkt, dly
' Issue command to the device
    case cmd
        core#START_MEAS, core#START_LP_MEAS:
            dly := 0
        core#MEAS_ONE:
            dly := core#T_MEAS_ONE
        core#MEAS_ONE_RHT:
            dly := core#T_MEAS_ONE_RHT
        core#STOP_MEAS:
            dly := core#T_STOP_MEAS
        core#REINIT:
            dly := core#T_REINIT
        core#FACT_RESET:
            dly := core#T_FACT_RESET
        core#PWR_DN:
            dly := core#T_CMD
        core#WAKE:
            dly := core#T_WAKE
        core#PERSIST_SET:
            dly := core#T_PERSIST_SET

    cmd_pkt.byte[0] := SLAVE_WR
    cmd_pkt.byte[1] := cmd.byte[1]
    cmd_pkt.byte[2] := cmd.byte[0]
    i2c.start{}
    i2c.wrblock_lsbf(@cmd_pkt, 3)
    i2c.stop{}
    time.usleep(dly)

PRI read_meas{} | tmp[2]
' Read measurements and cache in RAM
'   NOTE: Valid data will be returned only if the data_ready() signal is TRUE
    longfill(@tmp, 0, 2)
    readreg(core#READ_MEAS, 6, @tmp)
    _co2 := tmp.word[0]
    _temp := ~~tmp.word[1]
    _rh := tmp.word[2]

PRI readreg(reg_nr, nr_bytes, ptr_buff) | cmd_pkt, crc_rd, crc_calc, rdw, wd_nr, last_wd, dly
' Read nr_bytes from the device into ptr_buff
    case reg_nr                                 ' validate register num
        core#GET_SN, core#READ_MEAS, core#GET_SENS_ALT, core#GET_TEMP_OFFS, core#GET_AUTOCAL:
            dly := core#T_CMD
        core#SELF_TEST:
            dly := core#T_SELF_TEST
        core#GET_DRDY:
            dly := core#T_GET_DRDY
        other:                                  ' invalid reg_nr
            return

    cmd_pkt.byte[0] := SLAVE_WR
    cmd_pkt.byte[1] := reg_nr.byte[1]
    cmd_pkt.byte[2] := reg_nr.byte[0]
    i2c.start{}
    i2c.wrblock_lsbf(@cmd_pkt, 3)
    i2c.stop{}
    time.usleep(dly)
    i2c.start{}
    i2c.wr_byte(SLAVE_RD)
    last_wd := (nr_bytes / 2)-1                 ' bytes to words
    repeat wd_nr from 0 to last_wd
        rdw := i2c.rdword_msbf(i2c#ACK)
        crc_rd := i2c.rd_byte(wd_nr == last_wd) ' NAK if this is the last word to be read
        crc_calc := crc.sensirion_crc8(@rdw, 2)
        if (crc_rd == crc_calc)                 ' copy data to caller if CRC is good
            word[ptr_buff][wd_nr] := rdw
    i2c.stop{}

PRI writereg(reg_nr, nr_bytes, ptr_buff) | cmd_pkt, tmp, crc_calc, dly
' Write nr_bytes to the device from ptr_buff
    case reg_nr
        core#SET_SENS_ALT, core#SET_TEMP_OFFS, core#SET_AUTOCAL, core#SET_AMB_PRESS:
            dly := core#T_CMD
        core#RE_CAL:
            dly := core#T_RECAL
        other:
            return

    cmd_pkt.byte[0] := SLAVE_WR
    cmd_pkt.byte[1] := reg_nr.byte[1]
    cmd_pkt.byte[2] := reg_nr.byte[0]

    i2c.start{}
    i2c.wrblock_lsbf(@cmd_pkt, 3)
    tmp.byte[1] := byte[ptr_buff][1]
    tmp.byte[0] := byte[ptr_buff][0]
    crc_calc := crc.sensirion_crc8(@tmp, 2)
    i2c.wrword_msbf(tmp)
    i2c.wr_byte(crc_calc)
    i2c.stop{}
    time.usleep(dly)

DAT
{
Copyright 2023 Jesse Burt

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
}

