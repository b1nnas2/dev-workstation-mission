#!/usr/bin/env bash
# ==========================================================================
# 미션 전체 실습을 한 번에 실행하고, "명령어 + 출력"을 logs/*.txt 로 저장한 뒤
# README.md 의 <!-- LOG:이름 --> 블록에 자동으로 붙여 넣는 스크립트.
#
# 사용법 (저장소 루트에서, Docker Desktop/OrbStack 실행 중인 상태):
#   bash scripts/collect_evidence.sh            # 전체 실행
#   bash scripts/collect_evidence.sh git        # 특정 섹션만 다시 실행 (예: push 후 git 증거)
#   bash scripts/collect_evidence.sh embed      # README 에 로그만 다시 붙이기
#   bash scripts/collect_evidence.sh clean      # 실습 컨테이너/볼륨 정리
#
# 지원 환경: Windows Git Bash / macOS(OrbStack, Docker Desktop) / Linux
# ==========================================================================
set -u
export MSYS_NO_PATHCONV=1          # Git Bash 의 /경로 자동 변환 방지 (트러블슈팅 #5)

cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"
HOST_ROOT="$(pwd -W 2>/dev/null || pwd)"   # Windows Git Bash 면 C:/Users/... 형태 (docker -v 용 절대경로)
LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"
IMAGE="my-web:1.0"
LOG=""

section() { LOG="$LOG_DIR/$1.txt"; : > "$LOG"; echo "▶ $1 수집 중..."; }
note()    { printf '# %s\n' "$*" >> "$LOG"; }
run()     { printf '$ %s\n' "$*" >> "$LOG"; eval "$*" >> "$LOG" 2>&1; printf '\n' >> "$LOG"; }
quiet()   { "$@" >/dev/null 2>&1; }

need_docker() {
  if ! docker info >/dev/null 2>&1; then
    echo "!! Docker 데몬에 연결할 수 없습니다. Docker Desktop(또는 OrbStack)을 먼저 실행하세요." >&2
    exit 1
  fi
}

clean() {
  quiet docker rm -f hello-test ubuntu-test ubuntu-oneshot attach-test \
                     web-8080 web-8082 web-bind web-conflict vol-test vol-test2
  quiet docker volume rm -f mydata mydata-restore
  rm -rf "$ROOT/backup"
}

# --------------------------------------------------------------------------
s_env() {
  section 00_env
  run 'uname -a'
  run 'echo "SHELL=$SHELL"'
  run 'bash --version | head -n 1'
  run 'docker --version'
  run 'git --version'
}

s_terminal() {
  section 01_terminal
  rm -rf "$ROOT/practice"
  note '현재 위치 / 숨김 파일 포함 목록'
  run 'pwd'
  run 'ls -la'
  note '디렉토리 생성 후 이동 (상대 경로)'
  run 'mkdir -p practice/sub'
  run 'cd practice'
  run 'pwd'
  note '빈 파일 생성 / 내용 작성 / 내용 확인'
  run 'touch empty.txt'
  run 'echo "Linux CLI Practice" > sample.txt'
  run 'cat sample.txt'
  run 'ls -la'
  note '복사 -> 이름 변경 -> 다른 폴더로 이동'
  run 'cp sample.txt copy.txt'
  run 'mv copy.txt renamed.txt'
  run 'mv renamed.txt sub/'
  run 'ls -la . sub'
  note '삭제 (파일 -> 빈 디렉토리)'
  run 'rm sub/renamed.txt'
  run 'rmdir sub'
  run 'ls -la'
  note '절대 경로로 저장소 루트 복귀'
  run "cd \"$ROOT\""
  run 'pwd'
}

s_permission() {
  section 02_permission
  note '[A] 호스트(Windows Git Bash, NTFS)에서 시도 -> 권한 비트가 바뀌지 않음 (트러블슈팅 #2)'
  note '    macOS/Linux 호스트에서는 정상적으로 바뀜'
  run 'touch practice/perm_host.txt && ls -l practice/perm_host.txt'
  run 'chmod 755 practice/perm_host.txt && ls -l practice/perm_host.txt'
  note '[B] Linux(ubuntu) 컨테이너 안에서 파일 1개 + 디렉토리 1개 권한 변경 실험'
  run 'tr -d "\r" < scripts/perm_lab.sh | docker run --rm -i ubuntu bash'
}

s_docker_check() {
  section 03_docker_check
  run 'docker --version'
  run 'docker version --format "Client {{.Client.Version}} / Server {{.Server.Version}} ({{.Server.Os}}/{{.Server.Arch}})"'
  note 'docker info: Server 섹션이 출력되면 데몬이 정상 동작 중'
  run 'docker info | sed -E "s/(Username: ).*/\1***masked***/"'
}

s_containers() {
  section 04_containers
  note 'hello-world 실행'
  run 'docker run --name hello-test hello-world'
  note 'ubuntu 컨테이너 실행(백그라운드 유지) 후 내부 명령 실행 (exec)'
  run 'docker run -d --name ubuntu-test ubuntu sleep infinity'
  run 'docker exec ubuntu-test ls /'
  run 'docker exec ubuntu-test bash -c "echo Hello from ubuntu container && head -n 2 /etc/os-release"'
  note '관찰 1) exec 로 띄운 프로세스가 끝나도 컨테이너는 계속 Up (메인 프로세스 sleep 이 살아 있음)'
  run 'docker ps --filter name=ubuntu-test'
  note '관찰 2) 메인 프로세스 자체가 끝나는 컨테이너는 즉시 Exited'
  run 'docker run --name ubuntu-oneshot ubuntu echo "main process done"'
  run 'docker ps -a --filter name=ubuntu-oneshot'
  note '관찰 3) attach 는 "메인 프로세스"의 입출력에 붙음 -> 메인 프로세스가 끝나면 attach 도 끝나고 컨테이너도 종료'
  run "docker run -d --name attach-test ubuntu bash -c 'for i in 1 2 3; do echo tick \$i; sleep 1; done'"
  run 'docker attach --no-stdin attach-test'
  run 'docker ps -a --filter name=attach-test'
}

s_build() {
  section 05_build
  run 'cat Dockerfile'
  run "docker build --progress=plain -t $IMAGE ."
  run "docker image inspect $IMAGE --format 'Labels={{json .Config.Labels}}  Env={{json .Config.Env}}  ExposedPorts={{json .Config.ExposedPorts}}'"
}

s_port() {
  section 06_port
  note '같은 이미지로 컨테이너 2개를 서로 다른 호스트 포트에 매핑 (8080, 8082 -> 컨테이너 80)'
  run "docker run -d -p 8080:80 --name web-8080 $IMAGE"
  run "docker run -d -p 8082:80 --name web-8082 $IMAGE"
  sleep 3
  run 'docker ps --filter name=web-80'
  run 'docker port web-8080'
  run 'curl -s -i http://localhost:8080'
  run 'curl -s -i http://localhost:8082'
}

s_ops() {
  section 07_docker_ops
  run 'docker pull nginx:alpine'
  run 'docker images'
  run 'docker ps'
  run 'docker ps -a'
  note '컨테이너 중지 / 재시작'
  run 'docker stop web-8082'
  run 'docker ps -a --filter name=web-8082'
  run 'docker start web-8082'
  run 'docker ps --filter name=web-8082'
  note '로그 / 리소스 / 헬스체크 상태'
  run 'docker logs --tail 10 web-8080'
  run 'docker stats --no-stream'
  sleep 6
  run "docker inspect --format '{{.Name}} health={{.State.Health.Status}}' web-8080"
}

s_bind() {
  section 08_bind_mount
  mkdir -p "$ROOT/bind-site"
  note '호스트 폴더 bind-site/ 를 nginx 웹 루트에 직접 연결 (절대 경로 필요 -> $(pwd) 사용)'
  run 'echo "<h1>bind mount v1 (before)</h1>" > bind-site/index.html'
  run "docker run -d -p 8081:80 -v \"$HOST_ROOT/bind-site:/usr/share/nginx/html\" --name web-bind nginx:alpine"
  sleep 2
  note '[변경 전]'
  run 'curl -s http://localhost:8081'
  note '호스트에서 파일만 수정 (이미지 재빌드 / 컨테이너 재시작 없음)'
  run 'echo "<h1>bind mount v2 (after) - edited on host</h1>" > bind-site/index.html'
  note '[변경 후] -> 즉시 반영'
  run 'curl -s http://localhost:8081'
  run 'docker exec web-bind cat /usr/share/nginx/html/index.html'
  run "docker inspect --format '{{range .Mounts}}{{.Type}}: {{.Source}} -> {{.Destination}}{{end}}' web-bind"
}

s_volume() {
  section 09_volume
  note '1) 볼륨 생성'
  run 'docker volume create mydata'
  run 'docker volume ls'
  run 'docker volume inspect mydata'
  note '2) 첫 번째 컨테이너에 연결하고 데이터 쓰기'
  run 'docker run -d --name vol-test -v mydata:/data ubuntu sleep infinity'
  run "docker exec vol-test bash -c 'echo hi-volume > /data/hello.txt && cat /data/hello.txt'"
  note '3) 컨테이너 삭제 (삭제 전/후 목록)'
  run 'docker ps -a --filter name=vol-test'
  run 'docker rm -f vol-test'
  run 'docker ps -a --filter name=vol-test'
  note '4) 새 컨테이너에 같은 볼륨 연결 -> 데이터 유지 확인'
  run 'docker run -d --name vol-test2 -v mydata:/data ubuntu sleep infinity'
  run 'docker exec vol-test2 cat /data/hello.txt'
  note '5) 데이터 손실 대비: 볼륨 백업(tar) -> 새 볼륨으로 복구'
  mkdir -p "$ROOT/backup"
  run "docker run --rm -v mydata:/data -v \"$HOST_ROOT/backup:/backup\" ubuntu tar czf /backup/mydata.tgz -C /data ."
  run 'ls -l backup'
  run 'docker volume create mydata-restore'
  run "docker run --rm -v mydata-restore:/data -v \"$HOST_ROOT/backup:/backup\" ubuntu tar xzf /backup/mydata.tgz -C /data"
  run 'docker run --rm -v mydata-restore:/data ubuntu cat /data/hello.txt'
}

s_conflict() {
  section 10_port_conflict
  note '문제 재현: 이미 web-8080 이 쓰는 8080 에 또 매핑'
  run "docker run -d -p 8080:80 --name web-conflict $IMAGE"
  note '진단 1) 어떤 컨테이너가 8080 을 쓰는가'
  run 'docker ps --filter publish=8080'
  note '진단 2) OS 수준에서 8080 을 LISTEN 중인 프로세스'
  run 'if command -v ss >/dev/null; then ss -ltnp | grep ":8080"; elif command -v lsof >/dev/null; then lsof -nP -iTCP:8080 -sTCP:LISTEN; else netstat -ano | grep ":8080" | grep LISTEN; fi'
  note '조치) 실패하며 남은 컨테이너 정리 후 빈 포트(8083)로 재실행'
  run 'docker rm -f web-conflict'
  run "docker run -d -p 8083:80 --name web-conflict $IMAGE"
  sleep 2
  run 'curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8083'
  run 'docker rm -f web-conflict'
}

s_git() {
  section 11_git
  run 'git --version'
  note 'user.email 은 개인정보이므로 마스킹'
  run 'git config --list | sed -E "s/^(user\.email=).*/\1***masked***/"'
  run 'git config --global init.defaultBranch'
  run 'git branch --show-current'
  run 'git remote -v | sed -E "s#https://[^@/]+@#https://***@#"'
  run 'git log --oneline --decorate -n 5'
  note '원격(GitHub) main 의 커밋 해시 = 로컬 push 결과'
  run 'git ls-remote origin main'
  run 'git status -sb'
}

s_compose() {
  section 12_bonus_compose
  if ! docker compose version >/dev/null 2>&1; then note 'docker compose 미설치 - 생략'; return; fi
  run 'docker compose version'
  run 'cat docker-compose.yml'
  run 'docker compose up -d --build'
  sleep 8
  run 'docker compose ps'
  note 'checker 컨테이너가 서비스 이름 "web" 으로 접속 (Compose 기본 네트워크의 DNS)'
  run 'docker compose logs --tail 5 checker'
  run 'curl -s http://localhost:8090'
  run 'docker compose down'
}

# --------------------------------------------------------------------------
mask_logs() {   # 혹시 모를 이메일/토큰을 한 번 더 가림
  perl -pi -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/***\@***/g; s/gh[pousr]_[A-Za-z0-9]{20,}/***token***/g' "$LOG_DIR"/*.txt 2>/dev/null
}

embed() {
  awk -v dir="$LOG_DIR" '
    { sub(/\r$/, "") }
    /^<!-- LOG:[A-Za-z0-9_]+ -->$/ {
      print; name=$0; sub(/^<!-- LOG:/, "", name); sub(/ -->$/, "", name)
      f = dir "/" name ".txt"; print "```text"
      if ((getline line < f) > 0) { print line; while ((getline line < f) > 0) print line }
      else print "(아직 수집 전: bash scripts/collect_evidence.sh 실행)"
      close(f); print "```"; skip = 1; next
    }
    /^<!-- \/LOG -->$/ { skip = 0; print; next }
    !skip { print }
  ' README.md > README.md.tmp && mv README.md.tmp README.md
  echo "✔ README.md 에 로그를 붙였습니다."
}

ALL="env terminal permission docker_check containers build port ops bind volume conflict git compose"

case "${1:-all}" in
  all)   need_docker; clean; for s in $ALL; do "s_$s"; done; mask_logs; embed
         echo; echo "완료! 브라우저로 http://localhost:8080 을 열어 주소창이 보이게 캡처 -> images/browser_8080.png 로 저장하세요."
         echo "실습 컨테이너 정리는: bash scripts/collect_evidence.sh clean" ;;
  embed) mask_logs; embed ;;
  clean) need_docker; clean; echo "정리 완료" ;;
  *)     need_docker; "s_$1" && mask_logs && embed ;;
esac
