#!/bin/sh
set -e

needs_rebuild() {
    target=$1
    shift
    for source in $@
    do
        [ "$target" -ot "$source" ] && return 0
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
BOOTLOADER_ADDR=0x1000
EXTRA_FLAGS="-DARDUINO_USB_CDC_ON_BOOT=0"

ARDUINO_PLATFORM_PATH=./arduino-esp32
ARDUINO_CORE_PATH=$ARDUINO_PLATFORM_PATH/cores/esp32

#ARDUINO_PLATFORM_PATH="$LOCALAPPDATA/Arduino15/packages/esp32"
#ARDUINO_CORE_PATH="$ARDUINO_PLATFORM_PATH/hardware/esp32/2.0.14/cores/esp32"

TOOL_PATH=$ARDUINO_PLATFORM_PATH/tools
ESP32_ARDUINO_LIBS_PATH=$TOOL_PATH/esp32-arduino-libs/$MCU
COMPILER_PREFIX=${TARCH}-${MCU}-elf
COMPILER_PATH=$TOOL_PATH/$COMPILER_PREFIX/bin

CC=$COMPILER_PATH/$COMPILER_PREFIX-gcc
CXX=$COMPILER_PATH/$COMPILER_PREFIX-g++
AR=$COMPILER_PATH/$COMPILER_PREFIX-gcc-ar
ESP_TOOL=$TOOL_PATH/esptool/esptool
GEN_ESP32PART=$TOOL_PATH/gen_esp32part

cpreprocessor_flags="
  $(<$ESP32_ARDUINO_LIBS_PATH/flags/defines)
  -iprefix $ESP32_ARDUINO_LIBS_PATH/include/
  $(<$ESP32_ARDUINO_LIBS_PATH/flags/includes)
  -I$ESP32_ARDUINO_LIBS_PATH/${BOOT}_qspi/include
"
c_flags=$(<$ESP32_ARDUINO_LIBS_PATH/flags/c_flags)
cpp_flags=$(<$ESP32_ARDUINO_LIBS_PATH/flags/cpp_flags)
arduino_flags="
  -DF_CPU=$F_CPU
  -DARDUINO_ARCH_${TARCH}
  -DARDUINO_BOARD=\"${BOARD}\"
  -DARDUINO_VARIANT=\"${VARIANT}\"
  -DARDUINO_PARTITION_${PARTITIONS}
  -DESP32
  $EXTRA_FLAGS
"
includes="-I$ARDUINO_CORE_PATH -I$ARDUINO_PLATFORM_PATH/variants/${VARIANT}"

common_args="$arduino_flags $cpreprocessor_flags $includes -Os -Wall -Wextra -I$PWD"

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

if needs_rebuild sketch.bootloader.bin build-esp32.sh
then
  echo 'Building bootloader.'
  $ESP_TOOL \
    --chip $MCU elf2image \
    --flash_mode $FLASH_MODE \
    --flash_freq $FLASH_FREQ \
    --flash_size $FLASH_SIZE \
    -o "sketch.bootloader.bin" \
    "$ESP32_ARDUINO_LIBS_PATH/bin/bootloader_${BOOT}_${FLASH_FREQ}.elf" &
fi

if needs_rebuild sketch.partitions.bin build-esp32.sh
then
  echo 'Generating partition.'
  $GEN_ESP32PART -q "$TOOL_PATH/partitions/${PARTITIONS}.csv" sketch.partitions.bin &
fi

if needs_rebuild sketch.o sketch.cpp
then
  echo 'Building sketch.'
  parallel_command "$CXX $cpp_flags $common_args -DARDUINO_CORE_BUILD -c" sketch.cpp
fi

wait

echo "Building image."
if needs_rebuild sketch.bin core.a sketch.o sketch.bootloader.bin sketch.partitions.bin
then
  echo 'Linking program.'

  elf_flags="
    $(<$ESP32_ARDUINO_LIBS_PATH/flags/ld_flags)
    $(<$ESP32_ARDUINO_LIBS_PATH/flags/ld_scripts)
    -Wl,--Map=./sketch.map -L$ESP32_ARDUINO_LIBS_PATH/lib
    -L$ESP32_ARDUINO_LIBS_PATH/ld
    -L$ESP32_ARDUINO_LIBS_PATH/${BOOT}_qspi
    -Wl,--wrap=esp_panic_handler
  "
  $CXX $cpp_flags $common_args $elf_flags \
    -Wl,--start-group core.a sketch.o $(<$ESP32_ARDUINO_LIBS_PATH/flags/ld_libs) \
    -Wl,--end-group \
    -Wl,-EL \
    -o sketch.elf

  echo 'Creating image.'
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

SKETCH_ARGS="
  $BOOTLOADER_ADDR sketch.bootloader.bin
  0x8000 sketch.partitions.bin
  0xe000 $TOOL_PATH/partitions/boot_app0.bin
"
SKETCH_ARGS=

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
  --flash_size keep \
  $SKETCH_ARGS \
  0x10000 sketch.bin

