cmake_minimum_required(VERSION 3.0)

###################################################################

if (NOT DEFINED ENV{OPENORBIS})
    set(OPENORBIS /opt/pacbrew/ps4/openorbis)
    set(ENV{OPENORBIS} ${OPENORBIS})
else ()
    set(OPENORBIS $ENV{OPENORBIS})
endif ()

if (NOT DEFINED ENV{OO_PS4_TOOLCHAIN})
    set(OO_PS4_TOOLCHAIN /opt/pacbrew/ps4/openorbis)
else ()
    set(OO_PS4_TOOLCHAIN $ENV{OO_PS4_TOOLCHAIN})
endif ()

list(APPEND CMAKE_MODULE_PATH "${OPENORBIS}/cmake")

set(PS4 TRUE)

set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(TARGET x86_64-pc-freebsd-elf)
set(CMAKE_SYSTEM_VERSION 12)
set(CMAKE_CROSSCOMPILING 1)

set(CMAKE_ASM_COMPILER ${OPENORBIS}/bin/clang CACHE PATH "")
set(CMAKE_C_COMPILER ${OPENORBIS}/bin/clang CACHE PATH "")
set(CMAKE_CXX_COMPILER ${OPENORBIS}/bin/clang++ CACHE PATH "")
set(CMAKE_LINKER ${OPENORBIS}/bin/ld.lld CACHE PATH "")
set(CMAKE_AR ${OPENORBIS}/bin/llvm-ar CACHE PATH "")
set(CMAKE_RANLIB ${OPENORBIS}/bin/llvm-ranlib CACHE PATH "")
set(CMAKE_STRIP ${OPENORBIS}/bin/llvm-strip CACHE PATH "")

# We use the linker directly instead of using the llvm wrapper.
# CMake uses `-Xlinker` for passing llvm linker flags
# added via `add_link_options(... "LINKER:...")`.
# Force the correct linker flag generation:
macro(reset_linker_wrapper_flag)
    set(CMAKE_ASM_LINKER_WRAPPER_FLAG "")
    set(CMAKE_C_LINKER_WRAPPER_FLAG "")
    set(CMAKE_CXX_LINKER_WRAPPER_FLAG "")
endmacro()
variable_watch(CMAKE_ASM_LINKER_FLAG reset_linker_wrapper_flag)
variable_watch(CMAKE_C_LINKER_WRAPPER_FLAG reset_linker_wrapper_flag)
variable_watch(CMAKE_CXX_LINKER_WRAPPER_FLAG reset_linker_wrapper_flag)

set(CMAKE_LIBRARY_ARCHITECTURE x86_64 CACHE INTERNAL "abi")

set(CMAKE_FIND_ROOT_PATH ${OPENORBIS} ${OPENORBIS}/usr)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

set(BUILD_SHARED_LIBS OFF CACHE INTERNAL "Shared libs not available")

###################################################################

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(CMAKE_ASM_FLAGS_INIT
  "-target x86_64-pc-freebsd12-elf \
   -D__PS4__ -D__OPENORBIS__ -D__ORBIS__ \
   -DPS4 -D__BSD_VISIBLE -D_BSD_SOURCE \
   -fPIC -funwind-tables \
   -isysroot ${OPENORBIS} -isystem ${OPENORBIS}/include \
   -I${OPENORBIS}/usr/include")

set(CMAKE_C_FLAGS_INIT "${CMAKE_ASM_FLAGS_INIT}")
set(CMAKE_CXX_FLAGS_INIT "${CMAKE_C_FLAGS_INIT} -I${OPENORBIS}/include/c++/v1")

set(CMAKE_C_STANDARD_LIBRARIES "-lkernel -lc -lclang_rt.builtins-x86_64 -lSceLibcInternal")
set(CMAKE_CXX_STANDARD_LIBRARIES "${CMAKE_C_STANDARD_LIBRARIES} -lc++")

set(CMAKE_EXE_LINKER_FLAGS_INIT
  "-m elf_x86_64 -pie --eh-frame-hdr \
   --script ${OPENORBIS}/link.x \
   -L${OPENORBIS}/lib -L${OPENORBIS}/usr/lib")

# crt1.o may be already added to LDFLAGS from "ps4vars.sh", so remove LDFLAGS env (todo: find a better way...)
set(ENV{LDFLAGS} "" CACHE STRING FORCE)

set(CMAKE_ASM_LINK_EXECUTABLE
  "<CMAKE_LINKER> -o <TARGET> <CMAKE_ASM_LINK_FLAGS> <LINK_FLAGS> --start-group \
   <OBJECTS> <LINK_LIBRARIES> --end-group")

set(CMAKE_C_LINK_EXECUTABLE
  "<CMAKE_LINKER> -o <TARGET> <CMAKE_C_LINK_FLAGS> <LINK_FLAGS> \
  --start-group \
     ${OPENORBIS}/lib/crt1.o ${OPENORBIS}/lib/crti.o \
     <OBJECTS> <LINK_LIBRARIES> \
     ${OPENORBIS}/lib/crtn.o \
  --end-group")

set(CMAKE_CXX_LINK_EXECUTABLE
  "<CMAKE_LINKER> -o <TARGET> <CMAKE_CXX_LINK_FLAGS> <LINK_FLAGS> \
  --start-group \
     ${OPENORBIS}/lib/crt1.o ${OPENORBIS}/lib/crti.o \
     <OBJECTS> <LINK_LIBRARIES> \
     ${OPENORBIS}/lib/crtn.o \
  --end-group")

# Start find_package in config mode
set(CMAKE_FIND_PACKAGE_PREFER_CONFIG TRUE)

# Set pkg-config for the same
find_program(PKG_CONFIG_EXECUTABLE NAMES openorbis-pkg-config HINTS "${OPENORBIS}/usr/bin")
if (NOT PKG_CONFIG_EXECUTABLE)
    message(WARNING "Could not find openorbis-pkg-config: try installing ps4-openorbis-pkg-config")
endif ()

function(add_self project)
    set(AUTH_INFO "000000000000000000000000001C004000FF000000000080000000000000000000000000000000000000008000400040000000000000008000000000000000080040FFFF000000F000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")
    add_custom_command(
            OUTPUT "${project}.self"
            COMMAND ${CMAKE_COMMAND} -E env "OO_PS4_TOOLCHAIN=${OPENORBIS}" "${OPENORBIS}/bin/create-fself" "-in=${project}" "-out=${project}.oelf" "--eboot" "eboot.bin" "--paid" "0x3800000000000035" "--authinfo" "${AUTH_INFO}"
            VERBATIM
            DEPENDS "${project}"
    )
    add_custom_target(
            "${project}_self" ALL
            DEPENDS "${project}.self"
    )
endfunction()

function(add_pkg project pkgdir title-id title version)
    # Title must not exceed 128 characters
    string(SUBSTRING "${title}" 0 127 title)

    # Format version string in such a way that is acceptable by the PS4
    string(SUBSTRING "${version}" 0 7 verclean)
    string(REGEX MATCH "([0-9]+\\.[0-9]+)" verclean ${verclean})
    if("${verclean}" STREQUAL "")
        message(WARNING "The version string '${version}' is formatted in a way that is incompatable with the PS4, using '01.00'")
        set(verclean "01.00")
    endif()

    # Format content-id based on title-id and version
    string(REPLACE "." "0" vercont ${verclean})
    string(APPEND vercont "00000000")
    string(SUBSTRING "${vercont}" 0 7 vercont)
    set(content_id "IV0001-${title-id}_00-${title-id}${vercont}")
    # export pkg name for end user
    set(PKG_OUT_NAME "${content_id}.pkg" CACHE STRING "ps4 pkg name" FORCE)
  
    add_custom_command(
            OUTPUT "${project}.pkg"
            # copy required files to binary directory
            COMMAND ${CMAKE_COMMAND} -E copy eboot.bin ${pkgdir}/eboot.bin
            # generate sfo
            COMMAND "${OPENORBIS}/bin/linux/PkgTool.Core" sfo_new ${pkgdir}/sce_sys/param.sfo
            COMMAND "${OPENORBIS}/bin/linux/PkgTool.Core" sfo_setentry ${pkgdir}/sce_sys/param.sfo APP_TYPE --type Integer --maxsize 4 --value 1
            COMMAND "${OPENORBIS}/bin/linux/PkgTool.Core" sfo_setentry ${pkgdir}/sce_sys/param.sfo APP_VER --type Utf8 --maxsize 8 --value "${verclean}"
            COMMAND "${OPENORBIS}/bin/linux/PkgTool.Core" sfo_setentry ${pkgdir}/sce_sys/param.sfo ATTRIBUTE --type Integer --maxsize 4 --value 65536
            COMMAND "${OPENORBIS}/bin/linux/PkgTool.Core" sfo_setentry ${pkgdir}/sce_sys/param.sfo CATEGORY --type Utf8 --maxsize 4 --value "gde"
            COMMAND "${OPENORBIS}/bin/linux/PkgTool.Core" sfo_setentry ${pkgdir}/sce_sys/param.sfo FORMAT --type Utf8 --maxsize 4 --value "obs"
            COMMAND "${OPENORBIS}/bin/linux/PkgTool.Core" sfo_setentry ${pkgdir}/sce_sys/param.sfo CONTENT_ID --type Utf8 --maxsize 48 --value "${content_id}"
            COMMAND "${OPENORBIS}/bin/linux/PkgTool.Core" sfo_setentry ${pkgdir}/sce_sys/param.sfo DOWNLOAD_DATA_SIZE --type Integer --maxsize 4 --value 0
            COMMAND "${OPENORBIS}/bin/linux/PkgTool.Core" sfo_setentry ${pkgdir}/sce_sys/param.sfo SYSTEM_VER --type Integer --maxsize 4 --value 1020
            COMMAND "${OPENORBIS}/bin/linux/PkgTool.Core" sfo_setentry ${pkgdir}/sce_sys/param.sfo TITLE --type Utf8 --maxsize 128 --value "${title}"
            COMMAND "${OPENORBIS}/bin/linux/PkgTool.Core" sfo_setentry ${pkgdir}/sce_sys/param.sfo TITLE_ID --type Utf8 --maxsize 12 --value "${title-id}"
            COMMAND "${OPENORBIS}/bin/linux/PkgTool.Core" sfo_setentry ${pkgdir}/sce_sys/param.sfo VERSION --type Utf8 --maxsize 8 --value "${verclean}"
            # generate gp4 file
            COMMAND "${OPENORBIS}/bin/linux/create-gp4" -out ${pkgdir}/${project}.gp4 --content-id "${content_id}" --path "${pkgdir}"
            # generate pkg
            COMMAND cd ${pkgdir} && "${OPENORBIS}/bin/linux/PkgTool.Core" pkg_build ${project}.gp4 ${CMAKE_BINARY_DIR}
            # cleanup
            COMMAND ${CMAKE_COMMAND} -E remove ${pkgdir}/eboot.bin
            COMMAND ${CMAKE_COMMAND} -E remove ${pkgdir}/sce_sys/param.sfo
            COMMAND ${CMAKE_COMMAND} -E remove ${pkgdir}/${project}.gp4
            VERBATIM
            DEPENDS "${project}.self"
    )
    add_custom_target(
            "${project}_pkg" ALL
            DEPENDS "${project}.pkg"
    )
endfunction()

