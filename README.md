# Proxmox kernel for T2 Macs

Builds the Proxmox VE 9 kernel with the [t2linux](https://wiki.t2linux.org/) patches.
Made for a late 2018 Mac mini (Macmini8,1).

The result is a normal Proxmox kernel named `7.0.14-30-t2-pve`.
It adds T2 support: the `apple-bce` driver (audio, internal USB), fan control
through `applesmc`, Bluetooth, and the APFS driver.

## What is here

| File | What it does |
| --- | --- |
| `config.env` | Which Proxmox kernel and t2linux patch commits to use |
| `config-t2.opts` | Kernel options turned on for T2 hardware |
| `patches/` | Fixed copies of t2linux patches. A file here replaces the t2linux file with the same name |
| `build.sh` | Fetches sources, adds patches, builds `.deb` files into `out/` |
| `docker-build.sh` | Runs `build.sh` in a Debian trixie container |
| `.github/workflows/build.yml` | Builds on GitHub Actions and makes a release |

## Build

A kernel build takes 2 to 4 hours on 4 cores and needs about 30 GB of disk.
It must build on an x86_64 (amd64) machine.

**Option 1: GitHub Actions (best on an Apple Silicon Mac)**

1. Push this repo to GitHub.
2. Go to Actions, pick "Build kernel", press "Run workflow".
3. When it ends, the `.deb` files are on the Releases page.

**Option 2: On the Mac mini, after Proxmox is installed**

```sh
apt install git
git clone <this repo> && cd t2linux-proxmox
./build.sh
```

**Option 3: Any amd64 machine with Docker**

```sh
./docker-build.sh
```

### Quick patch check

To see if all patches apply, without a full build:

```sh
./docker-build.sh prepare
# On Apple Silicon, use the native arch so it is fast:
PLATFORM=linux/arm64 ./docker-build.sh prepare
```

## Install Proxmox on the Mac mini

1. Boot macOS Recovery (hold Cmd+R at power on).
2. Open Utilities > Startup Security Utility.
   - Secure Boot: **No Security**
   - External Boot: **Allow booting from external media**
3. Write the Proxmox VE 9 ISO to a USB stick.
4. Plug in a USB keyboard. Hold **Option** at power on and pick "EFI Boot".
5. Install Proxmox as usual. The stock kernel sees the internal SSD and Ethernet.

## Install the T2 kernel

Copy the kernel and headers `.deb` files to the Mac mini. Then:

```sh
apt install ./proxmox-kernel-7.0.14-30-t2-pve_*.deb ./proxmox-headers-7.0.14-30-t2-pve_*.deb
proxmox-boot-tool kernel pin 7.0.14-30-t2-pve
```

Only install those two. Skip `proxmox-kernel-7.0_*`, `proxmox-headers-7.0_*`
and `linux-tools-*`. Those share names with the stock Proxmox packages.

### Kernel command line

t2linux asks for `intel_iommu=on iommu=pt pcie_ports=compat`.

- **GRUB** (ext4 or LVM install): add them to `GRUB_CMDLINE_LINUX_DEFAULT`
  in `/etc/default/grub`, then run `update-grub`.
- **systemd-boot** (ZFS install): add them to the line in `/etc/kernel/cmdline`,
  then run `proxmox-boot-tool refresh`.

### Load the T2 driver

```sh
echo apple-bce > /etc/modules-load.d/t2.conf
reboot
```

### Check it works

```sh
uname -r                 # 7.0.14-30-t2-pve
lsmod | grep apple_bce
ls /sys/devices/platform/applesmc.768/ 2>/dev/null || ls /sys/bus/acpi/drivers/applesmc/
```

### Fans

The fans run slow and the Mac mini can get hot under load.
Set up `t2fanrd` with the [t2linux fan guide](https://wiki.t2linux.org/guides/fan/).

### Wi-Fi and Bluetooth

They need firmware copied from macOS. See the
[t2linux Wi-Fi and Bluetooth guide](https://wiki.t2linux.org/guides/wifi-bluetooth/).
Most servers use Ethernet, so this is optional.

## Update to a newer Proxmox kernel

1. Find the new commit in the [Proxmox kernel repo](https://git.proxmox.com/?p=pve-kernel.git).
2. Set `PVE_KERNEL_REF` in `config.env`. Update the comment with the version.
3. If Proxmox moved to a new Linux version (like 7.0 to 7.1), set
   `T2_PATCHES_REF` to the last t2linux commit made for that version.
   Look at the history of the `version` file in
   [linux-t2-patches](https://github.com/t2linux/linux-t2-patches/commits/main/version).
4. Run the quick patch check.
5. If a patch fails, make a fixed copy in `patches/` with the same name.
   If the fixes in `patches/` are no longer needed, delete them.
6. Build.

## Remove

```sh
proxmox-boot-tool kernel unpin
apt remove 'proxmox-kernel-*-t2-pve' 'proxmox-headers-*-t2-pve'
```

## Credits

- [t2linux](https://github.com/t2linux/linux-t2-patches) for the patches
- [Proxmox](https://git.proxmox.com/?p=pve-kernel.git) for the kernel packaging
- [AdityaGarg8/pve-edge-kernel-t2](https://github.com/AdityaGarg8/pve-edge-kernel-t2), which showed the way
