# 프로젝트 추적 도구 추천

날짜: 2026-05-15

## 결론

지금 이 프로젝트에는 다음 조합이 가장 좋습니다.

1. 바로 지금: 저장소 안의 Markdown 문서
2. 다음 단계: GitHub repository + Issues + Projects
3. 규모가 커지면: Linear 또는 Notion을 보조로 연결

이유는 단순합니다. 코드, 자동화 스크립트, 장비 상태, 작업 기록이 한 프로젝트 안에서 같이 움직여야 에이전트가 바뀌어도 맥락을 잃지 않습니다.

## 현재 적용한 실제 연결

2026-05-15 기준 실제 적용값은 다음과 같습니다.

- GitHub repository: `minoTrey/rpi-pxe-manager`
- Windows판 위치: `windows/`
- Linux판 위치: 기존 repo root
- GitHub branch: `agent/windows-netboot-manager`
- Draft PR: `https://github.com/minoTrey/rpi-pxe-manager/pull/1`
- Linear project: `RPI Netboot Windows`
- Linear issues:
  - `3D-5`: P0 rootfs 채우기
  - `3D-6`: rootfs 준비를 Windows manager/GUI에 연결
  - `3D-7`: Zero 2 W SD boot + USB gadget 흐름 분리
  - `3D-8`: 기존 GitHub repo에 Windows판 추가

새 repo를 만들지 않고 기존 repo에 Windows판을 추가하는 이유는, Linux판에서 Windows판으로 이어진 제품 히스토리가 같은 Git 기록 안에 남기 때문입니다.

현재 확인된 상태도 함께 기록합니다. GitHub connector에서 기존 `minoTrey/rpi-pxe-manager` repo를 확인했고, 사용자는 새 repo 대신 이 repo에 Windows판을 추가하기로 결정했습니다. Linear에는 `RPI Netboot Windows` 프로젝트와 남은 작업 이슈를 만들었습니다. 저장소 안 Markdown 문서는 세션 복구와 장비 상태 기록용 원장으로 계속 유지합니다.

## 지금 적용한 방식

현재 즉시 적용된 기록 체계:

- `docs/project-memory.md`: 가장 먼저 읽는 작업 원장
- `docs/worklog/YYYY-MM-DD-주제.md`: 날짜별 상세 작업 로그
- `docs/decisions/ADR-번호-주제.md`: 중요한 결정 기록
- `docs/current-test-status-ko.md`: 실제 장비 테스트 상태
- `README.md`: 주요 문서 진입점

이 방식은 인터넷 연결이나 외부 계정 없이도 바로 동작합니다.

## GitHub를 붙였을 때 권장 구조

GitHub를 쓰면 다음처럼 나눕니다.

| GitHub 기능 | 용도 |
| --- | --- |
| Issues | 모든 작업의 시작점 |
| Sub-issues | 큰 작업을 세부 작업으로 분해 |
| Projects | 여러 프로젝트/에이전트 작업을 한 화면에서 관리 |
| Pull Requests | 실제 변경의 감사 로그 |
| Actions | 빌드/테스트 자동 검증 |
| Releases/Tags | 의미 있는 완료 시점 기록 |
| Discussions | 아직 작업으로 확정되지 않은 아이디어 정리 |

추천 흐름:

```text
Discussion -> Issue -> Agent 작업 -> Draft PR -> Actions 검증 -> 사람 확인 -> Merge -> Release note
```

주의: Linux판과 Windows판은 같은 repo에 두되 폴더와 문서를 명확히 나눕니다. Linux판 루트 파일을 Windows 작업 때문에 깨뜨리지 않고, Windows판 변경은 `windows/` 아래에 집중합니다.

## 이 프로젝트에 맞는 GitHub Issue 라벨

| 라벨 | 의미 |
| --- | --- |
| `agent-task` | 에이전트에게 맡길 작업 |
| `hardware-test` | 실제 RPi/서버 PC 테스트 |
| `network` | IP, DHCP, TFTP, NFS, 공유기 |
| `rootfs` | rootfs 복제/마운트 |
| `gui` | Windows GUI |
| `docs` | 문서/도움말 |
| `zero2w-gadget` | Zero 2 W USB gadget |
| `blocked` | 사용자 장비 조작이나 외부 조건 대기 |

## 선택지 비교

| 도구 | 추천도 | 장점 | 주의점 |
| --- | --- | --- | --- |
| GitHub Issues/Projects | 가장 추천 | 코드와 작업 기록이 붙어 있음. PR/Actions와 연결됨. | 처음 라벨/템플릿 세팅이 필요함. |
| Linear | 선택 | 이슈 관리 UX가 좋고 GitHub PR과 잘 연결됨. | GitHub와 이중 관리가 될 수 있음. |
| Notion | 선택 | 예쁜 대시보드와 설명 문서에 좋음. | 코드 변경 기록의 원장으로 쓰기엔 약함. |
| Obsidian | 개인용 선택 | Markdown 기반 개인 지식베이스로 좋음. | 협업/작업 추적은 GitHub보다 약함. |

## 현재 외부 도구 확인 결과

- GitHub: `minoTrey/rpi-pxe-manager` repo 사용
- GitHub 구조: Linux판은 repo root, Windows판은 `windows/`
- Linear: project `RPI Netboot Windows`
- Linear: issues `3D-5`, `3D-6`, `3D-7`, `3D-8`
- 운영 판단: GitHub/Linear와 저장소 문서를 함께 사용하되, 실제 장비 상태는 `docs/current-test-status-ko.md`를 우선

## GitHub/Linear에 올릴 남은 작업 후보

| 라벨 | 작업 |
| --- | --- |
| `rootfs` | `D:\rootfs\d80c0b88`에 실제 Raspberry Pi OS rootfs 준비 |
| `gui` | rootfs 준비 기능을 GUI 버튼과 상태 점검에 연결 |
| `zero2w-gadget` | Zero 2 W SD 부팅 + USB gadget 준비 흐름을 RPi4 netboot 흐름과 분리 |
| `hardware-test` | rootfs 준비 후 RPi4 한 대를 SD 없이 NFS root까지 완전 부팅 검증 |

정책 메모: RPi4만 Ethernet netboot 대상입니다. Zero 2 W는 SD 부팅 + USB gadget mode 장치로 준비하며, 네트워크 부팅 대상 목록에 넣지 않습니다.

## 권장 운영 규칙

1. 중요한 작업은 먼저 Issue 또는 `docs/worklog`에 기록합니다.
2. 장비 상태가 바뀌면 `docs/current-test-status-ko.md`를 업데이트합니다.
3. 방향이 바뀌면 ADR을 추가합니다.
4. 에이전트에게 맡긴 작업은 결과 파일과 남은 blocker를 `docs/project-memory.md`에 합칩니다.
5. GUI/스크립트 변경 후에는 README와 HTML 도움말에서 진입점을 확인합니다.

## 참고 링크

- GitHub Issues/Projects planning docs: https://docs.github.com/en/issues/tracking-your-work-with-issues/learning-about-issues/planning-and-tracking-work-for-your-team-or-project
- GitHub issue creation and CLI: https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-an-issue
- Linear GitHub integration: https://linear.app/docs/github-integration
- Notion Projects and Tasks: https://www.notion.com/en-gb/help/guides/getting-started-with-projects-and-tasks
- ADR guide: https://mitlibraries.github.io/guides/misc/adr.html
