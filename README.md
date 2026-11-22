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
| `.github/workflows/build.yml` | Builds on GitHub Actions, makes a release, updates the apt repo |
| `check-upstream.sh` | Moves `config.env` to the newest Proxmox kernel release |
| `.github/workflows/check-upstream.yml` | Runs `check-upstream.sh` daily and starts a build when needed |
| `publish-apt.sh` | Adds a build to the apt repo on the `apt` GitHub release |
| `meta/` | The `proxmox-kernel-t2` package, which always points at the newest kernel |
| `KEY.asc` | Public key that signs the apt repo |

## How updates flow

1. Every day, "Check upstream" looks for a new release commit in the Proxmox kernel repo.
2. If there is one, it updates `config.env`, commits, and starts "Build kernel".
3. The build makes a GitHub release and adds the kernel to the apt repo.
4. On the Mac mini, `apt upgrade` (or the Proxmox web UI) installs it.

If Proxmox moves to a new Linux version (like 7.0 to 7.1), the check opens an
issue instead. The t2linux patches must be picked by hand for that.
If a patch stops applying, the build fails and GitHub emails you.

## Build

A kernel build takes about 2.5 hours on GitHub's 4 core runner and needs about 30 GB of disk.
It must build on an x86_64 (amd64) machine.

### Option 1: GitHub Actions (best on an Apple Silicon Mac)

1. Push this repo to GitHub.
2. Go to Actions, pick "Build kernel", press "Run workflow".
3. When it ends, the `.deb` files are on the Releases page.

### Option 2: On the Mac mini, after Proxmox is installed

```sh
apt install git
git clone <this repo> && cd t2linux-proxmox
./build.sh
```

### Option 3: Any amd64 machine with Docker

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

Add the apt repo and install `proxmox-kernel-t2`:

```sh
curl -fsSL https://raw.githubusercontent.com/antiremy/t2linux-proxmox/main/KEY.asc \
  -o /usr/share/keyrings/t2linux-proxmox.asc
cat > /etc/apt/sources.list.d/t2linux-proxmox.sources <<'EOF'
Types: deb
URIs: https://github.com/antiremy/t2linux-proxmox/releases/download/apt/
Suites: ./
Signed-By: /usr/share/keyrings/t2linux-proxmox.asc
EOF
apt update
apt install proxmox-kernel-t2
```

`proxmox-kernel-t2` pulls in the newest T2 kernel and its headers. It also
pins that kernel as the boot default, so a newer stock Proxmox kernel does not
take over. Each update moves the pin to the new T2 kernel.
The repo keeps the 3 newest kernels.

**Without the apt repo:** download the kernel and headers `.deb` files from a
GitHub release, then:

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

## Update by hand

Most updates are automatic. Do this for a new Linux version, or to rebuild.

1. Find the new commit in the [Proxmox kernel repo](https://git.proxmox.com/?p=pve-kernel.git).
2. Set `PVE_KERNEL_REF` and `PVE_KERNEL_VERSION` in `config.env`, and set `T2_REL=1`.
   To rebuild the same kernel with new t2 patches, bump `T2_REL` instead.
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
apt remove proxmox-kernel-t2    # also unpins the kernel
apt remove 'proxmox-kernel-*-t2-pve' 'proxmox-headers-*-t2-pve'
```

## Set up the apt signing key (once, for the repo owner)

```sh
export GNUPGHOME=$(mktemp -d)
gpg --batch --passphrase '' --quick-gen-key "t2linux-proxmox apt repo" ed25519 sign never
gpg --armor --export > KEY.asc
gpg --armor --export-secret-keys | gh secret set APT_SIGNING_KEY
gpg --armor --export-secret-keys > ~/t2linux-proxmox-apt-key.asc   # keep this somewhere safe
rm -rf "$GNUPGHOME"
git add KEY.asc && git commit -m "Add apt signing key" && git push
```

## Credits

- [t2linux](https://github.com/t2linux/linux-t2-patches) for the patches
- [Proxmox](https://git.proxmox.com/?p=pve-kernel.git) for the kernel packaging
- [AdityaGarg8/pve-edge-kernel-t2](https://github.com/AdityaGarg8/pve-edge-kernel-t2), which showed the way
