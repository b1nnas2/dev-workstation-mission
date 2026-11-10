# ubuntu 컨테이너 안에서 실행되는 권한 실습 스크립트
# (collect_evidence.sh 가 표준입력으로 넘겨서 실행함)
PS4='$ '
set -x
cd /tmp

# ---- 파일 1개: 644 -> 755 -> 640 ----
touch perm_file.txt
chmod 644 perm_file.txt
ls -l perm_file.txt
chmod 755 perm_file.txt
ls -l perm_file.txt
chmod u=rw,g=r,o= perm_file.txt
ls -l perm_file.txt
stat -c '%a %A %n' perm_file.txt

# ---- 디렉토리 1개: 755 -> 700 ----
mkdir perm_dir
chmod 755 perm_dir
ls -ld perm_dir
chmod 700 perm_dir
ls -ld perm_dir
stat -c '%a %A %n' perm_dir

# ---- 700 의 효과: 소유자(root)가 아닌 사용자(nobody)는 접근 거부 ----
su -s /bin/bash nobody -c 'ls /tmp/perm_dir' || true
