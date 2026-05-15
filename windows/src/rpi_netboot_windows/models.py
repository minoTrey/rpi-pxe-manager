from __future__ import annotations

from dataclasses import asdict, dataclass, field
from ipaddress import IPv4Network
from pathlib import Path
import json
import re


SUPPORTED_METHODS = (
    "hanewin-nfs",
    "windows-server-nfs",
    "windows-server-iscsi",
)


def normalize_mac(value: str) -> str:
    cleaned = re.sub(r"[^0-9a-fA-F]", "", value or "")
    if len(cleaned) != 12:
        raise ValueError(f"MAC address must contain 12 hex digits: {value!r}")
    pairs = [cleaned[i : i + 2].lower() for i in range(0, 12, 2)]
    return ":".join(pairs)


def windows_dhcp_client_id(mac: str) -> str:
    return normalize_mac(mac).replace(":", "-")


def safe_name(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_.-]+", "-", value.strip())
    return cleaned.strip("-") or "rpi"


@dataclass(slots=True)
class Client:
    serial: str
    mac: str
    ip: str
    hostname: str = ""
    model: str = "pi4"
    boot_mode: str = "nfs"
    tftp_prefix: str = ""
    iscsi_target_name: str = ""
    iscsi_initiator_iqn: str = ""
    root_uuid: str = ""

    def normalized(self) -> "Client":
        serial = safe_name(self.serial.lower())
        hostname = safe_name(self.hostname or f"rpi-{serial[-6:]}")
        prefix = safe_name(self.tftp_prefix or serial)
        return Client(
            serial=serial,
            mac=normalize_mac(self.mac),
            ip=self.ip,
            hostname=hostname,
            model=self.model or "pi4",
            boot_mode=self.boot_mode or "nfs",
            tftp_prefix=prefix,
            iscsi_target_name=self.iscsi_target_name or f"rpi-{hostname}",
            iscsi_initiator_iqn=self.iscsi_initiator_iqn
            or f"iqn.1993-08.org.debian:01:{hostname}",
            root_uuid=self.root_uuid,
        )


@dataclass(slots=True)
class HostConfig:
    name: str = "rpi-netboot-windows"
    method: str = "hanewin-nfs"
    server_ip: str = "192.168.1.10"
    router_ip: str = "192.168.1.1"
    dns_server: str = "192.168.1.1"
    subnet_mask: str = "255.255.255.0"
    dhcp_start: str = ""
    dhcp_end: str = ""
    project_root: str = "D:\\"
    tftp_root: str = r"D:\tftp"
    nfs_root: str = r"D:\rootfs"
    nfs_alias: str = "/rpi"
    iscsi_root: str = r"D:\iscsi"
    vhdx_size_gb: int = 32
    clients: list[Client] = field(default_factory=list)

    def normalized(self) -> "HostConfig":
        if self.method not in SUPPORTED_METHODS:
            raise ValueError(
                f"Unsupported method {self.method!r}; choose one of {', '.join(SUPPORTED_METHODS)}"
            )
        clients = [client.normalized() for client in self.clients]
        return HostConfig(
            name=safe_name(self.name),
            method=self.method,
            server_ip=self.server_ip,
            router_ip=self.router_ip,
            dns_server=self.dns_server,
            subnet_mask=self.subnet_mask,
            dhcp_start=self.dhcp_start,
            dhcp_end=self.dhcp_end,
            project_root=self.project_root,
            tftp_root=self.tftp_root,
            nfs_root=self.nfs_root,
            nfs_alias=self.nfs_alias.rstrip("/") or "/rpi",
            iscsi_root=self.iscsi_root,
            vhdx_size_gb=self.vhdx_size_gb,
            clients=clients,
        )

    @property
    def dhcp_scope_id(self) -> str:
        network = IPv4Network(f"{self.server_ip}/{self.subnet_mask}", strict=False)
        return str(network.network_address)

    @property
    def cidr_prefix(self) -> int:
        return IPv4Network(f"{self.server_ip}/{self.subnet_mask}", strict=False).prefixlen

    def to_dict(self) -> dict:
        data = asdict(self)
        data["clients"] = [asdict(client) for client in self.clients]
        return data

    @classmethod
    def from_dict(cls, data: dict) -> "HostConfig":
        raw_clients = data.get("clients", [])
        clients = [Client(**client) for client in raw_clients]
        copied = dict(data)
        copied["clients"] = clients
        return cls(**copied).normalized()


def load_config(path: Path) -> HostConfig:
    with path.open("r", encoding="utf-8") as handle:
        return HostConfig.from_dict(json.load(handle))


def save_config(config: HostConfig, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(config.normalized().to_dict(), handle, indent=2)
        handle.write("\n")


def import_legacy_backup(path: Path) -> list[Client]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    clients = []
    for item in data.get("clients", []):
        clients.append(
            Client(
                serial=str(item.get("serial", "")),
                mac=str(item.get("mac", "")),
                ip=str(item.get("ip", "")),
                hostname=str(item.get("hostname", "")),
                boot_mode=str(item.get("boot_mode", "nfs")),
            ).normalized()
        )
    return clients
