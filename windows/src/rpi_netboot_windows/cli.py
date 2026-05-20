from __future__ import annotations

import argparse
import ntpath
import platform
import sys
from pathlib import Path

from .generators import generate, render_sources
from .models import (
    SUPPORTED_METHODS,
    Client,
    HostConfig,
    import_legacy_backup,
    load_config,
    save_config,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="rpi-win-netboot",
        description="Generate Windows-side setup plans for Raspberry Pi network boot.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    init = sub.add_parser("init", help="Create a starter JSON configuration.")
    init.add_argument("--config", default="rpi-netboot.json", help="Config path to create.")
    init.add_argument("--method", choices=SUPPORTED_METHODS, default="windows-lite-nfs")
    init.add_argument("--server-ip", default="192.168.1.10")
    init.add_argument("--router-ip", default="192.168.1.1")
    init.add_argument("--dns-server", default="")
    init.add_argument("--project-root", default="D:\\")
    init.add_argument("--tftp-root", default="")
    init.add_argument("--rootfs-root", default="")
    init.add_argument("--iscsi-root", default="")

    add = sub.add_parser("add-client", help="Add a Raspberry Pi client to a config.")
    add.add_argument("--config", default="rpi-netboot.json")
    add.add_argument("--serial", required=True)
    add.add_argument("--mac", required=True)
    add.add_argument("--ip", required=True)
    add.add_argument("--hostname", default="")
    add.add_argument("--model", default="pi4")
    add.add_argument("--boot-mode", choices=["nfs", "iscsi"], default="nfs")

    imp = sub.add_parser("import-legacy", help="Import clients_backup.json from the Linux project.")
    imp.add_argument("--backup", required=True)
    imp.add_argument("--config", default="rpi-netboot.json")
    imp.add_argument("--method", choices=SUPPORTED_METHODS, default="windows-lite-nfs")
    imp.add_argument("--server-ip", default="192.168.1.10")
    imp.add_argument("--router-ip", default="192.168.1.1")
    imp.add_argument("--dns-server", default="")
    imp.add_argument("--project-root", default="D:\\")
    imp.add_argument("--tftp-root", default="")
    imp.add_argument("--rootfs-root", default="")
    imp.add_argument("--iscsi-root", default="")

    gen = sub.add_parser("generate", help="Generate Windows/Pi setup files from a config.")
    gen.add_argument("--config", default="rpi-netboot.json")
    gen.add_argument("--out", default="generated")

    doctor = sub.add_parser("doctor", help="Print local environment observations.")
    doctor.add_argument("--config", default="rpi-netboot.json")

    sub.add_parser("sources", help="Print research source links.")
    return parser


def with_project_roots(
    config: HostConfig,
    project_root: str,
    tftp_root: str = "",
    rootfs_root: str = "",
    iscsi_root: str = "",
) -> HostConfig:
    root = ntpath.normpath(project_root)
    if root.endswith(":"):
        root += "\\"
    if not config.dns_server:
        config.dns_server = config.router_ip
    if not config.dhcp_start or not config.dhcp_end:
        parts = config.server_ip.split(".")
        if len(parts) == 4:
            base = ".".join(parts[:3])
            config.dhcp_start = config.dhcp_start or f"{base}.100"
            config.dhcp_end = config.dhcp_end or f"{base}.199"
    config.project_root = root
    config.tftp_root = ntpath.normpath(tftp_root) if tftp_root else ntpath.join(root, "tftp")
    config.nfs_root = ntpath.normpath(rootfs_root) if rootfs_root else ntpath.join(root, "rootfs")
    config.iscsi_root = ntpath.normpath(iscsi_root) if iscsi_root else ntpath.join(root, "iscsi")
    return config.normalized()


def move_ip_to_server_subnet(client_ip: str, server_ip: str) -> str:
    client_parts = client_ip.split(".")
    server_parts = server_ip.split(".")
    if len(client_parts) != 4 or len(server_parts) != 4:
        return client_ip
    return ".".join(server_parts[:3] + [client_parts[3]])


def cmd_init(args: argparse.Namespace) -> int:
    config = with_project_roots(
        HostConfig(
            method=args.method,
            server_ip=args.server_ip,
            router_ip=args.router_ip,
            dns_server=args.dns_server,
        ),
        args.project_root,
        args.tftp_root,
        args.rootfs_root,
        args.iscsi_root,
    )
    save_config(config, Path(args.config))
    print(f"Created {Path(args.config).resolve()}")
    return 0


def cmd_add_client(args: argparse.Namespace) -> int:
    path = Path(args.config)
    config = load_config(path)
    config.clients.append(
        Client(
            serial=args.serial,
            mac=args.mac,
            ip=args.ip,
            hostname=args.hostname,
            model=args.model,
            boot_mode=args.boot_mode,
        )
    )
    save_config(config.normalized(), path)
    print(f"Added client to {path.resolve()}")
    return 0


def cmd_import_legacy(args: argparse.Namespace) -> int:
    clients = import_legacy_backup(Path(args.backup))
    for client in clients:
        client.ip = move_ip_to_server_subnet(client.ip, args.server_ip)
    config = with_project_roots(
        HostConfig(
            method=args.method,
            server_ip=args.server_ip,
            router_ip=args.router_ip,
            dns_server=args.dns_server,
            clients=clients,
        ),
        args.project_root,
        args.tftp_root,
        args.rootfs_root,
        args.iscsi_root,
    )
    save_config(config, Path(args.config))
    print(f"Imported {len(clients)} clients into {Path(args.config).resolve()}")
    return 0


def cmd_generate(args: argparse.Namespace) -> int:
    config = load_config(Path(args.config))
    output = Path(args.out)
    generate(config, output)
    print(f"Generated plan in {output.resolve()}")
    return 0


def cmd_doctor(args: argparse.Namespace) -> int:
    print(f"OS: {platform.platform()}")
    print(f"Python: {sys.version.split()[0]}")
    path = Path(args.config)
    if path.exists():
        config = load_config(path)
        print(f"Config: {path.resolve()}")
        print(f"Method: {config.method}")
        print(f"Server IP: {config.server_ip}")
        print(f"DHCP scope: {config.dhcp_scope_id}/{config.cidr_prefix}")
        print(f"Clients: {len(config.clients)}")
    else:
        print(f"Config not found: {path.resolve()}")
    if platform.system().lower() != "windows":
        print("Note: this generator can run anywhere, but the generated apply scripts target Windows.")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "init":
            return cmd_init(args)
        if args.command == "add-client":
            return cmd_add_client(args)
        if args.command == "import-legacy":
            return cmd_import_legacy(args)
        if args.command == "generate":
            return cmd_generate(args)
        if args.command == "doctor":
            return cmd_doctor(args)
        if args.command == "sources":
            print(render_sources().strip())
            return 0
        parser.error(f"unknown command {args.command}")
        return 2
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
