# NFS Provider Matrix

| Provider | Status | Evidence | Decision |
| --- | --- | --- | --- |
| WinNFSd | Reaches rootfs read/init read, then `error -14` | `INIT_EXEC_FAIL_PROBABLE` | Not enough for production |
| haneWIN TCP | Fails on RPC args parsing | `nfs3_getattr/access cannot read args` | Reject |
| haneWIN UDP | Reaches mountd mapping, then invalid argument | `NFS_MOUNT_INVALID_ARGUMENT` | Reject as production path |
| Linux nfs-kernel-server | Next A/B provider | bundle ready at `D:\tools\rpi-netboot\linux-nfs-provider` | Highest probability next step |

## Rule

Only RPi4 participates in network boot. RPi Zero 2 W stays on the SD + USB gadget workflow.
