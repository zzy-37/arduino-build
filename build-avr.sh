#!/bin/sh
set -e

. ./env.sh

[ "$1" = "clean" ] && {
    rm -v *.o *.a *.elf *.hex
    exit
}

[ "$1" = "size" ] && {
    avr-size -A sketch.elf
    exit
}

MCU=atmega328p

ARDUINO_CORE_PATH=./MiniCore/avr/cores/MCUdude_corefiles
INCLUDES="-I$ARDUINO_CORE_PATH -I./MiniCore/avr/variants/standard"
CFLAGS="-Wall -Wextra -Os -flto -ffunction-sections -fdata-sections"
CXXFLAGS="$CFLAGS -fpermissive -fno-exceptions -fno-threadsafe-statics"
ARDUINO_FLAGS="-mmcu=$MCU -DF_CPU=16000000L"

needs_rebuild() {
    target=$1
    shift
    for source in $@
    do [ "$target" -ot "$source" ] && return 0
    done
    return 1
}

arduino_core_source="$ARDUINO_CORE_PATH/*.S $ARDUINO_CORE_PATH/*.c $ARDUINO_CORE_PATH/*.cpp"
needs_rebuild core.a $arduino_core_source && {
    echo 'building arduino core.'
    avr-g++ $CXXFLAGS $INCLUDES $ARDUINO_FLAGS -c $arduino_core_source
    avr-gcc-ar rcs core.a *.o
    rm *.o
}
needs_rebuild sketch.hex sketch.cpp core.a && {
    echo 'building sketch.'
    avr-g++ $CXXFLAGS $INCLUDES $ARDUINO_FLAGS -Wl,--gc-sections -o sketch.elf sketch.cpp core.a
    objcopy -O ihex sketch.elf sketch.hex
}
echo 'build complete.'

[ "$1" != "upload" ] && exit

get_com_ports() {
    for tty in $(ls /dev/ttyS*)
    do
        echo com$((${tty#/dev/ttyS}+1))
        [ "$1" != "all" ] && exit
    done
}

port=$(get_com_ports)
[ "$port" ] && avrdude -v -V -p$MCU -curclock -P$port -b115200 -D -Uflash:w:sketch.hex

