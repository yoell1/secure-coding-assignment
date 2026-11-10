# =====================================================================
#  시큐어 코딩 적용 과제 - 자동 검증 스크립트
#  REPORT.md에 적은 공격을 실제로 보내고, 막혔는지 PASS / FAIL로 보여 준다.
#  코드를 바꾼 뒤 다시 돌리면, 고친 취약점이 다시 열렸는지 바로 알 수 있다 (보안 회귀 테스트).
#
#  사용법 (프로젝트 루트에서)
#    1) 앱 실행:   .\mvnw.cmd spring-boot:run   (환경 변수 ASSIGN_DB_PASSWORD, ASSIGN_AES_KEY 필요)
#    2) 다른 터미널에서:
#       powershell -ExecutionPolicy Bypass -File .\verify\check.ps1 -ResetDb
#
#  -ResetDb: 검사 전과 후에 sql/01_schema.sql을 sqlplus로 자동 실행해 DB를 초기화한다.
#            sqlplus(Oracle XE에 포함)와 환경 변수 ASSIGN_DB_PASSWORD가 필요하다.
#            빼고 실행하면 DB 초기화는 직접 한다. (동시 상환·가입 확인 때문에 데이터가 바뀜)
#  이 스크립트에는 비밀번호나 키 값이 들어 있지 않다.
# =====================================================================

param([switch]$ResetDb)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$base = "http://localhost:8080"
$work = Join-Path $env:TEMP ("sc-verify-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory $work | Out-Null
$jar  = Join-Path $work "cookie.txt"
$body = Join-Path $work "body.txt"
$head = Join-Path $work "head.txt"
$XRW  = "X-Requested-With: XMLHttpRequest"

$results = New-Object System.Collections.ArrayList
$pass = 0; $fail = 0

function Req([string]$method, [string]$url, [string[]]$extra = @()) {
    if (Test-Path $body) { Remove-Item $body }
    if (Test-Path $head) { Remove-Item $head }
    $args2 = @("-s", "-b", $jar, "-c", $jar, "-D", $head, "-o", $body, "-w", "%{http_code}", "-X", $method) + $extra + @($url)
    $code = & curl.exe @args2
    $b = ""; $h = ""
    if (Test-Path $body) { $b = [IO.File]::ReadAllText($body, [Text.Encoding]::UTF8) }
    if (Test-Path $head) { $h = [IO.File]::ReadAllText($head) }
    return @{ code = [int]$code; body = $b; head = $h }
}

function Check([string]$area, [string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { $script:pass++; $mark = "PASS" } else { $script:fail++; $mark = "FAIL" }
    [void]$script:results.Add([pscustomobject]@{ 결과 = $mark; 영역 = $area; 확인 = $name; 실제 = $detail })
    $color = if ($ok) { "Green" } else { "Red" }
    Write-Host ("[{0}] {1,-6} {2}  ->  {3}" -f $mark, $area, $name, $detail) -ForegroundColor $color
}

function JsonFile([string]$text) {
    $f = Join-Path $work ("req-" + [guid]::NewGuid().ToString("N").Substring(0, 6) + ".json")
    [IO.File]::WriteAllText($f, $text, (New-Object System.Text.UTF8Encoding($false)))
    return $f
}


# --- DB 초기화 (sqlplus) ------------------------------------------------------
$schema = Join-Path $PSScriptRoot "..\sql\01_schema.sql"
function Reset-Db([string]$when) {
    if (-not $ResetDb) { return $true }
    $ErrorActionPreference = "Continue"   # sqlplus 경고 출력 때문에 멈추지 않게
    if (-not (Get-Command sqlplus -ErrorAction SilentlyContinue)) {
        Write-Host "[$when] sqlplus를 찾을 수 없어 DB 초기화를 건너뜁니다. SQL Developer에서 01_schema.sql을 직접 실행해 주세요." -ForegroundColor Yellow
        return $true
    }
    if (-not $env:ASSIGN_DB_PASSWORD) {
        Write-Host "[$when] 환경 변수 ASSIGN_DB_PASSWORD가 없어 DB 초기화를 건너뜁니다." -ForegroundColor Yellow
        return $true
    }
    $path = (Resolve-Path $schema).Path
    $oldNls = $env:NLS_LANG
    $env:NLS_LANG = "KOREAN_KOREA.AL32UTF8"   # 01_schema.sql(UTF-8)의 한글을 깨지지 않게 읽음
    # 비밀번호는 명령줄이 아니라 표준 입력으로 넘긴다 (프로세스 목록에 남지 않게)
    $cmds = "connect C##SECURE/$($env:ASSIGN_DB_PASSWORD)@//localhost:1521/XE`n" +
            "whenever sqlerror continue`n@`"$path`"`n" +
            "set heading off feedback off pagesize 0`n" +
            "select 'COUNT:' || (select count(*) from customer) || ':' || (select count(*) from loan) from dual;`nexit`n"
    $out = $cmds | sqlplus -S /nolog 2>&1 | Out-String
    $env:NLS_LANG = $oldNls

    # DROP 단계의 "테이블 없음"은 PL/SQL 블록에서 무시되므로, 남은 ORA- 는 모두 실제 오류다
    $errors = ($out -split "`r?`n" | Where-Object { $_ -match "ORA-\d+|SP2-\d+" }) | Select-Object -Unique
    $count = if ($out -match "COUNT:(\d+):(\d+)") { "고객 $($Matches[1])명 / 대출 $($Matches[2])건" } else { "건수 확인 실패" }
    if ($errors -or ($out -notmatch "COUNT:3:4")) {
        Write-Host "[$when] DB 초기화 실패 ($count)" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        Write-Host "    SQL Developer에서 sql/01_schema.sql을 직접 실행해 주세요." -ForegroundColor Red
        return $false
    }
    Write-Host "[$when] DB 초기화 완료 ($count)" -ForegroundColor DarkGray
    return $true
}

# --- SQL 한 줄 실행 (sqlplus) -------------------------------------------------
# 검사용으로 데이터 값만 바꿀 때 쓴다. 스키마는 바꾸지 않고, 끝난 뒤 -ResetDb가 초기화한다.
function Invoke-Sql([string]$sql) {
    $ErrorActionPreference = "Continue"
    $cmds = "connect C##SECURE/$($env:ASSIGN_DB_PASSWORD)@//localhost:1521/XE`n" +
            "set heading off feedback off pagesize 0`n$sql`nexit`n"
    $out = $cmds | sqlplus -S /nolog 2>&1 | Out-String
    return -not ($out -match "ORA-\d+|SP2-\d+")
}

# --- 0. 앱이 켜져 있는지 -------------------------------------------------
$ping = Req "GET" "$base/login-page"
if ($ping.code -ne 200) {
    Write-Host "앱에 연결할 수 없습니다. .\mvnw.cmd spring-boot:run 으로 앱을 먼저 켜 주세요." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "=== 시큐어 코딩 적용 과제 자동 검증 ===" -ForegroundColor Cyan
Write-Host ""
if (-not (Reset-Db "시작 전")) { exit 1 }

# --- 로그인 없이 접근 ----------------------------------------------------
$r = Req "GET" "$base/api/loans/1001"
Check "[2]" "로그인 없이 대출 조회 -> 401" ($r.code -eq 401) "HTTP $($r.code)"

# --- 로그인 (C001) -------------------------------------------------------
$r = Req "POST" "$base/login?customerId=C001"
Check "준비" "C001 로그인" ($r.code -eq 200) "HTTP $($r.code)"
# 쿠키 속성 확인: 쿠키 없이 새로 로그인해서 처음 발급되는 Set-Cookie를 본다
$freshHead = (& curl.exe -s -D - -o NUL -X POST "$base/login?customerId=C001") -join "`n"
$cookieLine = ($freshHead -split "`r?`n" | Where-Object { $_ -match "^Set-Cookie:\s*JSESSIONID" }) -join " "
Check "추가6" "로그인 쿠키 SameSite=Lax, HttpOnly" (($cookieLine -match "SameSite=Lax") -and ($cookieLine -match "HttpOnly")) ($cookieLine -replace "JSESSIONID=[^;]+", "JSESSIONID=***")

# --- [1] SQL 삽입 --------------------------------------------------------
$r = Req "GET" "$base/api/loans?customerId=C001%27%20OR%20%271%27%3D%271"
Check "[1]" "customerId에 ' OR '1'='1 -> 타인 대출 노출 없음" (($r.code -ne 200) -and ($r.body -notmatch "C002")) "HTTP $($r.code)"
$r = Req "GET" "$base/api/loans/sorted?customerId=C001&sortBy=nosuch"
Check "[1]" "sortBy=nosuch -> 400, SQL 노출 없음" (($r.code -eq 400) -and ($r.body -notmatch "ORA-|SELECT")) "HTTP $($r.code) $($r.body)"
$r = Req "GET" "$base/api/loans/sorted?customerId=C001&sortBy=balance"
Check "[1]" "sortBy=balance -> 정상 정렬" ($r.code -eq 200) "HTTP $($r.code)"

# --- [2] IDOR ------------------------------------------------------------
$r1 = Req "GET" "$base/api/loans/1002"
$r2 = Req "GET" "$base/api/loans/9999"
Check "[2]" "남의 대출 1002 -> 404" ($r1.code -eq 404) "HTTP $($r1.code)"
Check "[2]" "없는 대출 9999 -> 404, 남의 것과 응답 동일" (($r2.code -eq 404) -and ($r1.body -eq $r2.body)) "HTTP $($r2.code)"
$r = Req "GET" "$base/api/loans/1001"
Check "[2]" "본인 대출 1001 -> 정상 조회" (($r.code -eq 200) -and ($r.body -match "1001")) "HTTP $($r.code)"
$r = Req "GET" "$base/api/loans?customerId=C002"
Check "추가4" "남의 대출 목록 C002 -> 404" ($r.code -eq 404) "HTTP $($r.code)"
$r = Req "GET" "$base/api/loans/sorted?customerId=C002&sortBy=balance"
Check "추가4" "남의 대출 정렬 조회 C002 -> 404" ($r.code -eq 404) "HTTP $($r.code)"
$r = Req "POST" "$base/api/loans/1002/repay?amount=1000" @("-H", $XRW)
Check "[2]" "남의 대출 1002 상환 -> 실패" ($r.body -match '"success"\s*:\s*false') "HTTP $($r.code) $($r.body)"

# --- [3] 민감정보 ---------------------------------------------------------
$r = Req "GET" "$base/api/customers/C001"
Check "[3]" "본인 정보: 주민번호·전화번호 마스킹" (($r.code -eq 200) -and ($r.body -match "rrnMasked") -and ($r.body -notmatch "1234567") -and ($r.body -notmatch "1111-2222")) $r.body
Check "[3]" "응답에 passwordHash 필드 없음" ($r.body -notmatch "passwordHash") "필드 목록 확인"
$r = Req "GET" "$base/api/customers/C002"
Check "[3]" "남의 고객 정보 C002 -> 404" ($r.code -eq 404) "HTTP $($r.code)"

# --- [4] 에러 처리 --------------------------------------------------------
$r = Req "GET" "$base/api/interest?principal=1000000&rate=abc"
Check "[4]" "rate=abc -> 400, 예외 이름 노출 없음" (($r.code -eq 400) -and ($r.body -notmatch "Exception|java\.")) "HTTP $($r.code) $($r.body)"
$r = Req "GET" "$base/api/interest?principal=abc&rate=0.035"
Check "추가2" "숫자 자리에 글자 -> 400" ($r.code -eq 400) "HTTP $($r.code)"
$r = Req "GET" "$base/nothing"
Check "추가2" "없는 주소 -> 404" ($r.code -eq 404) "HTTP $($r.code)"
$r = Req "GET" "$base/login?customerId=C001"
Check "추가2" "메서드가 틀림 (GET /login) -> 405" ($r.code -eq 405) "HTTP $($r.code)"
$f = JsonFile "hello"
$r = Req "POST" "$base/api/signup" @("-H", "Content-Type: text/plain", "--data-binary", "@$f")
Check "추가2" "형식이 틀림 (text/plain 가입) -> 415" ($r.code -eq 415) "HTTP $($r.code)"
$f = JsonFile '{"customerId":'
$r = Req "POST" "$base/api/signup" @("-H", "Content-Type: application/json", "--data-binary", "@$f")
Check "추가2" "깨진 JSON 가입 -> 400, 예외 이름 노출 없음" (($r.code -eq 400) -and ($r.body -notmatch "Exception")) "HTTP $($r.code) $($r.body)"

# --- [5] 입력값 검증 -------------------------------------------------------
$f = JsonFile '{"customerId":"C2''--","customerName":"<script>alert(1)</script>","rrn":"not-a-rrn","phone":"123","password":"1234"}'
$r = Req "POST" "$base/api/signup" @("-H", "Content-Type: application/json", "--data-binary", "@$f")
Check "[5]" "잘못된 가입 값 5개 -> 400" ($r.code -eq 400) "HTTP $($r.code) $($r.body)"
$f = JsonFile '{"customerId":"C001","customerName":"Park","rrn":"950101-1234567","phone":"010-1234-5678","password":"Passw0rd!23"}'
$r = Req "POST" "$base/api/signup" @("-H", "Content-Type: application/json", "--data-binary", "@$f")
Check "추가3" "이미 있는 ID(C001)로 가입 -> 409" ($r.code -eq 409) "HTTP $($r.code)"
$newId = "V" + (Get-Random -Minimum 100000 -Maximum 999999)
$f = JsonFile ('{"customerId":"' + $newId + '","customerName":"Park","rrn":"950101-1234567","phone":"010-1234-5678","password":"Passw0rd!23"}')
$r = Req "POST" "$base/api/signup" @("-H", "Content-Type: application/json", "--data-binary", "@$f")
Check "[5]" "정상 가입 ($newId) -> 성공" (($r.code -eq 200) -and ($r.body -match $newId)) "HTTP $($r.code)"
# 추가11: 암호화해 저장한 가입 고객도 조회하면 복호화 후 마스킹된 주민번호가 보여야 한다
$r = Req "POST" "$base/login?customerId=$newId"
$r = Req "GET" "$base/api/customers/$newId"
Check "추가11" "가입 고객 $newId 주민번호 복호화 후 마스킹 -> 950101-1******" ($r.body -match '"rrnMasked"\s*:\s*"950101-1\*{6}"') $r.body
$r = Req "POST" "$base/login?customerId=C001"   # 다시 C001로

# --- [6] 설정 파일 ----------------------------------------------------------
$props = Join-Path $PSScriptRoot "..\src\main\resources\application.properties"
if (Test-Path $props) {
    $p = [IO.File]::ReadAllText((Resolve-Path $props), [Text.Encoding]::UTF8)
    Check "[6]" "DB 비밀번호·AES 키는 환경 변수 참조만" (($p -match "password=\$\{ASSIGN_DB_PASSWORD\}") -and ($p -match "aes-key=\$\{ASSIGN_AES_KEY\}")) "application.properties"
}

# --- [7] 금액 계산 / 동시성 --------------------------------------------------
$r = Req "GET" "$base/api/interest?principal=1000000&rate=0.035"
Check "[7]" "월 이자 (100만 원, 3.5%) -> 2917" ($r.body -match '"monthlyInterest"\s*:\s*2917') $r.body
$r = Req "GET" "$base/api/interest?principal=1000000&rate=-1"
Check "[7]" "음수 금리 -> 400" ($r.code -eq 400) "HTTP $($r.code)"
$r = Req "POST" "$base/api/loans/1001/repay?amount=-1000000" @("-H", $XRW)
Check "[7]" "음수 상환 -> 400" ($r.code -eq 400) "HTTP $($r.code)"
$r = Req "GET" "$base/api/loans/1001"
$bal = 0; if ($r.body -match '"balance"\s*:\s*(\d+)') { $bal = [long]$Matches[1] }
$r = Req "POST" "$base/api/loans/1001/repay?amount=$($bal + 1)" @("-H", $XRW)
Check "[7]" "잔액보다 1원 많은 상환 -> 실패" ($r.body -match '"success"\s*:\s*false') "잔액 $bal, 요청 $($bal + 1) -> $($r.body)"

$r = Req "GET" "$base/api/loans/1004"
$before = [long]((ConvertFrom-Json $r.body).balance)
$amount = 1000000
$expected = [long][math]::Floor($before / $amount)
$n = $expected + 2
$raw = & curl.exe -s -b $jar -H $XRW --parallel --parallel-immediate --parallel-max 50 -X POST "$base/api/loans/1004/repay?amount=$amount&n=[1-$n]"
$joined = ($raw -join "")
$ok = ([regex]::Matches($joined, '"success"\s*:\s*true')).Count
$no = ([regex]::Matches($joined, '"success"\s*:\s*false')).Count
$r = Req "GET" "$base/api/loans/1004"
$after = [long]((ConvertFrom-Json $r.body).balance)
Check "[7]" "1004에 100만 원 상환 ${n}건 동시 -> 성공 ${expected}건" ($ok -eq $expected) "성공 $ok / 실패 $no"
Check "[7]" "동시 상환 후 잔액 = 처음 잔액 - 성공 x 100만 원" ($after -eq ($before - $ok * $amount)) ("{0:N0} -> {1:N0}" -f $before, $after)

# --- [8] XSS / CSRF --------------------------------------------------------
$r = Req "GET" "$base/search?q=%3Cimg%20src%3Dx%20onerror%3Dalert(1)%3E"
Check "[8]" "XSS: 검색어가 태그로 실행되지 않음" (($r.body -notmatch "<img src=x onerror") -and ($r.body -match "&lt;img")) "&lt;img ... 로 이스케이프됨"
Check "[8]" "XSS: innerHTML 대신 textContent" (($r.body -match "textContent") -and ($r.body -notmatch "innerHTML")) "search.jsp 스크립트"

$r = Req "GET" "$base/repay-form"
$hasToken = $r.body -match 'name="_csrf"'
Check "[8]" "상환 폼에 CSRF 토큰 숨은 칸" $hasToken "_csrf"
Check "추가5" "상환 폼 클릭재킹 방지 헤더" (($r.head -match "X-Frame-Options:\s*DENY") -and ($r.head -match "frame-ancestors 'none'")) "X-Frame-Options / CSP"
# 추가10: 상환 폼이 아닌 화면·API에도 보안 헤더가 붙는지 (SecurityHeaderFilter)
$hdrOk = $true; $hdrMiss = @()
foreach ($u in @("/login-page", "/search?q=a", "/api/loans/1001")) {
    $h = (Req "GET" "$base$u").head
    if (-not (($h -match "X-Frame-Options:\s*DENY") -and ($h -match "frame-ancestors 'none'") -and ($h -match "X-Content-Type-Options:\s*nosniff"))) { $hdrOk = $false; $hdrMiss += $u }
}
Check "추가10" "모든 화면·API에 보안 헤더 (로그인 화면, 검색, 대출 API)" $hdrOk $(if ($hdrOk) { "X-Frame-Options / CSP / nosniff" } else { "빠짐: " + ($hdrMiss -join ", ") })
# 추가13: 개인정보 응답이 브라우저·프록시 캐시에 남지 않게 (Cache-Control: no-store)
$h = (Req "GET" "$base/api/customers/C001").head
Check "추가13" "고객 조회 응답에 Cache-Control: no-store" ($h -match "Cache-Control:\s*no-store") $(if ($h -match "(Cache-Control:[^\r\n]*)") { $Matches[1] } else { "헤더 없음" })
$token = ""
if ($r.body -match 'name="_csrf"\s+value="([0-9a-f]+)"') { $token = $Matches[1] }

$r = Req "POST" "$base/repay-form" @("-d", "loanId=1001", "-d", "amount=1000")
Check "[8]" "토큰 없이 상환 폼 전송 (CSRF 공격) -> 403" ($r.code -eq 403) "HTTP $($r.code)"
$r = Req "POST" "$base/repay-form" @("-d", "loanId=1001", "-d", "amount=1000", "-d", "_csrf=$token")
Check "[8]" "올바른 토큰으로 상환 -> 성공" ($r.body -match "true") $r.body
# 추가12: 한 번 쓴 토큰은 폐기되어야 한다 (같은 토큰으로 다시 보내면 403)
$r = Req "POST" "$base/repay-form" @("-d", "loanId=1001", "-d", "amount=1000", "-d", "_csrf=$token")
Check "추가12" "같은 토큰으로 다시 상환 (토큰 재사용) -> 403" ($r.code -eq 403) "HTTP $($r.code)"

$r = Req "POST" "$base/api/loans/1001/repay?amount=1000"
Check "추가1" "헤더 없이 상환 API 호출 (CSRF 공격) -> 403" ($r.code -eq 403) "HTTP $($r.code)"
$r = Req "POST" "$base/api/loans/1001/repay?amount=1000" @("-H", $XRW)
Check "추가1" "헤더를 붙인 정상 상환 API -> 성공" ($r.body -match '"success"\s*:\s*true') $r.body

# --- 추가7 해지된 대출 상환 (-ResetDb 일 때만) ---------------------------------
# 1001을 CLOSED로 바꾼 뒤 상환해 본다. 데이터 값만 바꾸고, 끝난 뒤 초기화로 되돌린다.
if ($ResetDb -and (Get-Command sqlplus -ErrorAction SilentlyContinue) -and $env:ASSIGN_DB_PASSWORD) {
    if (Invoke-Sql "update loan set status = 'CLOSED' where loan_id = 1001;`ncommit;") {
        $r = Req "POST" "$base/api/loans/1001/repay?amount=1000" @("-H", $XRW)
        Check "추가7" "해지(CLOSED)된 대출 1001 상환 -> 실패" ($r.body -match '"success"\s*:\s*false') $r.body
    } else {
        Check "추가7" "해지(CLOSED)된 대출 1001 상환 -> 실패" $false "1001 상태 변경 실패 (sqlplus 오류)"
    }
} else {
    Write-Host "[SKIP] 추가7  해지된 대출 상환 검사는 -ResetDb 로 실행할 때만 합니다." -ForegroundColor DarkGray
}

# --- 결과 요약 ---------------------------------------------------------------
Write-Host ""
$total = $pass + $fail
$color = if ($fail -eq 0) { "Green" } else { "Red" }
Write-Host ("=== 결과: {0} / {1} 통과 ===" -f $pass, $total) -ForegroundColor $color
if ($ResetDb) {
    $null = Reset-Db "끝난 뒤"
} else {
    Write-Host "DB 데이터가 바뀌었습니다(1001·1004 잔액, 가입 $newId). sql/01_schema.sql로 다시 초기화해 주세요." -ForegroundColor Yellow
    Write-Host "다음부터는 -ResetDb 를 붙이면 자동으로 초기화합니다." -ForegroundColor Yellow
}

Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
if ($fail -gt 0) { exit 1 }
