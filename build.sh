#!/bin/sh

needs_rebuild() {
    target=$1; shift
    for source in $@; do
        [ "$target" -ot "$source" ] && return 0
    done
    return 1
}

log() {
    >&2 echo "$@"
}

build_file() {
    build_cmd=$1; file=$2
    log "Building file: $file"
    $build_cmd $file
}

build_library() {
    lib_path=$(realpath "$1")

    c_files=$(find "$lib_path" -name '*.c' -o -name '*.S')
    cpp_files=$(find "$lib_path" -name '*.cpp')

    if [ "$2" ]; then
        archive_file="$2.a"
    else
        mkdir -pv "$cache_dir"
        set -- $(echo -n "$lib_path" | md5sum)
        archive_file="$cache_dir/$1.a"
    fi

    log "Building library from path: $lib_path"
    if ! needs_rebuild "$archive_file" $c_files $cpp_files; then
        log "Using cached file: $archive_file"
        return
    fi

    cwd="$PWD"
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir"

    for file in $c_files; do
        build_file "$cc $common_flags $c_flags -I$lib_path -c" $file &
    done
    for file in $cpp_files; do
        build_file "$cxx $common_flags $cxx_flags -I$lib_path -c" $file &
    done
    wait

    cd "$cwd"
    log "Creating archive: $archive_file"
    $ar qcs "$archive_file" "$tmp_dir"/*.o
    rm -r "$tmp_dir"
}

get_com_ports() {
    for tty in $(ls /dev/ttyS*)
    do
        echo com$((${tty#/dev/ttyS}+1))
        [ "$1" != "all" ] && exit
    done
}

clean_cmd() {
    rm -vr "$cache_dir" || true
    rm -v *.elf *.hex *.a 2>/dev/null || true
}

size_cmd() {
    $avr_size -A "$sketch_name.elf"
}

usage() {
    log "\
Usage: $0 <command> ...
Commands:
    build [sketch_name]
    clean
    rebuild [sketch_name]
    upload ...
"
    exit
}

set -e

[ "$cache_dir" ] || cache_dir="lib_cache"

case "$1" in
build) ;;
clean)
    log "INFO: running clean"
    clean_cmd
    exit
    ;;
rebuild)
    log "INFO: rebuild"
    clean_cmd
    ;;
upload)
    need_upload=true
    ;;
*)
    usage
    ;;
esac

log "INFO: running build"
if [ "$2" ]; then
    [ -f "$2.cpp" ] || {
        log "ERROR: file $2.cpp not exist."
        usage
    }
    sketch_name="$2"
else
    sketch_name="sketch"
fi

arduino_ide_path="$LOCALAPPDATA/Arduino15"

if [ -d "$arduino_ide_path" ]; then
    log "INFO: Arduino IDE installation detected"

    avr_toolchain_install_dir="$arduino_ide_path/packages/arduino/tools/avr-gcc"
    avr_toolchain_installs=$(ls "$avr_toolchain_install_dir")
    set -- $avr_toolchain_installs; avr_toolchain_install=$1
    avr_toolchain_path="$avr_toolchain_install_dir/$avr_toolchain_install/bin"

    avrdude_install_dir="$arduino_ide_path/packages/arduino/tools/avrdude"
    avrdude_installs=$(ls "$avrdude_install_dir")
    set -- $avrdude_installs; avrdude_install=$1
    avrdude_path="$avrdude_install_dir/$avrdude_install/bin"

    ide_library_path="$arduino_ide_path/libraries"
    ide_core_path="$arduino_ide_path/packages/arduino/hardware/avr/1.8.6"
    core_name="arduino"
fi

# avr_toolchain_path="/d/opt/avr8-gnu-toolchain-win32_x86_64/bin"
avrdude_path="/d/opt/avrdude-v7.2-windows-x64"

log "Avr Tool Chain Path: $avr_toolchain_path"
log "Avrdude Path: $avrdude_path"

cc="$avr_toolchain_path/avr-gcc"
[ -x $cc ] || {
    log "ERROR: 'cc' command is not avaliable"
    exit
}

cxx="$avr_toolchain_path/avr-g++"
[ -x $cxx ] || {
    log "ERROR: 'cxx' command is not avaliable"
    exit
}

ar="$avr_toolchain_path/avr-gcc-ar"
[ -x $ar ] || {
    log "ERROR: 'ar' command is not avaliable"
    exit
}

objcopy="$avr_toolchain_path/avr-objcopy"
[ -x $objcopy ] || {
    log "ERROR: 'objcopy' command is not avaliable"
    exit
}

avr_size="$avr_toolchain_path/avr-size"
[ -x $avr_size ] || {
    log "ERROR: 'avr-size' command is not avaliable"
    exit
}

avrdude="$avrdude_path/avrdude"
[ -x $avrdude ] || {
    log "ERROR: 'avrdude' command is not avaliable"
    exit
}

mini_core_path=$(realpath "./MiniCore/avr")
core_name="MCUdude_corefiles"

core_path=$mini_core_path
arduino_core_path="$core_path/cores/$core_name"

mcu="atmega328p"

common_flags="
    -Wall -Wextra
    -DARDUINO_ARCH_AVR
    -I$arduino_core_path
    -I$core_path/variants/standard -mmcu=$mcu -DF_CPU=16000000L
"
c_flags="-Os -ffunction-sections -fdata-sections -flto"
cxx_flags="$c_flags -fpermissive -fno-exceptions -fno-threadsafe-statics"

includes="
  $(awk -F[\<\>] '/#include/{print $2}' "$sketch_name.cpp")
  $(awk -F\" '/#include/{print $2}' "$sketch_name.cpp")
"
lib_dirs=""
library_include_flags=""
for include_filename in $includes; do
    [ "$include_filename" = "Arduino.h" ] && continue

    set -- $(find "$core_path/libraries" "$ide_library_path" -name "$include_filename")
    [ "$1" ] || {
        log "ERROR: no matching library found for file: $include_filename"
        exit
    }
    dir=$(dirname "$1")
    log "include file '$include_filename' found in path: $dir"
    lib_dirs="$lib_dirs $dir"
    lib_include_flags="$lib_include_flags -I$dir"
    build_library "$dir" &
done

log "Building Arduino core"
build_library "$arduino_core_path" "arduino_core"
wait

echo "Linking program: $sketch_name.hex"
if needs_rebuild "$sketch_name.hex" "$sketch_name.cpp"
then
    $cxx \
        $common_flags $cxx_flags $lib_include_flags \
        -Wl,--gc-sections \
        -o "$sketch_name.elf" \
        "$sketch_name.cpp" \
        $([ -d "$cache_dir" ] && find "$cache_dir" -name '*.a') \
        arduino_core.a

    $objcopy -O ihex "$sketch_name.elf" "$sketch_name.hex"
fi

size_cmd

[ "$need_upload" = true ] && {
    port=$(get_com_ports)
    echo "uploading: mcu - $mcu, port - $port"
    set -x
    [ "$port" ] && $avrdude -v -V -p$mcu -curclock -P$port -b115200 -D -Uflash:w:"$sketch_name.hex"
}

