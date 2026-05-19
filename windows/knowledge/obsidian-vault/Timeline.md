# Timeline

## 2026-05-19

- 10:25 - WinNFSd reached NFS root/init read, then failed with `error -14`.
- 10:50 - Linux NFS provider bundle automation added.
- 12:13 - haneWIN portable provider added for A/B testing.
- 13:13 - haneWIN TCP failed with RPC args parsing errors.
- 13:20 - haneWIN UDP first profile failed because Pi rejected `proto=udp`.
- 13:40 - haneWIN UDP corrected profile reached mountd path mapping, then Pi failed with `nfs mount mount: invalid argument`.
- 13:55 - Harness verdict updated to `NFS_MOUNT_INVALID_ARGUMENT`.
