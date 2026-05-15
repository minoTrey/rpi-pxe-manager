# ADR-0001: 작업 기억장과 프로젝트 추적 방식

상태: 채택

날짜: 2026-05-15

## Context

이 프로젝트는 Windows 서버 PC, RPi4 netboot, Zero 2 W USB gadget, GUI 자동화, 네트워크 설정, SD카드 준비, rootfs 복제, 여러 에이전트 조사 작업이 동시에 섞입니다. 사용자가 작업 중간에 인터럽트를 많이 넣었고, 실제 장비 상태도 계속 변하기 때문에 채팅 기록만 믿으면 다음 단계가 쉽게 흐려집니다.

## Decision

즉시 적용하는 기준은 in-repo Markdown 문서입니다.

- `docs/project-memory.md`: 항상 먼저 읽는 프로젝트 기억장
- `docs/worklog/YYYY-MM-DD-주제.md`: 날짜별 상세 작업 로그
- `docs/decisions/ADR-번호-주제.md`: 중요한 결정과 이유

GitHub를 연결하면 다음 방식으로 확장합니다.

- GitHub Issues: 모든 작업의 시작점
- GitHub Projects: 여러 프로젝트와 에이전트 작업의 대시보드
- Pull Requests: 실제 변경의 감사 로그
- Releases/Tags: 의미 있는 완료 지점 기록
- Discussions: 아직 작업으로 확정되지 않은 아이디어와 방향성 논의

## Consequences

장점:

- 에이전트가 바뀌어도 이어받을 수 있습니다.
- 사용자가 “어디까지 했는지” 바로 확인할 수 있습니다.
- 코드 변경, 장비 상태, 결정 이유를 한 저장소 안에서 추적할 수 있습니다.
- 나중에 GitHub Issues/Projects로 옮기기 쉽습니다.

비용:

- 큰 변경을 할 때마다 문서를 같이 업데이트해야 합니다.
- 문서가 오래되면 오히려 혼란을 줄 수 있으므로 `project-memory.md`를 최신 기준으로 유지해야 합니다.

## References

- GitHub: planning and tracking work with issues/projects - https://docs.github.com/en/issues/tracking-your-work-with-issues/learning-about-issues/planning-and-tracking-work-for-your-team-or-project
- GitHub CLI issue creation - https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-an-issue
- Linear GitHub integration - https://linear.app/docs/github-integration
- Notion Projects and Tasks - https://www.notion.com/en-gb/help/guides/getting-started-with-projects-and-tasks
- ADR guide - https://mitlibraries.github.io/guides/misc/adr.html

