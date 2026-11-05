#!/bin/zsh
# 녹화 1회: 정리 → 녹화 → 부팅음 60 되돌리기 → 원래대로
R=${0:A:h}; N=${1:-1}; OUT=$R/take$N.mov
MOUSE=$(swift -e 'import Cocoa; let p = CGEvent(source: nil)!.location; print("\(p.x) \(p.y)")' 2>/dev/null)
APPS=$(osascript -e 'tell application "System Events" to get name of every application process whose visible is true')
echo "$APPS" > $R/visible_apps.txt
restore() {
  defaults write com.apple.WindowManager StandardHideWidgets -bool false
  $R/apps show $R/hidden_pids.txt
  [ -f $R/parked.txt ] && $R/park unpark $R/parked.txt && rm -f $R/parked.txt
  [ -n "$MOUSE" ] && swift -e "import Cocoa; CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: ${MOUSE% *}, y: ${MOUSE#* }), mouseButton: .left)!.post(tap: .cghidEventTap)" 2>/dev/null
  echo "되돌림 끝"
}
trap restore EXIT INT TERM
# 정리
defaults write com.apple.WindowManager StandardHideWidgets -bool true
$R/apps hide $R/hidden_pids.txt
sleep 0.8
L=$($R/wins_left)
for a in ${(s:,:)L}; do $R/park park $a $R/parked.txt >/dev/null; done
sleep 0.5; L=$($R/wins_left)
for a in ${(s:,:)L}; do [ "$a" = "$(cat $R/parked.txt | cut -d' ' -f1 | head -1)" ] || { echo "창이 남아 있어 녹화 중단: $a"; exit 1; }; done
swift -e 'import Cocoa; NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()' 2>/dev/null
sleep 1.5
screencapture -x -l 17 $R/clean_check$N.png 2>/dev/null; screencapture -x $R/full_before$N.png
# 녹화
rm -f $OUT; screencapture -v -C -V 36 -x $OUT & SC=$!
echo "녹화 시작 — 10초 동안 녹화 아이콘을 옮겨 주세요"; sleep 10
swift -e 'import Cocoa; CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: 820, y: 640), mouseButton: .left)!.post(tap: .cghidEventTap)' 2>/dev/null
sleep 1.2
$R/drive demo $R/cursor$N.json
wait $SC
# 부팅음 60 되돌리기
$R/drive restore $R/restore$N.json 60
