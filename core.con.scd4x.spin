{
    --------------------------------------------
    Filename: core.con.scd4x.spin
    Author: Jesse Burt
    Description: SCD4x-specific constants
    Copyright (c) 2022
    Started Aug 6, 2022
    Updated Aug 6, 2022
    See end of file for terms of use.
    --------------------------------------------
}

CON

' I2C Configuration
    I2C_MAX_FREQ    = 100_000                   ' device max I2C bus freq
    SLAVE_ADDR      = $62 << 1                  ' 7-bit format slave address
    T_POR           = 1_000_000                 ' startup time (usecs)
    T_RES           = 1_000_000

    DEVID_RESP      = $00                       ' device ID expected response


    START_MEAS      = $21B1
    READ_MEAS       = $EC05
    STOP_MEAS       = $3F86

    SET_TEMP_OFFS   = $241D
    GET_TEMP_OFFS   = $2318
    SET_SENS_ALT    = $2427
    GET_SENS_ALT    = $2322
    SET_AMB_PRESS   = $E000

    RE_CAL          = $362F
    SET_AUTOCAL     = $2416
    GET_AUTOCAL     = $2313

    START_LP_MEAS   = $21AC
    GET_DRDY        = $E4B8

    PERSIST_SET     = $3615
    GET_SN          = $3682
    SELF_TEST       = $3639
    FACT_RESET      = $3632
    REINIT          = $3646

    MEAS_ONE        = $219D
    MEAS_ONE_RHT    = $2196
    PWR_DN          = $36E0
    WAKE            = $36F6


PUB Null{}
' This is not a top-level object

