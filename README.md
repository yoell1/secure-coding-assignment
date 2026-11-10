# secure-coding-assignment — 시큐어 코딩 적용 과제

금융권 보안 코딩 과정의 적용 과제입니다. **일부러 취약하게 만든 Spring Boot 프로젝트를 받아, 소스 전체를 점검해 취약점을 찾아 고친 결과물**입니다.

> 이 저장소의 코드는 **수정이 끝난 상태**입니다. 취약점 재현 화면은 기록 목적으로 `docs/screenshots/` 에 남겨두었습니다.

- 제출일 2026-11-05 · 작성자 이우진
- 수정 내역 전체 → **[REPORT.md](REPORT.md)**
- 원본 과제 안내문 → [docs/과제안내_원본.md](docs/과제안내_원본.md)

## 결과

| 항목 | 결과 |
|---|---|
| 과제 지정 영역 | 8개 영역 전부 수정 |
| 추가로 발견한 취약점 | 13개 발견 → 12개 수정 (1건은 수정 금지 파일이라 기록만) |
| 자가 점검 테스트 | **21 / 21 통과** |
| 자동 점검 스크립트 (`verify/check.ps1`) | **44 / 44 통과** |
| SpotBugs 우선순위 1 | 5건 → **0건** |

## 고친 취약점

| 영역 | 내용 |
|---|---|
| SQL 삽입 | 문자열 연결 쿼리를 파라미터 바인딩으로 교체 |
| IDOR | 남의 대출 번호로 조회·상환되던 경로를 소유자 조건으로 차단 |
| 민감정보 노출 | 주민번호 AES 암호화 + 마스킹, 응답 전용 객체(`CustomerView`) 분리 |
| 에러 처리 | 예외 메시지가 그대로 응답에 실리던 것을 공통 핸들러로 차단 |
| 입력값 검증 | 금액·이자율의 타입·범위 검증, 음수·문자 입력 차단 |
| 해시·암호화·키 | 비밀번호 해시 적용, DB 비밀번호와 AES 키를 환경 변수로 분리 |
| 이자 계산 | 부동소수점 오차와 음수 상환 처리 수정 |
| XSS · CSRF | 출력 이스케이프, CSRF 토큰, 보안 헤더 필터(`SecurityHeaderFilter`) 추가 |

각 항목의 재현 방법 · 수정 전후 코드 · 확인 화면은 `REPORT.md` 에 정리되어 있습니다.

## 기술 스택

Java 17 · Spring Boot 3.3 · Spring MVC · MyBatis · Oracle 21c XE · JSP/JSTL · Maven · JUnit · SpotBugs

## 실행 방법

비밀번호와 키는 코드에 넣지 않고 환경 변수로만 받습니다. 값이 없으면 애플리케이션이 뜨지 않습니다.

```powershell
$env:ASSIGN_DB_PASSWORD = "<DB 비밀번호>"

# AES-128 키(Base64) 생성
$b = New-Object byte[] 16
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
$env:ASSIGN_AES_KEY = [Convert]::ToBase64String($b)
```

1. `sql/01_schema.sql` 실행 (테이블 생성 및 초기 데이터)
2. `./mvnw spring-boot:run`

## 폴더

| 경로 | 내용 |
|---|---|
| `src/main/java/edu/secure/assign/` | 애플리케이션 코드 |
| `src/test/` | 자가 점검 테스트 21개 |
| `verify/check.ps1` | 자동 점검 스크립트 44개 검사 |
| `docs/screenshots/` | 취약점 재현 및 수정 확인 화면 |
| `attack/csrf-attack.html` | CSRF 재현용 페이지 |
| `sql/01_schema.sql` | 스키마 및 초기 데이터 |

---

모든 데이터는 가상 데이터이며, 실제 개인정보는 포함되어 있지 않습니다.
