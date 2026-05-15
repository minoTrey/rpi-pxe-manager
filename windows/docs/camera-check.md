# Camera Check

This note records the local Windows host camera/video-device inspection and a
future validation workflow for Raspberry Pi cameras after a successful netboot.

## Local Windows Host Snapshot

Inspection time: `2026-05-13T18:08:39.9692816+09:00`

Host OS:

- `Microsoft Windows 10 Pro`
- Version `10.0.19045`, build `19045`
- Architecture: 64-bit

Read-only commands used:

```powershell
Get-PnpDevice -Class Camera |
  Select-Object Status,Class,FriendlyName,InstanceId

Get-PnpDevice -Class Image |
  Select-Object Status,Class,FriendlyName,InstanceId

Get-PnpDevice -Class Media |
  Select-Object Status,Class,FriendlyName,InstanceId

Get-PnpDevice |
  Where-Object {
    $_.FriendlyName -match '(?i)camera|webcam|capture|imaging|usb video' -or
    $_.Class -match '(?i)camera|image'
  } |
  Select-Object Status,Class,FriendlyName,InstanceId

Get-CimInstance Win32_PnPEntity |
  Where-Object {
    $_.Name -match '(?i)camera|webcam|capture|imaging|usb video' -or
    $_.PNPClass -match '(?i)camera|image'
  } |
  Select-Object Name,PNPClass,Status,DeviceID
```

Observed results:

- `Get-PnpDevice -Class Camera` found no devices with PNP class `Camera`.
- `Get-PnpDevice -Class Image` found no devices with PNP class `Image`.
- Broad PnP and CIM keyword searches for camera, webcam, capture, imaging, and
  USB video devices returned no matches.
- `Get-PnpDevice -Class Media` returned audio devices and Microsoft streaming
  proxy components only:
  - `Intel(R) Display Audio`, status `OK`
  - `Realtek(R) Audio`, status `OK`
  - Microsoft streaming service, tee, clock, quality-manager, and trusted-audio
    proxy components, status `Unknown`

Conclusion: no local Windows camera or video capture device was visible through
these read-only PnP/WMI checks at inspection time. This does not prove that no
camera hardware exists; it only means Windows did not expose a camera/video
capture device through the inspected PnP and CIM surfaces.

## Future Raspberry Pi Netboot Validation

Use this workflow after a Raspberry Pi has netbooted from the Windows-hosted
DHCP/TFTP/NFS or iSCSI setup. Keep the Pi camera result separate from the
Windows host result above; CSI cameras attached to the Pi will not appear as
Windows PnP camera devices.

### Before Boot

1. Power the Pi off before connecting or reseating a CSI camera.
2. Confirm the camera cable type and orientation for the Pi model and camera
   module.
3. Make sure the TFTP-served boot files and the network root filesystem come
   from the same Raspberry Pi OS image or release family.
4. In the TFTP-served `config.txt` for that Pi, preserve the normal Raspberry Pi
   OS camera auto-detection line for supported SBC camera modules:

   ```ini
   camera_auto_detect=1
   ```

5. For Compute Modules, third-party sensors, or cameras that do not
   auto-detect, document the required `dtoverlay=...` line from the board or
   camera vendor before testing.
6. Use a known-good power supply. Camera startup failures can be caused by low
   power as well as by software configuration.

### Confirm The Booted Target

Run on the Pi:

```bash
hostname
cat /proc/device-tree/model; echo
awk '/Serial|Model/ {print}' /proc/cpuinfo
ip addr show
findmnt /
cat /etc/os-release
uname -a
```

Record the Pi model, serial, IP address, root mount, OS version, and kernel. This
is especially important when several Pi serial directories exist under the TFTP
root.

### Check Boot Configuration

Run on the Pi:

```bash
grep -E 'camera_auto_detect|dtoverlay|dtparam' /boot/firmware/config.txt
vcgencmd get_config int | grep -E 'camera_auto_detect|start_x|gpu_mem' || true
vcgencmd get_config str
```

For Raspberry Pi OS Bookworm and later, the boot partition is normally mounted
at `/boot/firmware/`. On earlier images it may be mounted at `/boot/`. If the
file contents do not match the generated TFTP serial directory, check whether
the Pi booted from the expected TFTP prefix.

### Check Camera Stack

Raspberry Pi OS Bookworm renamed camera applications from `libcamera-*` to
`rpicam-*`. Prefer `rpicam-*` on current images and keep the `libcamera-*`
fallback only for older images.

Run on the Pi:

```bash
CAM_HELLO="$(command -v rpicam-hello || command -v libcamera-hello)"
test -n "$CAM_HELLO"
"$CAM_HELLO" --version
"$CAM_HELLO" --list-cameras
```

Expected result: `--list-cameras` lists the attached sensor, such as `ov5647`,
`imx219`, `imx708`, `imx477`, `imx296`, or `imx500`, with one or more supported
modes.

If extra package confirmation is needed:

```bash
dpkg -l 'rpicam-apps*' 'libcamera*' 'v4l-utils' | awk '/^ii/ {print $2, $3}'
```

### Check Kernel And Video Nodes

Run on the Pi:

```bash
ls -l /dev/video* /dev/media* 2>/dev/null || true
command -v v4l2-ctl >/dev/null && v4l2-ctl --list-devices
dmesg -T | grep -Ei 'camera|csi|unicam|imx|ov|arducam|libcamera|rp1|pisp' || true
journalctl -b | grep -Ei 'camera|csi|unicam|imx|ov|libcamera|rp1|pisp' || true
```

Absence of `/dev/video*` is not by itself a final failure, but it is useful
evidence when combined with `rpicam-hello --list-cameras` and boot logs.

### Capture Evidence

For a headless test, suppress preview output:

```bash
mkdir -p "$HOME/camera-check"
"$CAM_HELLO" -n --timeout 5000

if command -v rpicam-jpeg >/dev/null; then
  rpicam-jpeg -n --timeout 2000 --width 640 --height 480 \
    -o "$HOME/camera-check/test.jpg"
else
  libcamera-jpeg -n --timeout 2000 --width 640 --height 480 \
    -o "$HOME/camera-check/test.jpg"
fi

if command -v rpicam-vid >/dev/null; then
  rpicam-vid -n --timeout 5000 --width 1280 --height 720 \
    -o "$HOME/camera-check/test.h264"
else
  libcamera-vid -n --timeout 5000 --width 1280 --height 720 \
    -o "$HOME/camera-check/test.h264"
fi

ls -lh "$HOME/camera-check"
```

Expected result:

- The no-preview hello command exits successfully.
- `test.jpg` and `test.h264` are non-empty.
- The image is visually plausible for the lens and lighting.
- The logs do not show `no cameras available`, camera timeout, or sensor probe
  failures.

### Failure Triage

If `--list-cameras` reports no cameras:

- Power off and reseat the camera cable.
- Confirm the Pi model, camera model, cable type, and connector port.
- Check that the active TFTP `config.txt` contains `camera_auto_detect=1` or the
  correct explicit `dtoverlay=...` for the camera.
- Confirm that boot firmware, kernel modules, overlays, and root filesystem come
  from the same Raspberry Pi OS release family.
- Review `dmesg` and `journalctl -b` for sensor probe, I2C, CSI, Unicam, RP1, or
  PiSP errors.

If the camera lists but capture fails:

- Re-run `"$CAM_HELLO" --version` and record the `rpicam-apps`/`libcamera`
  versions.
- Try `-n` for no preview on headless systems.
- Confirm there is enough power and that no other process is holding the camera.
- Save the full command output with the Pi serial and OS/kernel version.

## Result Log Template

```text
Date/time:
Operator:
Pi model:
Pi serial:
Pi IP:
Netboot backend:
Camera module:
Cable/port:
OS/kernel:
config.txt camera lines:
rpicam/libcamera version:
list-cameras result:
capture artifacts:
Pass/fail:
Notes:
```

## References

- Raspberry Pi camera software:
  https://www.raspberrypi.com/documentation/computers/camera_software.html
- Raspberry Pi `config.txt` and `camera_auto_detect`:
  https://www.raspberrypi.com/documentation/computers/config_txt.html
