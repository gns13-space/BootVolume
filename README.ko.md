# BootVolume

[English](README.md) · [웹사이트](https://bootvolume.oodot.top)

로그인한 뒤에는 소리가 나지 않게 두면서, 맥을 켤 때 나는 부팅음만 들리게 하는 macOS 메뉴바 앱입니다.

애플 칩 맥의 부팅음은 맥을 끌 때의 음량을 따릅니다. 평소 음량을 0으로 두면 부팅음도 나지 않습니다. BootVolume은 이렇게 해결합니다.

- **로그인 후**: 정해 둔 음량(기본 0)으로 맞춥니다. 원하면 끄기 전 음량으로 되돌릴 수도 있습니다.
- **끌 때**: 관리자 권한으로 도는 작은 도우미가 정해 둔 부팅음 음량을 NVRAM에 직접 써 넣습니다. 그래서 부팅음이 그 음량으로 납니다. 평소 음량은 건드리지 않습니다.

## 필요한 것

- macOS 15 이상
- 애플 칩 맥
- MacBook Air(M4) · macOS 27에서만 시험했습니다. 다른 기종에서는 다르게 동작할 수 있습니다. [동작 방식](#동작-방식)을 참고하세요.

## 빌드·설치

```sh
./build.sh
```

릴리스로 빌드해 `/Applications/BootVolume.app`에 설치합니다. 서명에는 다음 순서로 찾은 것을 씁니다.

1. `$BOOTVOLUME_SIGN_ID`
2. 키체인의 첫 번째 `Apple Development` 인증서
3. 임시 서명(ad-hoc)

설치한 뒤 메뉴바 스피커 아이콘을 누르고 **도우미 설치**를 누르세요. 관리자 암호를 묻습니다.

## 동작 방식

부팅음은 NVRAM 값 `SystemAudioVolumeExtension`을 읽습니다. 이 값은 2바이트이고, 둘째 바이트의 맨 앞 비트가 음소거를 뜻합니다. 음량을 바꾸면 macOS가 이 값을 고쳐 씁니다. 하지만 끄는 도중에 바꾼 음량은 제때 기록되지 않습니다.

그래서 BootVolume은 이렇게 합니다.

1. **재기**: 부팅음 음량을 정하면, 앱이 음소거를 켠 채로 시스템 음량을 잠깐 그 값으로 맞춥니다. 음소거 중에도 macOS는 음량 값을 쓰고 음소거 표시만 더 붙이기 때문에, 그 2바이트를 읽어 음소거 표시를 빼고 원래 음량과 음소거 상태로 되돌립니다. 그래서 재는 동안 소리가 커지지 않습니다. 재생 중인 소리는 4초쯤 음소거됩니다. 이 값의 형식은 공개되어 있지 않아서 항상 그 맥에서 재고, 코드에 정해 둔 값은 없습니다.
2. **끌 때 쓰기**: 관리자 권한으로 도는 LaunchDaemon(`top.oodot.bootchime`)이 맥이 꺼지기를 기다립니다. 꺼질 때 시스템이 보내는 종료 신호를 받으면, 잰 값을 `SystemAudioVolumeExtension`에 씁니다. 0.5초 뒤 한 번 확인하고, 다른 값으로 덮였을 때만 다시 씁니다.
3. **로그인**: 앱이 켜지자마자 음량을 맞추고, 1·3·6초 뒤에 한 번씩 더 맞춥니다.

**부팅음 켜기** 스위치는 부팅음을 막는 두 값도 지웁니다. `StartupMute=%01`과 옛 방식의 `SystemAudioVolume=%80`입니다.

## 파일

| 경로 | 소유 | 용도 |
|---|---|---|
| `/Library/Application Support/BootVolume/bootchime.sh` | root | 도우미 스크립트 |
| `/Library/Application Support/BootVolume/chime-value` | 사용자 | 잰 값(16진수 4자) |
| `/Library/LaunchDaemons/top.oodot.bootchime.plist` | root | 도우미 데몬 |
| `/var/log/bootchime.log` | root | 도우미 기록 |
| `~/Library/Logs/BootVolume.log` | 사용자 | 앱 기록 |

두 기록과 상태 점검은 **설정 → 기록** 탭에서 확인할 수 있습니다.

## 보안

도우미가 관리자 권한으로 돌기 때문에 이렇게 막아 두었습니다.

- 도우미는 `chime-value`를 읽기만 합니다. 16바이트를 넘는 파일은 읽지 않고, 소문자 16진수 4자일 때만 씁니다. 그 밖의 경우에는 아무것도 쓰지 않고 오류를 기록합니다.
- 도우미를 설치할 때는 관리자 스크립트가 먼저 앱 폴더가 실행 중인 앱의 서명 조건을 그대로 만족하는지 확인합니다. 그다음 관리자만 쓰는 임시 폴더로 복사하고, 서명을 다시 확인한 뒤 원본과 같은지 비교합니다.
- 관리자 스크립트는 파일로 쓰지 않고 `osascript`에 인자로 바로 넘깁니다.
- 앱 설정에서 읽은 값은 관리자 스크립트에 넣기 전에 검사합니다.

## 한계

- 전원 버튼을 길게 눌러 강제로 끄면 도우미가 돌 틈이 없어 다음 부팅음이 나지 않을 수 있습니다.
- NVRAM 형식은 공개되어 있지 않아 macOS 업데이트로 바뀔 수 있습니다.

## 지우기

1. 메뉴바 패널에서 **도우미 지우기**를 누릅니다.
2. 앱을 종료하고 `/Applications/BootVolume.app`을 지웁니다.
3. 남은 파일까지 지우려면 아래를 실행합니다.

```sh
defaults delete top.oodot.bootvolume
rm -f ~/Library/Logs/BootVolume.log
sudo rm -f /var/log/bootchime.log
```

## 디버그 옵션

```sh
open -n /Applications/BootVolume.app --args --test-poweroff   # 끌 때 알림 흉내
open -n /Applications/BootVolume.app --args --test-measure    # 지금 부팅음 음량을 다시 잼(설정이 바뀜)
```

## 라이선스

[MIT](LICENSE)
