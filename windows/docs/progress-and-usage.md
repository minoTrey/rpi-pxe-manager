# 진행 상황과 사용법

## 현재 기준

- 실행 파일은 `RPI-Netboot-Manager.exe` 하나만 사용한다.
- 서버 PC 유선 이더넷은 `10.73.0.10/24` 기준이다.
- 공유기는 `10.73.0.1`, 운영 저장소는 GUI의 `저장소 설정`에서 선택한다.
- 부팅 파일은 `<저장소>\tftp`, rootfs는 `<저장소>\rootfs`에 둔다.
- 네트워크 부팅 대상은 RPi4다.
- Zero 2 W는 SD 부팅 + USB gadget 흐름으로 분리한다.

## 만들어진 것

- `lab-10.73.json` 기반 랩 설정.
- RPi4별 `<저장소>\tftp\<serial>` 및 `<저장소>\rootfs\<serial>` 구조.
- 한글 GUI 실행 파일 `RPI-Netboot-Manager.exe`.
- RPi4 EEPROM SD 준비 기능.
- Zero 2 W gadget SD 준비 기능.
- 새 RPi4 등록/복제 기능.
- 상태 점검, 서버 PC 준비, 부팅 서비스 시작 작업.

## 권장 실행 순서

1. `RPI-Netboot-Manager.exe` 실행.
2. `상태 확인`으로 PC, 저장소, 네트워크, 서비스 상태 확인.
3. 문제가 있으면 `서버 PC 준비` 실행.
4. `부팅 서비스 시작` 실행.
5. `RPi4 EEPROM SD`로 EEPROM SD 준비.
6. 첫 RPi4의 serial/MAC 확인.
7. 첫 RPi4의 bootfs를 `<저장소>\tftp\<serial>`에 준비.
8. 첫 RPi4의 rootfs를 `<저장소>\rootfs\<serial>`에 준비.
9. RPi4 전원을 다시 넣어 DHCP, TFTP, rootfs 부팅 흐름 확인.

## 관리자 권한

관리자 권한이 필요한 버튼은 같은 `RPI-Netboot-Manager.exe`가 UAC로 다시 열린다. 별도 관리자 실행 파일은 사용하지 않는다.

## 다음 집중 지점

첫 테스트 장비 `d80c0b88`의 `<저장소>\rootfs\d80c0b88`를 실제 Linux rootfs로 채우는 것이 다음 핵심 작업이다. 이 폴더가 비어 있거나 Linux rootfs 구조가 아니면 커널 이후 단계에서 부팅이 멈춘다.
