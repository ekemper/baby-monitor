# Ubuntu Server on Raspberry Pi SD Card (dd on macOS)

Lightest option: **Ubuntu Server 24.04 LTS preinstalled** for Raspberry Pi (no installer; image is written directly to the card).

---

## 1. Image to use

**Preinstalled server (recommended, lightest):**

- **File:** `ubuntu-24.04.3-preinstalled-server-arm64+raspi.img.xz`
- **Size:** ~1.1 GB compressed
- **Compatible:** Pi 3, 4, 5, CM4, Zero 2 W
- **Download:**  
  https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04.3-preinstalled-server-arm64+raspi.img.xz

**Verify (optional):**  
https://cdimage.ubuntu.com/releases/24.04/release/SHA256SUMS — check the line for the above filename and run `shasum -a 256 <file>` after download.

---

## 2. Best practice with dd on macOS

**Warning:** Using the wrong `of=` device will overwrite your Mac’s disk. Double-check the SD card device.

### Step 1: Insert SD card, find its device

```bash
diskutil list
```

Identify the SD card by **size** (e.g. 8 GB, 16 GB) and type (often `FDisk_partition_scheme` or similar). Note the **disk number** (e.g. `disk3`), not a partition like `disk3s1`.

### Step 2: Unmount the card (do not skip)

```bash
diskutil unmountDisk /dev/diskN
```

Replace `N` with your disk number (e.g. `diskutil unmountDisk /dev/disk3`). You should see “Unmount of all volumes on diskN was successful”.

### Step 3: Install xz (if needed)

Images are `.img.xz`. macOS may not have `xz`/`xzcat`:

```bash
brew install xz
```

### Step 4: Write the image (stream decompress → dd)

Use the **raw** device (`rdiskN`) for faster writes. Replace:

- `N` with your disk number
- `~/Downloads/ubuntu-24.04.3-preinstalled-server-arm64+raspi.img.xz` with the path to your downloaded file if different

**One command (decompress and write):**

```bash
xzcat ~/Downloads/ubuntu-24.04.3-preinstalled-server-arm64+raspi.img.xz | sudo dd of=/dev/rdiskN bs=4m status=progress
```

If `xzcat` is not available, use:

```bash
xz -dc ~/Downloads/ubuntu-24.04.3-preinstalled-server-arm64+raspi.img.xz | sudo dd of=/dev/rdiskN bs=4m status=progress
```

- `bs=4m` — 4 MiB block size (good balance; some use `32m` for speed).
- `status=progress` — print progress (GNU dd; on macOS `dd` may not support it; progress will appear when the command finishes).
- **Use `rdiskN`** (e.g. `/dev/rdisk3`), not `diskN`, for faster writes.

### Step 5: Eject

When dd finishes (you get the shell back and “records in/out”):

```bash
diskutil eject /dev/diskN
```

Then remove the card and boot the Pi from it.

---

## 3. Quick reference

| Step        | Command |
|------------|---------|
| List disks | `diskutil list` |
| Unmount    | `diskutil unmountDisk /dev/diskN` |
| Write      | `xzcat path/to/ubuntu-24.04.3-preinstalled-server-arm64+raspi.img.xz \| sudo dd of=/dev/rdiskN bs=4m` |
| Eject      | `diskutil eject /dev/diskN` |

---

## 4. First boot (Ubuntu Server 24.04 on Pi)

- Default user: **ubuntu**
- Default password: **ubuntu** — you will be forced to change it at first login.
- For headless: configure cloud-init or add `user-data` on the card if you need SSH/network set before first boot (see Ubuntu Raspberry Pi docs).

---

## 5. If you used a .img (already uncompressed)

If you decompressed to a `.img` file:

```bash
sudo dd if=path/to/image.img of=/dev/rdiskN bs=4m status=progress
```

Then unmount and eject as above.

---

## 6. Verify the image was written correctly

**Why:** SD cards can fail mid-write; verification confirms the device matches the image byte-for-byte.

**Important:** Do **not** checksum the whole device (e.g. `shasum /dev/rdisk5`). The card is usually **larger** than the image, so the hash will never match the image and does not indicate a bad write. Compare only the **first N bytes** (N = image size).

### Method A: Byte compare with `cmp` (best)

Compares the original image to the card up to the image size. Use the **raw** device and **unmount** the card first so reads are consistent.

**If you have the decompressed `.img` file:**

1. Unmount the card (do not eject):
   ```bash
   diskutil unmountDisk /dev/diskN
   ```
2. Get the image size in bytes:
   ```bash
   stat -f %z path/to/image.img
   ```
   (On Linux: `stat -c %s path/to/image.img`.)
3. Compare (replace `SIZE` and paths; use your disk number, e.g. `rdisk5`):
   ```bash
   cmp -n SIZE path/to/image.img /dev/rdiskN
   ```
   - **No output** and **exit code 0** = match; image was written correctly.
   - **Output** (byte offset and differing bytes) = mismatch; rewrite the image.
   - `cmp` stops at the first difference.

**If you only have the `.img.xz` file:**

1. Get the **decompressed** size (no need to decompress the whole file):
   ```bash
   xz -lv path/to/ubuntu-24.04.3-preinstalled-server-arm64+raspi.img.xz
   ```
   Look for “Uncompressed size” in the output (e.g. 3 221 225 472 bytes).
2. Decompress to a temporary file (or to stdout and pipe to cmp):
   ```bash
   xz -dc path/to/image.img.xz | cmp -n SIZE - /dev/rdiskN
   ```
   Here `SIZE` is the decompressed size from step 1; `-` is stdin. Unmount the card first.

### Method B: Read back and checksum

1. Get image size: `stat -f %z image.img` or `xz -lv image.img.xz` (uncompressed size).
2. Unmount the card: `diskutil unmountDisk /dev/diskN`
3. Read back exactly that many bytes from the card:
   ```bash
   sudo dd if=/dev/rdiskN of=readback.img bs=1m count=XXXX
   ```
   Use `count` so that `count * bs` ≥ image size (e.g. for ~3.2 GB use `bs=1m count=3200` or compute exactly).
4. Compare checksums:
   ```bash
   shasum -a 256 image.img readback.img
   ```
   Both lines should show the **same** hash. Then delete `readback.img`.

### Method C: Sanity check without the original image

If you no longer have the image file:

1. **Partition layout:** After writing a Pi/Ubuntu image, the card should show multiple partitions (e.g. boot + root). Check:
   ```bash
   diskutil list /dev/diskN
   ```
   You should see a partition table and several partitions (e.g. FAT32 boot, Linux root).
2. **First Aid (read-only):** In Disk Utility, select the SD card and run “First Aid”. It checks filesystem consistency; it does **not** verify the image content.
3. **Boot test:** Booting the Pi from the card is the real test; if it boots and the OS works, the write was sufficient (not a byte-level guarantee).

### Quick reference (verification)

| You have              | Action |
|-----------------------|--------|
| Original `.img`       | `cmp -n $(stat -f %z image.img) image.img /dev/rdiskN` (after unmount). |
| Original `.img.xz`    | Get uncompressed size with `xz -lv`; then `xz -dc image.img.xz \| cmp -n SIZE - /dev/rdiskN`. |
| No original file      | Check `diskutil list` for partitions; run First Aid; boot the Pi. |
