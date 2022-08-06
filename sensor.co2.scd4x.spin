{
    --------------------------------------------
    Filename: sensor.co2.scd4x.spin
    Author: Jesse Burt
    Description: Driver for the scd4x CO2 sensor
    Copyright (c) 2022
    Started Aug 6, 2022
    Updated Aug 6, 2022
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

PUB co2_data{}: f_co2
' CO2 data
'   Returns: IEEE-754 float
    return _co2

PUB co2_ppm{}: ppm
' CO2 concentration, in tenths of a part-per-million
'   Returns: Integer

PUB device_id{}: id
' Read device identification

PUB rhdata{}: rh_adc
' Relative humidity data
'   Returns: IEEE-754 float
    return _rh

PUB rhword2pct(adc_word): rh

PUB measure{}
' Read measurement data

PUB opmode(mode): curr_mode
' Set operating mode
'   Valid values:
'   Any other value returns the current setting

PUB reset{}
' Reset the device

PUB serial_num(ptr_buff)
' Read the 48-bit serial number of the device into ptr_buff
'   NOTE: Buffer at ptr_buff must be at least 6 bytes in length
'   Format: MSW..MW..LSW [47..32][31..16][15..0]
    readreg(core#GET_SN, 6, ptr_buff)

PUB tempdata{}: temp_adc
' Temperature data
'   Returns: IEEE-754 float
    return _temp

PUB tempword2deg(adc_word): temp

PRI readReg(reg_nr, nr_bytes, ptr_buff) | cmd_pkt, crc_rd, crc_calc, tmp, i
' Read nr_bytes from the device into ptr_buff
    case reg_nr                                 ' validate register num
        core#GET_SN:
            cmd_pkt.byte[0] := SLAVE_WR
            cmd_pkt.byte[1] := reg_nr.byte[1]
            cmd_pkt.byte[2] := reg_nr.byte[0]
            i2c.start{}
            i2c.wrblock_lsbf(@cmd_pkt, 3)
            i2c.stop
            ' wait?
            i2c.start{}
            i2c.wr_byte(SLAVE_RD)
            repeat i from 0 to 2
                tmp := i2c.rdword_msbf(i2c#ACK)
                crc_rd := i2c.rd_byte(i == 2)
                crc_calc := crc.sensirioncrc8(@tmp, 2)
                if (crc_rd == crc_calc)
                    word[ptr_buff][2-i] := tmp
            i2c.stop{}
            return
        other:                                  ' invalid reg_nr
            return

PRI writeReg(reg_nr, nr_bytes, ptr_buff) | cmd_pkt, dat_tmp
' Write nr_bytes to the device from ptr_buff
    cmd_pkt.byte[0] := SLAVE_WR
    cmd_pkt.byte[1] := reg_nr.byte[1]
    cmd_pkt.byte[2] := reg_nr.byte[0]
    case reg_nr
        0:
            i2c.start{}
            i2c.wrblock_lsbf(@cmd_pkt, 3)

            ' write MSByte to LSByte
            i2c.wrblock_msbf(@dat_tmp, nr_bytes)
            i2c.stop{}
        other:
            return

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

