#! /bin/sh

REPO_MANIFEST_SOURCE=https://github.com/akorb/manifest.git
REPO_PLATFORM=fvp.xml
REPO_VERSION=3.22.0-ftpm-ra

askContinue()
{
    printf "Continue? [y/N]: "
    read -r answer

    if [ "${answer}" != "y" ]; then
        printf "exiting\n"
        exit 0
    fi
}

printf "This will setup the whole software system (including FVP and OP-TEE) in the current directory.\n"
askContinue

. /etc/os-release

# Installing python2 is required because: https://github.com/OP-TEE/optee_os/issues/5936

if [ "${ID}" = "ubuntu" ]; then
    if [ "${VERSION_ID}" != "22.04" ]; then
        printf "For ubuntu, this script was only tested for version 22.04. You have %s.\n" "${VERSION}"
        askContinue
    fi
    sudo apt update && sudo apt full-upgrade -y
    sudo apt install -y \
    adb \
    acpica-tools \
    autoconf \
    automake \
    bc \
    bison \
    build-essential \
    ccache \
    cpio \
    cscope \
    curl \
    device-tree-compiler \
    e2tools \
    expect \
    fastboot \
    flex \
    ftp-upload \
    gdisk \
    git \
    libattr1-dev \
    libcap-ng-dev \
    libfdt-dev \
    libftdi-dev \
    libglib2.0-dev \
    libgmp3-dev \
    libhidapi-dev \
    libmpc-dev \
    libncurses5-dev \
    libpixman-1-dev \
    libslirp-dev \
    libssl-dev \
    libtool \
    libusb-1.0-0-dev \
    make \
    mtools \
    netcat \
    ninja-build \
    python2 \
    python3-cryptography \
    python3-pip \
    python3-pyelftools \
    python3-serial \
    python-is-python3 \
    repo \
    rsync \
    swig \
    unzip \
    uuid-dev \
    wget \
    xdg-utils \
    xterm \
    xz-utils \
    zlib1g-dev
elif [ "${ID}" = "manjaro" ]; then
    pamac upgrade --no-confirm
    pamac install --no-confirm mtools repo cpio acpica dtc xterm python-pyelftools python-cryptography ccache make autoconf automake bison flex unzip patch
    pamac build --no-confirm python2-bin
else
    echo "Unknown operating system"
    echo "Ensure you have installed the dependencies, see: https://optee.readthedocs.io/en/latest/building/prerequisites.html"
    askContinue
fi

wget 'https://developer.arm.com/-/media/Files/downloads/ecosystem-models/FVP_Base_RevC-2xAEMvA_11.23_9_Linux64.tgz?rev=9de951d16ad74096ad78e4be80df5114&hash=93BEA9D29D5360330D13FFF574CD6804' -O 'FVP_Base_RevC-2xAEMvA_11.23_9_Linux64.tgz'
tar -zxf FVP_Base_RevC-2xAEMvA_11.23_9_Linux64.tgz Base_RevC_AEMvA_pkg
rm FVP_Base_RevC-2xAEMvA_11.23_9_Linux64.tgz

wget 'https://developer.arm.com/-/media/Files/downloads/ecosystem-models/Foundation_Platform_11.23_9_Linux64.tgz?rev=9e3f3dd0452440c0bf1ccfa3cd4e90b5&hash=E2E23B0371FA468DFDDE827BA95C0594' -O 'Foundation_Platform_11.23_9_Linux64.tgz'
tar -zxf Foundation_Platform_11.23_9_Linux64.tgz Foundation_Platformpkg
rm Foundation_Platform_11.23_9_Linux64.tgz

repo init -u "${REPO_MANIFEST_SOURCE}" -m "${REPO_PLATFORM}" -b "${REPO_VERSION}"
repo sync -j4 --no-clone-bundle

if [ "${ID}" = "manjaro" ]; then
    # Fixes required because Manjaro has newer software than Ubuntu
    sed -i '/^LIBCURL_CONF_ENV += LD_LIBRARY_PATH/d' buildroot/package/libcurl/libcurl.mk
    sed -i '/^BUILD_CFLAGS = \-MD \-fshort\-wchar \-fno\-strict\-aliasing \-Wall \-Werror \-Wno\-deprecated\-declarations \-Wno\-stringop\-truncation \-Wno\-restrict \-Wno\-unused\-result \-nostdlib \-c \-g/ s/\r$/ -Wuse-after-free=0 -Wno-stringop-overflow -Wdangling-pointer=0\r/' edk2/BaseTools/Source/C/Makefiles/header.makefile
    rm buildroot/package/python-cryptography/python-cryptography.hash
fi

cd ms-tpm-20-ref || exit
git submodule init
git submodule update

cd ../build || exit
make -j2 toolchains

# Build everything
MEASURED_BOOT=y MEASURED_BOOT_FTPM=y CFG_ATTESTATION_PTA=y CFG_STACK_THREAD_EXTRA=8192 CFG_CORE_HEAP_SIZE=131072 make -j "$(nproc)"

mkdir -p shared_folder

# Run it
make FVP_USE_BASE_PLAT=y FVP_VIRTFS_ENABLE=y FVP_VIRTFS_HOST_DIR="$(realpath shared_folder)" run-only

# Mount the shared folder within FVP with:
# mount -t 9p -o trans=virtio,version=9p2000.L FM <mount point>
