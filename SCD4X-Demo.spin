{
----------------------------------------------------------------------------------------------------
    Filename:       SCD4X-Demo.spin
    Description:    SCD4X driver demo
        * CO2 data output
    Author:         Jesse Burt
    Started:        Aug 6, 2022
    Updated:        Sep 12, 2024
    Copyright (c) 2024 - See end of file for terms of use.
----------------------------------------------------------------------------------------------------
}

' Uncomment the two lines below to use the bytecode-based I2C engine
'#define SCD4X_I2C_BC
'#pragma exportdef(SCD4X_I2C_BC)

CON

    _clkmode    = xtal1+pll16x
    _xinfreq    = 5_000_000


OBJ

    env: "sensor.co2.scd4x" | SCL=28, SDA=29, I2C_FREQ=400_000
    ser: "com.serial.terminal.ansi" | SER_BAUD=115_200
    time: "time"


pub main() | co2

    setup()
    env.co2_set_alt_comp(0)                     ' your location's altitude above sea level (m)

    repeat
        env.measure()                           ' SCD41 only (ignored on SCD40)
        co2 := env.co2ppm()
        ser.pos_xy(0, 3)
        ser.printf2(@"CO2 (ppm): %5.5d.%0d\n\r", (co2 / 10), (co2 // 10))


PUB setup()

    ser.start()
    time.msleep(30)
    ser.clear()
    ser.strln(@"Serial terminal started")

    if ( env.start() )
        ser.strln(@"SCD4X driver started")
    else
        ser.strln(@"SCD4X driver failed to start - halting")
        repeat

    env.preset_active()


DAT
{
Copyright 2024 Jesse Burt

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

