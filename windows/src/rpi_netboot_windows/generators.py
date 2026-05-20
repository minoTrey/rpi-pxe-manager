from __future__ import annotations

from pathlib import Path
from textwrap import dedent

from .models import HostConfig, windows_dhcp_client_id


OPTION43_BYTES = [
    0x06,
    0x01,
    0x03,
    0x0A,
    0x04,
    0x00,
    0x50,
    0x58,
    0x45,
    0x09,
    0x14,
    0x00,
    0x00,
    0x11,
    0x52,
    0x61,
    0x73,
    0x70,
    0x62,
    0x65,
    0x72,
    0x72,
    0x79,
    0x20,
    0x50,
    0x69,
    0x20,
    0x42,
    0x6F,
    0x6F,
    0x74,
    0xFF,
]


def ps_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def option43_powershell() -> str:
    return "[byte[]](" + ",".join(f"0x{value:02X}" for value in OPTION43_BYTES) + ")"


def option43_decimal_text() -> str:
    return " ".join(str(value) for value in OPTION43_BYTES)


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def write_text(path: Path, content: str) -> None:
    ensure_dir(path.parent)
    path.write_text(content.rstrip() + "\n", encoding="utf-8")


def nfs_cmdline(config: HostConfig, client_index: int) -> str:
    client = config.clients[client_index]
    return (
        "console=serial0,115200 console=tty1 "
        "root=/dev/nfs "
        f"nfsroot={config.server_ip}:{config.nfs_alias}/{client.serial},vers=3 "
        "rw ip=dhcp rootwait elevator=deadline init=/usr/sbin/init"
    )


def iscsi_cmdline(config: HostConfig, client_index: int) -> str:
    client = config.clients[client_index]
    root = client.root_uuid or "REPLACE_WITH_ROOT_FILESYSTEM_UUID"
    return (
        "console=serial0,115200 console=tty1 "
        "ip=dhcp rootwait rw "
        f"ISCSI_INITIATOR={client.iscsi_initiator_iqn} "
        f"ISCSI_TARGET_NAME=iqn.1991-05.com.microsoft:{client.iscsi_target_name} "
        f"ISCSI_TARGET_IP={config.server_ip} "
        f"root=UUID={root}"
    )


def render_readme(config: HostConfig) -> str:
    method_note = {
        "windows-lite-nfs": "Windows desktop lab path using built-in DHCP/TFTP and an NFS rootfs service",
        "hanewin-nfs": "haneWIN DHCP/NFS + Tftpd64 또는 haneWIN TFTP를 쓰는 Windows Desktop 친화 경로",
        "windows-server-nfs": "Windows Server DHCP + Server for NFS + 별도 TFTP 경로",
        "windows-server-iscsi": "Windows Server DHCP + TFTP + iSCSI Target 경로",
    }[config.method]

    return dedent(
        f"""
        # Generated Raspberry Pi Windows Netboot Plan

        Method: `{config.method}` - {method_note}

        This directory is a plan, not an automatic network mutation. Review the files,
        run PowerShell as Administrator where required, and test on an isolated wired
        lab network before touching a production LAN.

        ## Apply Order

        1. Create the Windows folders:
           - `{config.project_root}`
           - `{config.tftp_root}`
           - `{config.nfs_root}`
           - `{config.iscsi_root}` only if using iSCSI
        2. Copy Raspberry Pi boot partition files into each `tftp/<prefix>` folder.
           The generated `cmdline.txt` and `config.txt` files are already placed there.
        3. Configure DHCP/TFTP:
           - Windows Server users: review `windows/02-dhcp-windows-server.ps1`.
           - Desktop/lab users: start the boot service from the Windows GUI.
        4. Configure the root filesystem backend:
           - NFS: use the operational rootfs service, or review `windows/server-nfs.ps1` for Windows Server.
           - iSCSI: review `windows/03-iscsi-windows-server.ps1`.
        5. Open firewall ports with `windows/01-firewall.ps1`.
        6. Materialize the Linux root filesystem from a Pi/Linux helper using
           `pi/materialize-rootfs.sh`. Do not extract the ext4 root partition with
           ordinary Windows unzip tools; symlinks, ownership, and mode bits matter.

        ## Network Values

        - Server IP: `{config.server_ip}`
        - DHCP scope: `{config.dhcp_scope_id}/{config.cidr_prefix}`
        - Router: `{config.router_ip}`
        - DNS: `{config.dns_server}`
        - Subnet mask: `{config.subnet_mask}`
        - Clients: `{len(config.clients)}`

        ## Important Raspberry Pi Constraints

        - Netboot uses the built-in wired Ethernet adapter.
        - Early boot needs DHCP and TFTP before Linux starts.
        - The Linux root filesystem should be NFSv3 or another initramfs-supported
          root such as iSCSI.
        - Raspberry Pi 4/5 use EEPROM bootloader settings; standardize TFTP prefix
          behavior before scaling to many devices.
        """
    )


def render_firewall(config: HostConfig) -> str:
    return dedent(
        f"""
        # Run in an elevated PowerShell session.
        # This opens common lab ports for Raspberry Pi netboot.

        New-NetFirewallRule -DisplayName "RPI Netboot DHCP" -Direction Inbound -Protocol UDP -LocalPort 67,68 -Action Allow -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName "RPI Netboot TFTP" -Direction Inbound -Protocol UDP -LocalPort 69 -Action Allow -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName "RPI Netboot NFS RPC" -Direction Inbound -Protocol TCP -LocalPort 111,2049 -Action Allow -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName "RPI Netboot NFS RPC UDP" -Direction Inbound -Protocol UDP -LocalPort 111,2049 -Action Allow -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName "RPI Netboot iSCSI" -Direction Inbound -Protocol TCP -LocalPort 3260 -Action Allow -ErrorAction SilentlyContinue

        Write-Host "Firewall rules added for {config.name} on {config.server_ip}."
        Write-Host "If your TFTP/NFS tool uses dynamic high ports, allow the program executable too."
        """
    )


def render_dhcp_windows_server(config: HostConfig) -> str:
    reservations = []
    for client in config.clients:
        reservations.append(
            "Add-DhcpServerv4Reservation "
            f"-ScopeId {ps_quote(config.dhcp_scope_id)} "
            f"-IPAddress {ps_quote(client.ip)} "
            f"-ClientId {ps_quote(windows_dhcp_client_id(client.mac))} "
            f"-Description {ps_quote('Raspberry Pi ' + client.hostname)} "
            f"-Name {ps_quote(client.hostname)} "
            "-ErrorAction SilentlyContinue"
        )

    reservation_block = "\n".join(reservations) or "# Add clients first, then regenerate."
    option43 = option43_powershell()
    return dedent(
        f"""
        # Run in an elevated PowerShell session on Windows Server.
        # Review before running. Existing DHCP scopes/options may conflict.

        $ScopeId = {ps_quote(config.dhcp_scope_id)}
        $StartRange = {ps_quote(config.dhcp_start)}
        $EndRange = {ps_quote(config.dhcp_end)}
        $SubnetMask = {ps_quote(config.subnet_mask)}
        $Router = {ps_quote(config.router_ip)}
        $DnsServer = {ps_quote(config.dns_server)}
        $TftpServer = {ps_quote(config.server_ip)}
        $Option43 = {option43}

        Install-WindowsFeature -Name DHCP -IncludeManagementTools

        if (-not (Get-DhcpServerv4Scope -ScopeId $ScopeId -ErrorAction SilentlyContinue)) {{
            Add-DhcpServerv4Scope -Name {ps_quote(config.name)} -StartRange $StartRange -EndRange $EndRange -SubnetMask $SubnetMask
        }}

        Set-DhcpServerv4OptionValue -ScopeId $ScopeId -Router $Router -DnsServer $DnsServer
        Set-DhcpServerv4OptionValue -ScopeId $ScopeId -OptionId 66 -Value $TftpServer
        Set-DhcpServerv4OptionValue -ScopeId $ScopeId -OptionId 67 -Value "bootcode.bin"

        # Raspberry Pi legacy netboot vendor-specific option 43.
        # If this errors on your DHCP Server version, create option 43 manually
        # with this byte sequence: {option43_decimal_text()}
        Set-DhcpServerv4OptionValue -ScopeId $ScopeId -OptionId 43 -Value $Option43

        {reservation_block}

        Write-Host "DHCP plan applied. Verify no other DHCP server is answering on this VLAN."
        """
    )


def render_hanewin_dhcp(config: HostConfig) -> str:
    rows = []
    for client in config.clients:
        rows.append(f"- `{client.mac}` -> `{client.ip}` ({client.hostname}), profile `{config.name}`")
    client_rows = "\n".join(rows) or "- Add clients first, then regenerate."
    return dedent(
        f"""
        # haneWIN DHCP/TFTP Profile Notes

        Use this when running from Windows desktop or when you prefer haneWIN DHCP
        over Windows Server DHCP.

        ## Profile

        - Profile name: `{config.name}`
        - Gateway/router: `{config.router_ip}`
        - DNS server: `{config.dns_server}`
        - TFTP next server: `{config.server_ip}`
        - TFTP root directory: `{config.tftp_root}`
        - Vendor-specific option 43 bytes:

        ```text
        {option43_decimal_text()}
        ```

        ## Static Clients

        {client_rows}

        ## Notes

        The option 43 payload advertises the Raspberry Pi PXE vendor string. Keep
        DHCP and TFTP on the same lab network for first boot tests.
        """
    )


def render_hanewin_nfs(config: HostConfig) -> str:
    return dedent(
        f"""
        # haneWIN NFS export lines
        # In haneWIN NFS Server, enable "Save attributes/uid/gid on NTFS volumes".
        # Then add this export:

        {config.nfs_root} -name:{config.nfs_alias.lstrip("/")} -alldirs -i32 -maproot:0:0
        """
    )


def render_server_nfs(config: HostConfig) -> str:
    return dedent(
        f"""
        # Run in an elevated PowerShell session on Windows Server.
        # Windows Server for NFS is edition-specific. Test Linux metadata behavior
        # before relying on it for a writable Raspberry Pi root filesystem.

        Install-WindowsFeature -Name FS-NFS-Service -IncludeManagementTools
        New-Item -ItemType Directory -Force -Path {ps_quote(config.nfs_root)} | Out-Null

        # This uses permissive unmapped access for a closed lab network.
        # Tighten access before using outside a lab.
        New-NfsShare -Name {ps_quote(config.nfs_alias.lstrip("/"))} -Path {ps_quote(config.nfs_root)} -Permission ReadWrite -AllowRootAccess $true -Authentication sys
        Grant-NfsSharePermission -Name {ps_quote(config.nfs_alias.lstrip("/"))} -ClientName "*" -ClientType Host -Permission ReadWrite -AllowRootAccess $true
        """
    )


def render_iscsi(config: HostConfig) -> str:
    blocks = []
    for client in config.clients:
        target_name = f"iqn.1991-05.com.microsoft:{client.iscsi_target_name}"
        vhdx = f"{config.iscsi_root}\\{client.hostname}.vhdx"
        blocks.append(
            dedent(
                f"""
                New-IscsiVirtualDisk -Path {ps_quote(vhdx)} -SizeBytes {config.vhdx_size_gb}GB
                New-IscsiServerTarget -TargetName {ps_quote(client.iscsi_target_name)} -InitiatorIds {ps_quote('IQN:' + client.iscsi_initiator_iqn)}
                Add-IscsiVirtualDiskTargetMapping -TargetName {ps_quote(client.iscsi_target_name)} -Path {ps_quote(vhdx)}
                # Pi cmdline target: {target_name}
                """
            ).strip()
        )
    block_text = "\n\n".join(blocks) or "# Add clients first, then regenerate."
    return dedent(
        f"""
        # Run in an elevated PowerShell session on Windows Server.
        # This creates one VHDX/iSCSI target per Raspberry Pi client.

        Install-WindowsFeature -Name FS-iSCSITarget-Server -IncludeManagementTools
        New-Item -ItemType Directory -Force -Path {ps_quote(config.iscsi_root)} | Out-Null

        {block_text}
        """
    )


def render_materialize_rootfs(config: HostConfig) -> str:
    first = config.clients[0].serial if config.clients else "CLIENT_SERIAL"
    return dedent(
        f"""\
        #!/usr/bin/env bash
        set -euo pipefail

        # Run this from a temporary Raspberry Pi OS boot or a Linux helper machine.
        # It copies a mounted/ext4 Raspberry Pi root filesystem into the Windows NFS
        # export through NFS, preserving Linux metadata through the NFS server.

        SERVER_IP="${{SERVER_IP:-{config.server_ip}}}"
        NFS_ALIAS="${{NFS_ALIAS:-{config.nfs_alias}}}"
        CLIENT_SERIAL="${{CLIENT_SERIAL:-{first}}}"
        SOURCE_ROOT="${{1:-}}"
        WORK="${{WORK:-/mnt/rpi-netboot-windows}}"

        if [ -z "$SOURCE_ROOT" ]; then
          echo "Usage: CLIENT_SERIAL=<serial> $0 /path/to/mounted/rootfs"
          echo "Example: sudo mount /dev/sda2 /mnt/pi-root && CLIENT_SERIAL={first} $0 /mnt/pi-root"
          exit 2
        fi

        sudo apt-get update
        sudo apt-get install -y nfs-common rsync

        sudo mkdir -p "$WORK/nfs"
        sudo mountpoint -q "$WORK/nfs" || sudo mount -t nfs -o vers=3,tcp "$SERVER_IP:$NFS_ALIAS" "$WORK/nfs"
        sudo mkdir -p "$WORK/nfs/$CLIENT_SERIAL"

        sudo rsync -aHAX --numeric-ids --delete "$SOURCE_ROOT"/ "$WORK/nfs/$CLIENT_SERIAL"/

        if [ -f "$WORK/nfs/$CLIENT_SERIAL/etc/fstab" ]; then
          sudo sed -i.bak -E 's#^(PARTUUID=[^[:space:]]+[[:space:]]+/[[:space:]].*)$#\\#\\1#' "$WORK/nfs/$CLIENT_SERIAL/etc/fstab"
          sudo sed -i -E 's#^(PARTUUID=[^[:space:]]+[[:space:]]+/boot[^[:space:]]*[[:space:]].*)$#\\#\\1#' "$WORK/nfs/$CLIENT_SERIAL/etc/fstab"
        fi

        echo "Root filesystem copied to $SERVER_IP:$NFS_ALIAS/$CLIENT_SERIAL"
        """
    )


def render_sources() -> str:
    return dedent(
        """
        # Research Notes

        Windows support is feasible because Raspberry Pi netboot requires standard
        network services, not Linux specifically. The hard part is matching the
        services and Linux filesystem semantics.

        ## Primary Sources

        - Raspberry Pi network boot flow and Ethernet-only constraint:
          https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#network-booting
        - Raspberry Pi bootloader and TFTP prefix settings:
          https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#raspberry-pi-bootloader-configuration
        - Windows Server NFS:
          https://learn.microsoft.com/en-us/windows-server/storage/nfs/deploy-nfs
        - Windows Server iSCSI Target:
          https://learn.microsoft.com/en-us/windows-server/storage/iscsi/iscsi-target-server
        - Windows Server DHCP PowerShell:
          https://learn.microsoft.com/en-us/powershell/module/dhcpserver/set-dhcpserverv4optionvalue
        - Tftpd64 project:
          https://github.com/PJO2/tftpd64
        - WinNFSd NFSv3 server for Windows:
          https://github.com/winnfsd/winnfsd

        ## Practical Windows Guide Found

        haneWIN documents a Windows-hosted Raspberry Pi netboot path using DHCP,
        TFTP, and NFS:

        - https://hanewin.net/rpi/remote-rpi-boot.htm
        - https://hanewin.net/rpi/remote-rpi-boot2.htm
        """
    )


def generate(config: HostConfig, output_dir: Path) -> None:
    config = config.normalized()
    write_text(output_dir / "README_NEXT_STEPS.md", render_readme(config))
    write_text(output_dir / "RESEARCH_NOTES.md", render_sources())
    write_text(output_dir / "windows" / "01-firewall.ps1", render_firewall(config))
    write_text(output_dir / "windows" / "02-dhcp-windows-server.ps1", render_dhcp_windows_server(config))
    write_text(output_dir / "windows" / "03-iscsi-windows-server.ps1", render_iscsi(config))
    write_text(output_dir / "windows" / "hanewin-dhcp-profile.md", render_hanewin_dhcp(config))
    write_text(output_dir / "windows" / "hanewin-nfs-exports.txt", render_hanewin_nfs(config))
    write_text(output_dir / "windows" / "server-nfs.ps1", render_server_nfs(config))
    write_text(output_dir / "pi" / "materialize-rootfs.sh", render_materialize_rootfs(config))

    for idx, client in enumerate(config.clients):
        tftp_dir = output_dir / "tftp" / client.tftp_prefix
        write_text(tftp_dir / "config.txt", "enable_uart=1\n")
        if config.method == "windows-server-iscsi" or client.boot_mode == "iscsi":
            write_text(tftp_dir / "cmdline.txt", iscsi_cmdline(config, idx))
        else:
            write_text(tftp_dir / "cmdline.txt", nfs_cmdline(config, idx))
        write_text(
            tftp_dir / "README_COPY_BOOT_FILES.txt",
            dedent(
                f"""
                Copy the Raspberry Pi boot partition files for {client.hostname} into this folder.
                Keep the generated cmdline.txt and config.txt, or merge their contents carefully.

                Expected TFTP prefix: {client.tftp_prefix}
                Client IP reservation: {client.ip}
                """
            ),
        )
