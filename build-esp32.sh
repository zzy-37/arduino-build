#!/bin/sh
set -e

needs_rebuild() {
    target=$1
    shift
    for source in $@
    do [ "$target" -ot "$source" ] && return 0
    done
    return 1
}

parallel_command() {
    cmd=$1
    shift
    for file in $@
    do
        echo "Build file: $file"
        $cmd $file &
    done
}

get_com_ports() {
    for tty in $(ls /dev/ttyS*)
    do
        echo com$((${tty#/dev/ttyS}+1))
        [ "$1" != "all" ] && exit
    done
}

ARDUINO_PLATFORM_PATH=./arduino-esp32

MCU=esp32 # esp32c3 esp32c6 esp32h2 esp32s2 esp32s3
FLASH_MODE=dio # qio
FLASH_FREQ=80m
FLASH_SIZE=4MB
BOOT=qio
TARCH=xtensa # riscv32
F_CPU=240000000L
BOARD=ESP32_DEV
VARIANT=esp32
PARTITIONS=default
EXTRA_FLAGS="-DARDUINO_USB_CDC_ON_BOOT=0"

TOOL_PATH=$ARDUINO_PLATFORM_PATH/tools
ESP32_ARDUINO_LIBS_PATH=$TOOL_PATH/esp32-arduino-libs/$MCU
COMPILER_PREFIX=${TARCH}-${MCU}-elf
COMPILER_PATH=$TOOL_PATH/$COMPILER_PREFIX/bin
CC=$COMPILER_PATH/$COMPILER_PREFIX-gcc
CXX=$COMPILER_PATH/$COMPILER_PREFIX-g++
AR=$COMPILER_PATH/$COMPILER_PREFIX-gcc-ar
ESP_TOOL=$TOOL_PATH/esptool/esptool

ARDUINO_CORE_PATH=$ARDUINO_PLATFORM_PATH/cores/esp32

cpreprocessor_flags="\
    $(<$ESP32_ARDUINO_LIBS_PATH/flags/defines) \
    -iprefix $ESP32_ARDUINO_LIBS_PATH/include/ \
    $(<$ESP32_ARDUINO_LIBS_PATH/flags/includes) \
    -I$ESP32_ARDUINO_LIBS_PATH/${BOOT}_qspi/include \
"
c_flags=$(<$ESP32_ARDUINO_LIBS_PATH/flags/c_flags)
cpp_flags=$(<$ESP32_ARDUINO_LIBS_PATH/flags/cpp_flags)
arduino_flags="\
    -DF_CPU=$F_CPU \
    -DARDUINO_ARCH_${TARCH} \
    -DARDUINO_BOARD=\"${BOARD}\" \
    -DARDUINO_VARIANT=\"${VARIANT}\" \
    -DARDUINO_PARTITION_${PARTITIONS} \
    -DESP32 \
    $EXTRA_FLAGS
"
includes="-I$ARDUINO_CORE_PATH -I$ARDUINO_PLATFORM_PATH/variants/${VARIANT}"

common_args="$arduino_flags $cpreprocessor_flags $includes -Os -Wall -Wextra"

echo 'Building arduino core.'
if needs_rebuild core.a $ARDUINO_CORE_PATH/*.c $ARDUINO_CORE_PATH/*.cpp
then
    parallel_command "$CC  $c_flags   $common_args -DARDUINO_CORE_BUILD -c" $ARDUINO_CORE_PATH/*.c
    parallel_command "$CXX $cpp_flags $common_args -DARDUINO_CORE_BUILD -c" $ARDUINO_CORE_PATH/*.cpp
    wait
    $AR rc core.a *.o
    rm *.o
else
    echo "No need to rebuild"
fi

elf_flags="\
    $(<$ESP32_ARDUINO_LIBS_PATH/flags/ld_flags) \
    $(<$ESP32_ARDUINO_LIBS_PATH/flags/ld_scripts) \
    -Wl,--Map=./sketch.map -L$ESP32_ARDUINO_LIBS_PATH/lib \
    -L$ESP32_ARDUINO_LIBS_PATH/ld \
    -L$ESP32_ARDUINO_LIBS_PATH/${BOOT}_qspi \
    -Wl,--wrap=esp_panic_handler
"
echo "Building image."
if needs_rebuild sketch.bin core.a sketch.cpp
then
    $CXX $cpp_flags $common_args $elf_flags \
        -Wl,--start-group core.a sketch.cpp $(<$ESP32_ARDUINO_LIBS_PATH/flags/ld_libs) \
        -Wl,--end-group \
        -Wl,-EL \
        -o sketch.elf

    $ESP_TOOL \
        --chip $MCU elf2image \
        --flash_mode "$FLASH_MODE" \
        --flash_freq "$FLASH_FREQ" \
        --flash_size "$FLASH_SIZE" \
        --elf-sha256-offset 0xb0 \
        -o sketch.bin sketch.elf

    rm -v sketch.map
else
    echo "No need to rebuild."
fi

[ "$1" != "upload" ] && exit
#upload speeds: 921600 921600 115200 115200 256000 256000 230400 230400 230400 460800 460800 460800 512000 512000
port=$(get_com_ports)
$ESP_TOOL \
    --chip $MCU \
    --port "$port" \
    --baud 921600 \
    $UPLOAD_FLAGS \
    --before default_reset \
    --after hard_reset write_flash \
    -z \
    --flash_mode keep \
    --flash_freq keep \
    --flash_size keep 0x10000 \
    sketch.bin

