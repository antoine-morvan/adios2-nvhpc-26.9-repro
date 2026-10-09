#!/usr/bin/env bash
set -e -u -o pipefail

##################################################################################
## Settings
##################################################################################

OPENMPI_VERSION=5.0.11

NVHPC_VERSION=26.9

REPRO_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
mkdir -p "${REPRO_SCRIPT_DIR}/downloads"

##################################################################################
## Compiler
##################################################################################

OPENMPI_EXTRA_CONFIGURE_FLAGS=()
case ${1:-nvhpc} in
    gcc)
        # use system gcc
        export CC=gcc
        export CXX=g++
        export FC=gfortran
        CC_VERSION=$(gcc -dumpfullversion -dumpversion)
        ;;
    nvhpc)
        (type -f module &> /dev/null) || { echo "error: missing 'module' command" ; exit 1 ; }
        # install nvhpc
        NVHPC_LONGVERSION=20${NVHPC_VERSION%.*}_${NVHPC_VERSION/./}
        CUDA_VERSION=multi

        NVHPC_DIR=nvhpc_${NVHPC_LONGVERSION}_Linux_$(uname -m)_cuda_${CUDA_VERSION}
        NVHPC_ARCHIVE=${NVHPC_DIR}.tar.gz
        NVHPC_URL=https://developer.download.nvidia.com/hpc-sdk/${NVHPC_VERSION}/${NVHPC_ARCHIVE}

        [ ! -f "${REPRO_SCRIPT_DIR}/downloads/${NVHPC_ARCHIVE}" ] && curl -L -o "${REPRO_SCRIPT_DIR}/downloads/${NVHPC_ARCHIVE}" "${NVHPC_URL}"
        [ ! -d "${NVHPC_DIR}" ] && (cd "${REPRO_SCRIPT_DIR}" && tar xf "${REPRO_SCRIPT_DIR}/downloads/${NVHPC_ARCHIVE}")

        NVHPC_PREFIX_DIR="$(readlink -f "${REPRO_SCRIPT_DIR}/${NVHPC_DIR}.prefix")"
        NVHPC_REAL_PREFIX_DIR="${NVHPC_PREFIX_DIR}/$(uname -s)_$(uname -m)/${NVHPC_VERSION}"
        [ ! -x "${NVHPC_REAL_PREFIX_DIR}/compilers/bin/nvfortran" ] && (
            export NVHPC_SILENT=true
            export NVHPC_INSTALL_TYPE=auto
            export NVHPC_INSTALL_DIR="${NVHPC_PREFIX_DIR}"
            "${NVHPC_DIR}/install"
        )
        module use "${NVHPC_PREFIX_DIR}/modulefiles"
        module load nvhpc-nompi

        # module already sets these
        # export CC=nvcc
        # export CXX=nvc++
        # export FC=nvfortran

        CC_VERSION="${NVHPC_VERSION}"
        ;;
    *) echo "ERROR: unsupported compiler '$1'" ; exit 1 ;;
esac

set -x
$CC --version
$CXX --version
$FC --version
set +x

##################################################################################
## Open MPI
##################################################################################
echo " -- Open MPI"
OPENMPI_DIR=openmpi-${OPENMPI_VERSION}
OPENMPI_ARCHIVE=${OPENMPI_DIR}.tar.bz2
OPENMPI_URL=https://download.open-mpi.org/release/open-mpi/v${OPENMPI_VERSION%.*}/${OPENMPI_ARCHIVE}

[ ! -f "${REPRO_SCRIPT_DIR}/downloads/${OPENMPI_ARCHIVE}" ] && curl -L -o "${REPRO_SCRIPT_DIR}/downloads/${OPENMPI_ARCHIVE}" "${OPENMPI_URL}"
[ ! -d "${OPENMPI_DIR}" ] && (cd "${REPRO_SCRIPT_DIR}" && tar xf "${REPRO_SCRIPT_DIR}/downloads/${OPENMPI_ARCHIVE}")

SOURCE_DIR="${REPRO_SCRIPT_DIR}/${OPENMPI_DIR}"
BUILD_DIR="${REPRO_SCRIPT_DIR}/${OPENMPI_DIR}.$(basename "${CC}")-${CC_VERSION}.build"
OPENMPI_PREFIX="${REPRO_SCRIPT_DIR}/${OPENMPI_DIR}.$(basename "${CC}")-${CC_VERSION}.prefix"

[ ! -x "${OPENMPI_PREFIX}/bin/mpiexec" ] && (
    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"
    [ ! -f Makefile ] && "${SOURCE_DIR}/configure" \
        --prefix="${OPENMPI_PREFIX}" \
        --enable-shared \
        --enable-mpi-fortran \
        --enable-wrapper-rpath=yes \
        --enable-wrapper-runpath=no \
        --disable-mpi1-compatibility \
        --enable-prte-prefix-by-default \
        --with-libnl=no \
        --with-portals4=no \
        --without-rocm \
        --without-cuda \
        --with-libevent=internal \
        --with-hwloc=internal \
        --with-pmix=internal \
        --without-hcoll \
        --without-lustre \
        --without-knem \
        --without-xpmem \
        --without-gpfs \
        --without-libfabric \
        --without-ucx \
        --without-ucc \
        --with-cma
    set +e
    make -j $(nproc)
    res=$?
    if [ $res != 0 ]; then
        echo ""
        echo " ----- make -j1 -----"
        echo ""
        make -j1 V=1 VERBOSE=1
        echo ""
        echo " ----- exit $res -----"
        echo ""
        exit $res
    fi
    set -e
    make install
)

export MPI_ROOT="${OPENMPI_PREFIX}"
export MPI_HOME="${OPENMPI_PREFIX}"
export MPI_DIR="${OPENMPI_PREFIX}"
export OPENMPI_ROOT="${OPENMPI_PREFIX}"
export OPENMPI_HOME="${OPENMPI_PREFIX}"
export OPAL_PREFIX="${OPENMPI_PREFIX}"

export PATH="${OPENMPI_PREFIX}/bin:${PATH}"
export LIBRARY_PATH="${OPENMPI_PREFIX}/lib${LIBRARY_PATH:+:${LIBRARY_PATH}}"
export LD_LIBRARY_PATH="${OPENMPI_PREFIX}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export CPATH="${OPENMPI_PREFIX}/include${CPATH:+:${CPATH}}"

export MPI_BIN="${OPENMPI_PREFIX}/bin"
export MPI_LIB="${OPENMPI_PREFIX}/lib"
export MPI_INC="${OPENMPI_PREFIX}/include"

export PKG_CONFIG_PATH="${OPENMPI_PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
export CMAKE_PREFIX_PATH="${OPENMPI_PREFIX}${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"

export MPICC=mpicc
export MPICXX=mpicxx
export MPIFC=mpifort

export MPI_C_COMPILER=mpicc
export MPI_CXX_COMPILER=mpicxx
export MPI_Fortran_COMPILER=mpifort

export OMPI_CC=${CC}
export OMPI_CXX=${CXX}
export OMPI_FC=${FC}
export OMPI_F90=${FC}
export OMPI_F77=${FC}

##################################################################################
## Adios2
##################################################################################

ADIOS2_VERSION="2.12.1"
ADIOS2_ARCHIVE=adios2-${ADIOS2_VERSION}.tar.gz
ADIOS2_DIR=ADIOS2-${ADIOS2_VERSION}
ADIOS2_URL=https://github.com/ornladios/ADIOS2/archive/refs/tags/v${ADIOS2_VERSION}.tar.gz

[ ! -f "${REPRO_SCRIPT_DIR}/downloads/${ADIOS2_ARCHIVE}" ] && curl -L -o "${REPRO_SCRIPT_DIR}/downloads/${ADIOS2_ARCHIVE}" "${ADIOS2_URL}"
[ ! -d "${ADIOS2_DIR}" ] && (cd "${REPRO_SCRIPT_DIR}" && tar xf "${REPRO_SCRIPT_DIR}/downloads/${ADIOS2_ARCHIVE}")

SOURCE_DIR="${REPRO_SCRIPT_DIR}/${ADIOS2_DIR}"
BUILD_DIR="${REPRO_SCRIPT_DIR}/${ADIOS2_DIR}.$(basename "${CC}")-${CC_VERSION}.build"
PREFIX_DIR="${REPRO_SCRIPT_DIR}/${ADIOS2_DIR}.$(basename "${CC}")-${CC_VERSION}.prefix"
(
    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"

    export CC=${MPICC}
    export CXX=${MPICXX}
    export FC=${MPIFC}

    [ ! -f Makefile ] && cmake \
        -Wno-dev \
        -G 'Unix Makefiles' \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${PREFIX_DIR}" \
        -DBUILD_SHARED_LIBS=ON \
        \
        -DADIOS2_USE_MPI=ON \
        -DADIOS2_USE_HDF5=OFF \
        -DADIOS2_USE_Fortran=ON \
        -DADIOS2_USE_BZip2=OFF \
        \
        -DADIOS2_BUILD_EXAMPLES=OFF \
        -DBUILD_TESTING=OFF \
        -DADIOS2_USE_Python=OFF \
        -DADIOS2_USE_PIP=OFF \
        \
        "${SOURCE_DIR}"

    set +e
    make -j $(nproc)
    RES=$?
    if [ $RES != 0 ]; then
        echo ""
        echo "----- make -j1 -----"
        echo ""
        make -j1
        echo ""
        echo "----- exit $RES -----"
        echo ""
        exit $RES
    fi
    set -e
    # make install
)

##################################################################################
## Exit
##################################################################################
exit 0
