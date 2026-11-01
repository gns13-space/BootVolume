#!/bin/sh
# BootVolume 부팅음 도우미. 루트 LaunchDaemon(top.oodot.bootchime)으로 돈다.
# 맥이 꺼질 때(launchd 가 TERM 을 보낼 때) 부팅음이 읽는 NVRAM 값
# SystemAudioVolumeExtension 을 직접 써 넣는다. 평소 음량은 건드리지 않는다.
# 써 넣을 값은 앱이 그 음량일 때 macOS 가 실제로 쓴 2바이트를 재서 chime-value 에 16진수 4자로 적어 둔다.
# 기록 형식(앱이 읽는다): "YYYY-MM-DD HH:MM:SS 내용", 문제는 "오류:" 로 시작
DIR="/Library/Application Support/BootVolume"
LOG=/var/log/bootchime.log
now() { date '+%F %T'; }

# chime-value 의 16진수 4자. 잘못돼 있으면 빈 값을 돌려주고, 그때는 NVRAM 에 아무것도 쓰지 않는다
# (이 2바이트의 뜻은 기종마다 다를 수 있어 정해 둔 기본값을 쓰지 않는다)
# 이 파일은 사용자 소유라 아무 내용이나 들어 있을 수 있다.
# - 크기부터 본다: 정상은 5바이트("a218\n"). 16바이트를 넘으면 읽지 않는다
#   (큰 파일을 끝까지 읽느라 맥이 꺼지는 걸 붙잡지 않게. 앞부분만 잘라 읽으면 뒤에 붙은 내용이 무시돼 이상한 파일도 통과하므로 자르지 않는다)
# - 기록에는 영문자·숫자만 남긴다(가짜 기록 줄을 섞지 못하게)
hexvalue() {
  f="$DIR/chime-value"
  size=$(/usr/bin/stat -f %z "$f" 2>/dev/null || echo -1)
  if [ "$size" -ge 0 ] && [ "$size" -le 16 ]; then
    v=$(tr -d ' \n' < "$f")
  else
    v="(크기 $size)"
  fi
  case "$v" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f]) echo "$v" ;;
    *) safe=$(printf '%s' "$v" | LC_ALL=C tr -cd 'A-Za-z0-9' | head -c 16)
       echo "$(now) 오류: chime-value 가 잘못되어 부팅음 값을 쓰지 않습니다 [$safe]" >> $LOG ;;
  esac
}
# 지금 NVRAM 값을 16진수로
current() {
  /usr/sbin/nvram -x SystemAudioVolumeExtension 2>/dev/null \
    | /usr/bin/plutil -extract SystemAudioVolumeExtension raw -o - - 2>/dev/null \
    | /usr/bin/base64 -D | /usr/bin/xxd -p
}
write() {
  out=$(/usr/sbin/nvram SystemAudioVolumeExtension="%${1%??}%${1#??}" 2>&1) \
    || echo "$(now) 오류: NVRAM 에 쓰지 못했습니다 ($out)" >> $LOG
}

on_term() {
  hex=$(hexvalue)
  [ -n "$hex" ] || exit 0
  write "$hex"; echo "$(now) 종료 → $hex 써 넣음" >> $LOG
  # 맥은 이 도우미가 끝날 때까지 기다렸다 꺼진다. 오래 붙잡지 않도록
  # 0.5초 뒤 한 번만 확인하고, 다른 값으로 덮였을 때만 다시 쓴다(전에는 3초 넘게 기다렸다).
  sleep 0.5
  last=$(current)
  if [ "$last" != "$hex" ]; then
    echo "$(now) 덮임($last) → 다시 씀" >> $LOG
    write "$hex"
    last=$(current)
  fi
  echo "$(now) 마지막 값: $last" >> $LOG
  exit 0
}
trap on_term TERM
echo "$(now) 시작" >> $LOG
[ -f "$DIR/chime-value" ] || echo "$(now) 오류: chime-value 파일이 없습니다" >> $LOG
while :; do sleep 86400 & wait $!; done
