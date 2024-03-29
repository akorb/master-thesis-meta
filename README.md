## Overview

This is the git repository describing how to set up and launch the demonstration.

## Launch the demonstration

### 1. Recommended environment

I tested the setup script on [Ubuntu 22.04.3 LTS (Jammy Jellyfish)](https://releases.ubuntu.com/jammy/) and [Manjaro](https://manjaro.org/download/) (on 19.01.2024).
Since Ubuntu is the officially supported operating system by OP-TEE, I recommend the former.
The simplest way is to set up a Ubuntu VM, e.g., with VirtualBox, and give it 35 GB of storage space.

### 2. Download & compile the source tree, and launch it within emulator

`cd` to the directory wherein you want to set up the source tree and execute:

```sh
wget 'https://github.com/akorb/master-thesis-meta/raw/main/setup.sh'
chmod +x setup.sh
./setup.sh
```

This script updates the system, installs dependencies, checks out the required repositories, builds them, and starts the Arm platform emulator [FVP](https://developer.arm.com/Tools%20and%20Software/Fixed%20Virtual%20Platforms) running Linux in the NW and OP-TEE OS in the SW.

If later you only want to launch FVP without rerunning the entire script, execute the following in the `build` folder:

```
make FVP_USE_BASE_PLAT=y FVP_VIRTFS_ENABLE=y FVP_VIRTFS_HOST_DIR="$(realpath shared_folder)" run-only
```

Either way, it should eventually look like the following:

![The three windows after launching FVP](/images/three_windows.png)

- Top: FVP dashboard
- Left: Normal world (Linux), interactive
- Right: Secure world (OP-TEE OS), only logs


### 3. Launch demonstration

Log in to the just opened Linux terminal by simply typing `root` (no password required).
And then, run the command `ra_demo`. It runs a `tmux` session. You can change between the two panes with `Ctrl+B`, `O` (standing for `O`ther).
Note: Release `Ctrl` before pressing `O`.

The terminal result should look like this:

![Screenshot of ra_demo](/images/ra_demo.png)

The verifier (`ra_verifier`) is already launched and waits for a prover (`ra_prover`) to connect.
The lower half of the terminal is waiting for you to hit Enter to spawn a prover.
Switch to the upper pane running the verifier to interactively accept or deny the prover.


## Repositories

Here, I want to show what repositories I modified or created to implement my solution. My changes are always in a branch called `3.22.0-ftpm-ra` branched from OP-TEE's [version 3.22.0](https://github.com/op-tee/manifest/tree/3.22.0).

[This file](https://github.com/akorb/manifest/blob/3.22.0-ftpm-ra/fvp.xml) contains references to all required repositories. It is used in `setup.sh`.

### [ms-tpm-20-ref](https://github.com/akorb/ms-tpm-20-ref)

#### Changes

* CDI is mocked
* Derive storage key and EPS from it
* Ask OP-TEE OS to create the EK cert of itself (the fTPM)
* Delete secrets as soon as they are no longer needed
* Add a command to return the whole certificate chain
* Encrypt data before storing, and decrypt it when loading it again
* Store EK cert, template, and nonce in the defined NV indices (as defined by the [TCG EK Credential Profile for TPM Family 2.0](https://trustedcomputinggroup.org/resource/http-trustedcomputinggroup-org-wp-content-uploads-tcg-ek-credential-profile-v-2-5-r2_published-pdf/))
* Some changes to the OP-TEE fTPM stub code (`Samples/ARM32-FirmwareTPM/optee_ta/fTPM`) to stay consistent with the function prototypes of the general fTPM code



#### Link to changes

https://github.com/akorb/ms-tpm-20-ref/compare/98b60a44aba79b15fcce1c0d1e46cf5918400f6a..3.22.0-ftpm-ra

___

### [optee_os](https://github.com/akorb/optee_os/)

#### Changes

I added the attestation of the firmware TPM.
This happens in [attestation.c](https://github.com/akorb/optee_os/compare/3.22.0..3.22.0-ftpm-ra#diff-24414f52059fe00212064e8346a9da29e5ca0d01b7cb9a8e3edd7acb7b4d8589).
Since the OP-TEE OS creates the EK cert now, I needed to activate some mbedtls modules to make this possible.
It also needs to be able to add the DICE-specific X.509 extension containing the fTPM's TCI into the EK cert. I added the code to create the data of this extension to the path `core/lib/alias_cert_extension`. This is the majority of the changes, even though the resulting files are mostly automatically generated. However, with some manual changes since the OP-TEE OS doesn't have a full C standard library.

#### Link to changes

https://github.com/akorb/optee_os/compare/3.22.0..3.22.0-ftpm-ra


___


### [ra_endpoints](https://github.com/akorb/ra_endpoints)

#### Changes

Written from scratch.
It contains code for two executables, the prover and the verifier. The verifier is a server waiting for a prover to connect to get verified.
The verifier retrieves information from the prover and represents it to the user. The user can interactively decide whether this information represents a trustworthy device.

___

### [alias_cert_extension](https://github.com/akorb/alias_cert_extension)

#### Changes

Written from scratch.
It contains the C code to create the data for the TCB Info Evidence X.509 extension defined in [DICE Attestation Architecture](https://trustedcomputinggroup.org/resource/dice-attestation-architecture/) (6.1.1).

The C code is copied at compile-time to where it is needed (ra_endpoints and dice_data_generator). However, I didn't get it to work for the [optee_os](https://github.com/akorb/optee_os/) repository, so I copied the code to it manually, duplicating it. Not nice, but it works.

___

### [dice_data_generator](https://github.com/akorb/dice_data_generator)

#### Changes

Written from scratch.
This repository is there to create mocked objects. That is the keys and the according certificates for the whole boot chain up to the EK cert (exclusive, since the EK cert is not mocked but created at runtime).
The resulting PEM certificates or keys are bundled into C header files and copied to where required.

* `cert_root.h` → ra_endpoints (to be able to verify the certificate chain)
* `cert_chain.h` → optee_os (to have access to the mocked certificates in the chain)
* `boot_chain_final_key.h` → optee_os (to be able to sign the EK certificate)

___

### [build](https://github.com/akorb/build)

#### Changes

This is the repository where the building starts.

* Add [ra_endpoints](https://github.com/akorb/ra_endpoints) to resulting Linux image
* Add [several executable scripts](https://github.com/akorb/build/tree/3.22.0-ftpm-ra/br-ext/board/fvp/overlay/usr/bin) to resulting Linux image which are convenient, most notably `ra_demo`, which starts a tmux session demonstrating my system. The other scripts load the fTPM's storage from the FVP guest to the host (into `./build/shared_folder`) or vice versa to make the data persistent between reboots. I used that for testing the fTPM between reboots, whether it keeps the data, and whether it is nicely reset when the identity of the fTPM changes.
* Integrate a much newer version of tpm2_tools because I needed some fixes


#### Link to changes

https://github.com/akorb/build/compare/3.22.0..3.22.0-ftpm-ra

___

### [linux](https://github.com/akorb/linux/tree/optee-3.22.0-ftpm-ra)

#### Changes

FVP has the Foundation and the Base image. The Base image has more features, e.g., it can mount a folder from the host directory. I wanted to use that to keep the fTPM's storage consistent.
But the Base image didn't work first at first when the fTPM support in the build system was activated. I got it to work; for that, I needed to copy some feature of the Base device tree to the Foundation device tree.
See [my comment](https://github.com/OP-TEE/optee_os/issues/6162#issuecomment-1637705809) for more details.

#### Link to changes

https://github.com/akorb/linux/compare/aed8040f4aca31a35b9fe9fe3c1f3e3867ea2188..optee-3.22.0-ftpm-ra
