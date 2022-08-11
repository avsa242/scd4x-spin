{
    --------------------------------------------
    Filename: sensor.co2.scd4x.spin
    Author: Jesse Burt
    Description: Driver for the scd4x CO2 sensor
    Copyright (c) 2022
    Started Aug 6, 2022
    Updated Aug 11, 2022
    See end of file for terms of use.
    --------------------------------------------
}
#include "sensor.co2.common.spinh"
#include "sensor.temp.common.spinh"
#include "sensor.rh.common.spinh"

CON

    SLAVE_WR        = core#SLAVE_ADDR
    SLAVE_RD        = core#SLAVE_ADDR|1

    DEF_SCL         = 28
    DEF_SDA         = 29
    DEF_HZ          = 100_000
    I2C_MAX_FREQ    = core#I2C_MAX_FREQ

' Operating modes
    STANDBY         = 0
    CONT            = 1

' Temperature scales
    C               = 0
    F               = 1

VAR

    long _co2
    long _temp
    long _rh
    long _presscomp
    byte _opmode

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
' Start using "standard" Propeller I2C pins and 100kHz
    return startx(DEF_SCL, DEF_SDA, DEF_HZ)

PUB startx(SCL_PIN, SDA_PIN, I2C_HZ): status
' Start using custom IO pins and I2C bus frequency
    if lookdown(SCL_PIN: 0..31) and lookdown(SDA_PIN: 0..31) and {
}   I2C_HZ =< core#I2C_MAX_FREQ                 ' validate pins and bus freq
        if (status := i2c.init(SCL_PIN, SDA_PIN, I2C_HZ))
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
    reset{}

PUB adc2co2(adc_word): co2
' Convert ADC word to CO2 concentration, in PPM
    return adc_word * 10

PUB alt_comp(alt): curr_alt
' Compensate CO2 measurements based on altitude, in meters
'   Valid values: 0..65535
'   Any other value polls the chip and returns the current setting
'   NOTE: The sensor must not be actively measuring for this setting to take effect
'       Call opmode(STANDBY) first
    case alt
        0..65535:
            writereg(core#SET_SENS_ALT, 3, @alt)
        other:
            curr_alt := 0
            readreg(core#GET_SENS_ALT, 3, @curr_alt)
            return curr_alt

PUB amb_pressure(press): curr_press
' Set ambient pressure, in millibars, for use in on-sensor compensation
'   Valid values:
'       0: disable compensation
'       700..1400 (* range unverified)
'   Any other value returns the current setting
    case press
        0, 700..1400:
            writereg(core#SET_AMB_PRESS, 2, @press)
            _presscomp := press
        other:
            return _presscomp

PUB cal_co2(ref_ppm): ppm | crc_rd
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
    if (crc_rd == crc.sensirioncrc8(@ppm, 2))
        return ppm

PUB co2_data{}: f_co2
' CO2 data
'   Returns: CO2 ADC word
    if (data_ready{})
        read_meas{}
    else
        return _co2

PUB data_ready{}: flag
' Flag indicating measurement data is ready
'   Returns: TRUE (-1) or FALSE (0)
    flag := 0
    readreg(core#GET_DRDY, 2, @flag)
    return ((flag & $7ff) <> 0)                 ' lower 11 bits set? data is ready

PUB rhdata{}: rh_adc
' Relative humidity data
'   Returns: RH ADC word
    if (data_ready{})
        read_meas{}
    else
        return _rh

PUB rhword2pct(adc_word): rh
' Convert ADC word to relative humidity, in hundredths of a percent
    return (100 * (adc_word * 100) / core#ADC_MAX)

PUB measure{}
' Read measurement data
    if (_opmode <> CONT)
        command(core#MEAS_ONE)

PUB opmode(mode): curr_mode
' Set operating mode
'   Valid values:
'   Any other value returns the current setting
    case mode
        CONT:
            _opmode := CONT
            command(core#START_MEAS)
        STANDBY:
            command(core#STOP_MEAS)
            _opmode := STANDBY

PUB reset{}
' Reset the device
    command(core#REINIT)

PUB serial_num(ptr_buff)
' Read the 48-bit serial number of the device into ptr_buff
'   Format: MSW..MW..LSW [47..32][31..16][15..0]
'   NOTE: Buffer at ptr_buff must be at least 6 bytes in length
'   NOTE: Serial number can only be read when no measurements are active
    readreg(core#GET_SN, 6, ptr_buff)

PUB temp_bias(tb): curr_bias
' Set temperature sensor bias/offset
'   Valid values: -10_00 .. 60_00 (-10C..60C, range unverified by datasheet)
'   Any other value returns the current setting
    case tb
        -10_00..60_00:
            tb := (tb * core#ADC_MAX) / 175_00
            writereg(core#SET_TEMP_OFFS, 2, @tb)
        other:
            curr_bias := 0
            readreg(core#GET_TEMP_OFFS, 2, @curr_bias)
            return (175 * (curr_bias * 100)) / core#ADC_MAX
            return

PUB tempdata{}: temp_adc
' Temperature data
'   Returns: temperature ADC word
    if (data_ready{})
        read_meas{}
    else
        return _temp

PUB tempword2deg(adc_word): temp
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
        core#START_MEAS:
            dly := 0
        core#MEAS_ONE:
            dly := core#T_MEAS
        core#STOP_MEAS:
            dly := core#T_STOP_MEAS
        core#REINIT:
            dly := core#T_REINIT

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

PRI readReg(reg_nr, nr_bytes, ptr_buff) | cmd_pkt, crc_rd, crc_calc, rdw, wd_nr, last_wd, dly
' Read nr_bytes from the device into ptr_buff
    case reg_nr                                 ' validate register num
        core#GET_SN, core#READ_MEAS, core#GET_SENS_ALT, core#GET_TEMP_OFFS:
            dly := core#T_CMD
        core#GET_DRDY:
            dly := core#T_GET_DRDY
        other:                                  ' invalid reg_nr
            return

    cmd_pkt.byte[0] := SLAVE_WR
    cmd_pkt.byte[1] := reg_nr.byte[1]
    cmd_pkt.byte[2] := reg_nr.byte[0]
    i2c.start{}
    i2c.wrblock_lsbf(@cmd_pkt, 3)
    i2c.stop
    time.usleep(dly)
    i2c.start{}
    i2c.wr_byte(SLAVE_RD)
    last_wd := (nr_bytes / 2)-1                 ' bytes to words
    repeat wd_nr from 0 to last_wd
        rdw := i2c.rdword_msbf(i2c#ACK)
        crc_rd := i2c.rd_byte(wd_nr == last_wd) ' NAK if this is the last word to be read
        crc_calc := crc.sensirioncrc8(@rdw, 2)
        if (crc_rd == crc_calc)                 ' copy data to caller if CRC is good
            word[ptr_buff][wd_nr] := rdw
    i2c.stop{}

PRI writeReg(reg_nr, nr_bytes, ptr_buff) | cmd_pkt, tmp, crc_calc, dly
' Write nr_bytes to the device from ptr_buff
    case reg_nr
        core#SET_SENS_ALT, core#SET_TEMP_OFFS:
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
    crc_calc := crc.sensirioncrc8(@tmp, 2)
    i2c.wrword_msbf(tmp)
    i2c.wr_byte(crc_calc)
    i2c.stop{}
    time.usleep(dly)

DAT
{
Copyright 2022 Jesse Burt

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

