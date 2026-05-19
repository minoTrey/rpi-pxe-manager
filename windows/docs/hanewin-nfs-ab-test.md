# haneWIN NFS A/B Test

이 실험은 DHCP/TFTP는 현재 Lite provider를 그대로 유지하고, NFS provider만 WinNFSd에서 haneWIN NFS로 바꿉니다.

목적은 WinNFSd/NTFS 계층이 `INIT_EXEC_FAIL_PROBABLE`의 원인인지 빠르게 가르는 것입니다.

## 왜 haneWIN을 다시 쓰나

haneWIN은 장기 운영 기본 provider가 아닙니다. 미등록 상태에서는 평가판입니다. 다만 haneWIN NFS 문서상 Windows 볼륨에서 diskless Unix client를 실행하는 기능, NTFS uid/gid/mode 저장, softlink/special file 처리, `-exec` 옵션을 제공합니다.

따라서 지금은 운영 채택이 아니라 A/B 진단 provider로 씁니다.

## 자동 실행

기본값은 portable 모드입니다. `C:\Program Files\nfsd`의 실행 파일을 `D:\tools\rpi-netboot\hanewin-portable`로 복사하고, 서비스 설정 대신 console/debug 모드의 내장 portmap으로 실행합니다. 이 방식은 Program Files의 `exports`를 직접 수정하지 않습니다.

```text
windows\RPI-Netboot-HaneWIN-NFS-Start-Attempt-Admin.bat
```

이 명령은 다음을 수행합니다.

1. haneWIN portable 폴더를 준비합니다.
2. WinNFSd만 중지합니다. 일반 종료가 막히면 WMI terminate로 PID를 정리합니다.
3. portable `exports`를 백업합니다.
4. haneWIN export를 `D:\rootfs -> /rpi`로 설정합니다.
5. export 옵션에 `-alldirs -i32 -maproot:0:0 -exec`를 넣습니다.
6. 가능하면 haneWIN `SaveAttr`와 방화벽 규칙을 활성화합니다.
7. portable `nfsd.exe -debug -portmap`을 시작합니다.
8. 하네스 `start-attempt`를 시작합니다.

그 다음 사용자가 할 일은 SD 없는 RPi4 전원을 뺐다가 다시 꽂는 것뿐입니다.

성공적으로 전환되면 `status`에서 `nfsd.exe`가 TCP/UDP `111`과 `2049`를 잡고 있어야 합니다.

## 결과 판정

부팅 후 화면 메시지를 확인하고 다음 명령으로 마무리합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\hanewin-nfs-provider.ps1 finish-attempt -Config .\windows\lab-10.73.json -Serial d80c0b88 -ConsoleText "HDMI screen text here"
```

해석:

- haneWIN NFS에서 부팅 성공: WinNFSd provider가 원인입니다.
- haneWIN NFS에서도 같은 init 실패: NTFS rootfs 표현 자체 또는 rootfs 복제 품질 문제 가능성이 커지고, 다음은 Linux NFS provider A/B입니다.
- 전원 재인가 후 DHCP 로그가 새로 안 찍힘: provider 판정 전 단계입니다. Pi 전원, SD 제거 상태, Ethernet link를 먼저 확인합니다.

## 상태 확인

```text
windows\RPI-Netboot-HaneWIN-NFS-Status-Admin.bat
```
