# RPI Netboot Knowledge Base

이 폴더는 작업 흐름을 까먹지 않기 위한 파일 기반 운영 기록입니다.

- `obsidian-vault/`: Obsidian에서 그대로 열 수 있는 vault입니다.
- `gbrain/graph.json`: 사람, 장비, provider, 시도, 결정의 관계 그래프입니다.
- `hermes/events.jsonl`: append-only 이벤트 로그입니다.

운영 원칙:

1. 실제 증거는 `D:\logs\netboot-harness\...`에 보관합니다.
2. 요약과 의사결정은 `windows/docs/`와 `windows/knowledge/obsidian-vault/`에 남깁니다.
3. GitHub PR과 Linear 이슈에는 최신 commit, verdict, 다음 액션만 짧게 업데이트합니다.
4. 새 netboot attempt가 끝나면 `current-test-status-ko.md`, 해당 날짜 worklog, Hermes 이벤트 로그를 함께 갱신합니다.
