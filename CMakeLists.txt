cmake_minimum_required(VERSION 3.16)

if(NOT EXISTS "$ENV{ZOS_PATH}/cmake/zos_init.cmake")
    message(FATAL_ERROR "Set ZOS_PATH to a current Zeal-8-bit-OS checkout.")
endif()

set(ZOS_TOOLCHAIN z88dk)
include("$ENV{ZOS_PATH}/cmake/zos_init.cmake")

project(bbcbasic ASM)

add_executable(bbcbasic
    src/main.asm
    src/exec.asm
    src/eval.asm
    src/fpp.asm
    src/hardware.asm
    src/zos.asm
    src/ram.asm
)

# CMake does not scan z80asm INCLUDE directives for dependencies.
set(zos_sdk_dir "$ENV{ZOS_PATH}/sdk/z88dk-z80asm")
set_source_files_properties(src/hardware.asm PROPERTIES
    OBJECT_DEPENDS "${CMAKE_SOURCE_DIR}/src/zos_syscall.asm;${zos_sdk_dir}/zos_sys.asm;${zos_sdk_dir}/zos_video.asm"
)
set_source_files_properties(src/zos.asm PROPERTIES
    OBJECT_DEPENDS "${CMAKE_SOURCE_DIR}/src/zos_syscall.asm;${zos_sdk_dir}/zos_sys.asm;${zos_sdk_dir}/zos_keyboard.asm"
)

target_link_options(bbcbasic PRIVATE -m)
set_property(TARGET bbcbasic APPEND PROPERTY ADDITIONAL_CLEAN_FILES
    "$<TARGET_FILE_DIR:bbcbasic>/bbcbasic.map"
)
zos_add_outputs(bbcbasic)
