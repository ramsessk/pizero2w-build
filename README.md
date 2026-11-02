# pizero2w-build

Docker와 Buildroot로 Raspberry Pi용 Linux 이미지를 만들고, Wi-Fi·SSH·I2C 및 SSD1306 OLED 시계를 구성하는 프로젝트입니다. Ubuntu x86_64 호스트에서의 빌드를 기준으로 합니다.

> **개발 이력과 대상 보드:** 이 프로젝트는 처음에 **Pi Zero 2 W**를 목표로 시작하여 저장소 이름을 `pizero2w-build`로 정했습니다. 이후 실제 구현에서는 이미지를 **Pi Zero W에 다운로드하여 테스트**했습니다. 현재 구현 및 실기기 테스트의 기준 보드는 Pi Zero W입니다.
>
> 저장소 이름은 `pizero2w-build`이지만, 현재 저장된 defconfig는 **Pi Zero W(ARM1176JZF-S / ARMv6, bcm2708-rpi-zero-w)**용입니다. Pi Zero 2 W용 설정으로 검증된 상태는 아닙니다. Zero 2 W에서 사용하려면 해당 보드의 CPU·커널·DTB·펌웨어 설정을 먼저 확인해야 합니다.

## 목차

- [저장소 구성](#저장소-구성)
- [최초 준비](#최초-준비)
- [Docker 빌드 환경](#docker-빌드-환경)
- [Buildroot 설정과 빌드](#buildroot-설정과-빌드)
- [SD 카드 기록과 첫 접속](#sd-카드-기록과-첫-접속)
- [오버레이와 부팅 구성](#오버레이와-부팅-구성)
- [SSD1306 OLED 시계](#ssd1306-oled-시계)
- [설정 백업과 반복 빌드](#설정-백업과-반복-빌드)
- [문제 해결](#문제-해결)
- [현재 확인이 필요한 사항](#현재-확인이-필요한-사항)

## 저장소 구성

| 경로 | 역할 |
| --- | --- |
| `Dockerfile` | Ubuntu 22.04 기반 빌드 환경, 호스트 UID/GID에 맞춘 builduser |
| `configs/raspberrypizero_custom_defconfig` | 버전 관리하는 Buildroot 설정 |
| `workspace/buildroot/` | Buildroot 서브모듈 |
| `workspace/firmware/` | pyavitz/firmware 서브모듈 |
| `workspace/users.txt` | defconfig가 실제 참조하는 사용자 테이블 |
| `users.txt` | 루트에도 존재하는 사용자 테이블 사본 |
| `workspace/rootfs-overlay/` | 이미지의 루트 파일시스템에 복사할 파일 |
| `workspace/buildroot/output/` | 로컬 빌드 결과·캐시·최종 이미지 |
| `docs/backup/README.md` | 통합 전 첫 번째 문서 원본 |
| `docs/backup/README2.md` | 통합 전 두 번째 문서 원본 |

오버레이의 주요 파일은 다음과 같습니다.

| 오버레이 내부 경로 | 역할 |
| --- | --- |
| `etc/network/interfaces` | wlan0 DHCP와 wpa_supplicant 실행 |
| `etc/wpa_supplicant/wpa_supplicant.conf.example` | Wi-Fi 설정 템플릿 |
| `etc/init.d/S30wifi_load` | brcmfmac 및 /etc/modules 로드, I2C 권한 설정 |
| `etc/init.d/S45ntpdate` | 현재는 ntpd 명령으로 부팅 시각 동기화 시도 |
| `etc/init.d/S50dropbear` | SSH 서버 시작·중지·재시작 |
| `etc/dropbear/` | SSH 호스트 키 |
| `etc/fstab` | 루트·가상 파일시스템 및 부트 파티션 마운트 |
| `etc/modules`, `etc/mdev.conf` | I2C 모듈과 장치 권한 |
| `etc/shells`, `etc/sudoers.d/90-sudo-group` | 로그인 셸과 sudo 그룹 설정 |
| `boot/firmware/config.txt` | I2C 활성화 설정이 담긴 파일 |
| `lib/firmware/brcm/` | Broadcom Wi-Fi 펌웨어와 모델명 심볼릭 링크 |
| `home/sg/oled-test/` | OLED 시계 및 로컬 Adafruit 드라이버 |

Buildroot와 firmware는 메인 저장소에 소스 전체를 복사하는 대신 각 저장소의 특정 커밋을 기록합니다. 현재 firmware 서브모듈은 소스 보관용이며, 저장된 defconfig에 이 디렉터리를 자동 복사하는 설정은 없습니다. 실제 이미지에 넣는 커스텀 Wi-Fi 파일은 오버레이의 `lib/firmware/brcm/`에 있습니다.

## 최초 준비

Docker와 Git을 사용할 수 있는 일반 사용자 계정으로 실행합니다.

```bash
git clone --recurse-submodules https://github.com/ramsessk/pizero2w-build.git
cd pizero2w-build
git submodule status
```

이미 저장소를 받았다면 다음 명령으로 기록된 서브모듈 커밋을 복원합니다.

```bash
git submodule update --init --recursive
```

재현 빌드에는 메인 저장소에 기록된 커밋을 사용합니다. `git submodule update --remote`는 원격의 다른 버전으로 이동할 수 있으므로 일반적인 복원 명령으로 사용하지 않습니다.

Wi-Fi 설정은 호스트에서 준비합니다.

```bash
cp workspace/rootfs-overlay/etc/wpa_supplicant/wpa_supplicant.conf.example \
   workspace/rootfs-overlay/etc/wpa_supplicant/wpa_supplicant.conf
chmod 600 workspace/rootfs-overlay/etc/wpa_supplicant/wpa_supplicant.conf
```

생성한 파일의 SSID와 비밀번호를 편집합니다. 이 실제 설정 파일은 `.gitignore`로 제외되어 있으므로 새로 clone할 때마다 별도로 준비해야 합니다.

```text
ctrl_interface=/var/run/wpa_supplicant
update_config=1
country=KR

network={
    ssid="접속할_와이파이_이름"
    psk="와이파이_비밀번호"
    key_mgmt=WPA-PSK
}
```

저장된 root 및 sg 계정의 초기 비밀번호는 `raspberry`입니다. 사용 전에 defconfig와 `workspace/users.txt`의 비밀번호를 변경하십시오. 현재 공개 저장소에는 SSH 호스트 개인키도 포함되어 있으므로 실제 운영 장비에서는 장비별 새 키로 교체해야 합니다.

## Docker 빌드 환경

프로젝트 루트의 기존 Dockerfile을 사용합니다. Buildroot 의존성, UTF-8 로케일, 일반 사용자 builduser가 구성되어 있습니다.

호스트에서 이미지를 만듭니다.

```bash
docker build \
  --build-arg USER_ID="$(id -u)" \
  --build-arg GROUP_ID="$(id -g)" \
  -t buildroot-builder .
```

프로젝트 전체를 마운트하고 Buildroot 디렉터리에서 시작합니다. 루트의 `configs/`도 컨테이너에서 접근할 수 있도록 기존 문서의 workspace 단독 마운트를 변경했습니다.

```bash
docker run -it --rm \
  -v "$PWD:/home/builduser/project" \
  -w /home/builduser/project/workspace/buildroot \
  buildroot-builder bash
```

이후 빌드 명령은 컨테이너 안에서 실행합니다. 프로젝트 파일과 Buildroot의 output은 호스트에 있으므로 컨테이너를 종료해도 유지됩니다. 컨테이너의 마운트 밖에 저장한 파일은 `--rm`으로 종료 시 삭제됩니다. UID/GID 매핑은 호스트에서 일반 사용자로 실행하는 것을 전제로 합니다.

## Buildroot 설정과 빌드

### 저장된 설정 불러오기

컨테이너의 `/home/builduser/project/workspace/buildroot`에서 실행합니다.

```bash
make defconfig BR2_DEFCONFIG=/home/builduser/project/configs/raspberrypizero_custom_defconfig
make menuconfig
```

기존 `output/.config`에 보존해야 할 변경이 있다면 defconfig를 불러오기 전에 [설정 백업](#설정-백업과-반복-빌드)을 하십시오. 별도의 Buildroot clone이나 임의 브랜치 checkout은 필요하지 않습니다.

### 현재 defconfig의 핵심 설정

| 구분 | 저장된 값 |
| --- | --- |
| CPU / 툴체인 | ARM1176JZF-S, Bootlin ARMv6 EABIHF glibc |
| 커널 | Raspberry Pi Linux 커밋을 고정한 tarball, bcmrpi defconfig |
| Device Tree | `broadcom/bcm2708-rpi-zero-w` |
| 부트 설정 | `board/raspberrypi0w/config_0w.txt` |
| 사용자 / 오버레이 | `../users.txt` / `../rootfs-overlay` |
| 시간대 | `Asia/Seoul`, timezone info 활성화 |
| 네트워크 | wpa_supplicant, wpa_cli, wpa_passphrase, Dropbear, NTP |
| Python / I2C | Python 3, Pillow, pip, smbus-cffi, i2c-tools |
| 셸 / 관리 | Bash, sudo, kmod |
| 루트 파일시스템 | ext4 형식, 120M |

상대 경로는 Buildroot 디렉터리에서 빌드할 때를 기준으로 합니다. 루트의 `users.txt`가 아니라 `workspace/users.txt`가 사용됩니다.

`menuconfig`에서 변경할 주요 항목:

- `System configuration`: root 비밀번호, 기본 셸, 사용자 테이블, 오버레이, 시간대.
- `Target packages → Networking applications`: wpa_supplicant와 필요한 드라이버 지원, Dropbear, NTP.
- `Target packages`의 I2C·Python 관련 메뉴: i2c-tools, Python 3, Pillow, smbus-cffi.
- 독립 `ntpdate`를 사용하려면 해당 하위 옵션도 확인합니다. 현재 defconfig에는 NTP 패키지 선택만 명시되어 있습니다.

Bash 패키지가 선택되어 있어도 시스템 기본 셸까지 Bash로 설정되었다고 단정할 수는 없습니다. sg의 로그인 셸은 사용자 테이블에 `/bin/bash`로 지정되어 있습니다.

### 빌드

```bash
make
```

완료 후 이미지 경로:

```text
workspace/buildroot/output/images/sdcard.img
```

120M 루트 파일시스템 공간이 부족하면 `menuconfig`의 ext 파일시스템 크기를 늘립니다. CPU·툴체인 같은 기반 설정을 변경하면 기존 output을 재사용하기보다 새 출력 디렉터리에서 전체 빌드하는 것이 적합합니다. 이 문서의 명령은 기본 output 경로를 기준으로 합니다.

## SD 카드 기록과 첫 접속

컨테이너에서 `exit`한 뒤 호스트에서 SD 카드 장치를 확인합니다.

```bash
lsblk -o NAME,SIZE,MODEL,MOUNTPOINTS
```

대상 카드의 마운트된 파티션을 해제한 뒤 기록합니다. 아래 `/dev/sdX`는 실제 카드의 **전체 디스크 경로**로 바꾸어야 하며, 해당 디스크의 내용은 덮어씁니다.

```bash
sudo dd if=workspace/buildroot/output/images/sdcard.img \
  of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

카드를 장착하고 부팅한 뒤 공유기에서 할당된 IP를 확인합니다.

```bash
ssh sg@<라즈베리파이_IP>
```

현재 wlan0는 DHCP 방식입니다. 일정한 IP가 필요하면 공유기에서 장비의 MAC 주소에 DHCP 예약을 설정합니다. 기존 문서의 IP는 예시이며 환경에 맞게 바꾸어야 합니다.

## 오버레이와 부팅 구성

### 사용자와 권한

`workspace/users.txt`는 사용자명·UID·그룹명·GID·비밀번호·홈·셸·추가 그룹·설명 순서의 테이블입니다. sg는 `/home/sg`, `/bin/bash`, sudo/audio/video 그룹으로 정의되어 있습니다. 설명은 공백 없는 문자열로 관리하면 필드 혼동을 줄일 수 있습니다.

`etc/shells`에는 Bash 경로가 등록되어 있습니다. 현재 defconfig에는 sudo가 포함되어 있으므로 기존 문서의 “sudo 제외” 설명은 적용되지 않습니다. 필요하면 다음으로 root 계정에 진입합니다.

```bash
su -
```

### Wi-Fi 펌웨어

오버레이에 다음 파일과 링크가 이미 저장되어 있습니다. 최초 clone 후 다시 만들 필요는 없습니다.

```text
brcmfmac43430-sdio.bin
brcmfmac43430-sdio.clm_blob
brcmfmac43430-sdio.txt
brcmfmac43430-sdio.raspberrypi,model-zero-w.bin -> brcmfmac43430-sdio.bin
brcmfmac43430-sdio.raspberrypi,model-zero-w.txt -> brcmfmac43430-sdio.txt
```

교체할 때에는 대상 보드와 호환되는 파일을 사용하고 배포 라이선스를 확인합니다. `S30wifi_load`가 brcmfmac을 로드하며, `interfaces`가 wpa_supplicant를 시작한 다음 DHCP를 사용합니다.

### SSH

`S50dropbear`는 `dropbear -R -B`로 서버를 실행합니다. `-B`는 빈 비밀번호 로그인을 허용하므로 운영 환경에서는 옵션과 계정 정책을 함께 점검해야 합니다. 호스트 키가 유지되면 같은 장비의 재부팅 후에도 SSH 식별자가 유지됩니다.

장비에서 기존 공개 키를 교체할 경우, 콘솔 등 복구 경로를 확보한 상태에서 실행합니다.

```bash
# 장비의 root 셸에서 실행
/etc/init.d/S50dropbear stop
mv /etc/dropbear/dropbear_rsa_host_key /etc/dropbear/dropbear_rsa_host_key.old
dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key
chmod 600 /etc/dropbear/dropbear_rsa_host_key
/etc/init.d/S50dropbear start
```

새 이미지를 다시 기록하면 오버레이의 키로 덮어쓸 수 있으므로, 운영용 이미지의 키 관리 방식도 별도로 정해야 합니다.

### 부트 파티션과 I2C

현재 fstab에는 다음 설정이 있습니다.

```text
/dev/mmcblk0p1 /boot/firmware vfat defaults,rw,umask=000 0 2
```

부트 파티션을 읽기·쓰기로 마운트하며 일반 사용자에게도 쓰기 권한을 줍니다. 필요에 따라 권한을 제한하십시오.

오버레이의 `boot/firmware/config.txt`에는 `dtparam=i2c_arm=on`이 있지만, 부트 파티션을 이 경로에 마운트하면 루트 파일시스템의 해당 파일은 가려집니다. **오버레이에 파일이 있다는 사실만으로 실제 FAT 부트 파티션에 I2C 설정이 반영되지는 않습니다.** 이미지 생성에 사용하는 `board/raspberrypi0w/config_0w.txt`와 부팅 후 실제 `/boot/firmware/config.txt`를 확인하십시오.

`etc/modules`에는 i2c-bcm2835와 i2c-dev가 지정되어 있고, `S30wifi_load`가 이를 로드합니다. mdev 규칙과 시작 스크립트는 I2C 장치에 0666 권한을 부여합니다. 이는 모든 사용자에게 장치 접근을 허용하는 현재 개발용 구성입니다.

### 시간 동기화

현재 `S45ntpdate`는 이름과 달리 다음 명령을 실행합니다.

```text
ntpd -q -n -p ://google.com
```

`://google.com`은 잘못된 서버 주소입니다. 따라서 현재 스크립트를 정상적인 시간 동기화 구현으로 간주할 수 없습니다. 사용하는 ntpd가 BusyBox판인지 NTP 패키지판인지 `ntpd --help`로 확인한 뒤 해당 구현의 옵션에 맞게 수정해야 합니다. 독립 ntpdate를 선택했다면 root에서 다음과 같이 점검할 수 있습니다.

```bash
ntpdate -u time.google.com
date
```

NTP는 시스템 시각을 맞추며, 화면의 한국 시각 표시는 시간대 설정이 담당합니다. 외장 RTC가 없는 보드에서는 `hwclock -w`가 실패할 수 있으므로 이를 필수 단계로 두지 않습니다.

## SSD1306 OLED 시계

현재 코드는 I2C 버스 1, 주소 0x3C의 128×64 SSD1306을 기준으로 합니다.

| OLED 핀 | Raspberry Pi 물리 핀 |
| --- | --- |
| VCC | 모듈 사양에 맞는 전원, 3.3V 지원 모듈은 1번 |
| GND | 6번 |
| SDA | 3번, GPIO2 |
| SCL | 5번, GPIO3 |

전원을 끄고 배선하며, 모듈의 전압 사양을 확인합니다. I2C 장치를 확인한 뒤 실행합니다.

```bash
ls -l /dev/i2c-1
i2cdetect -y 1
cd /home/sg/oled-test
python3 test_oled.py
```

코드는 저장소의 `test_oled.py`와 같은 폴더의 `adafruit_ssd1306.py`, `adafruit_framebuf.py`를 사용합니다. 별도 Blinka 설치를 전제로 하지 않습니다. Python의 smbus 및 Pillow 모듈은 이미지에 필요합니다.

SMBus 전송 크기 제한에 맞춰 컨트롤 바이트 `int(buf[0])`와 데이터 영역을 분리하고, 데이터를 16바이트씩 나누어 전송합니다. 화면에는 제목과 날짜·시각을 1초마다 갱신하며 Ctrl+C로 종료하면 화면을 지웁니다. 시스템 시각이 맞지 않으면 OLED 표시도 틀립니다.

현재 저장소에는 OLED 시계를 부팅 시 자동 실행하는 init 스크립트가 없습니다. 위 명령으로 수동 실행합니다.

## 설정 백업과 반복 빌드

컨테이너의 Buildroot 디렉터리에서 설정을 저장합니다.

```bash
make savedefconfig BR2_DEFCONFIG=/home/builduser/project/configs/raspberrypizero_custom_defconfig
```

다른 환경에서 복원할 때:

```bash
make defconfig BR2_DEFCONFIG=/home/builduser/project/configs/raspberrypizero_custom_defconfig
make
```

같은 작업 폴더를 다시 마운트하면 기존 output/.config와 빌드 결과가 남습니다. 매번 defconfig를 복원할 필요는 없습니다. 오버레이만 수정했다면 보통 `make`로 이미지를 재생성합니다. 삭제한 오버레이 파일은 기존 output/target에 남을 수 있어, 삭제 반영이 중요하면 깨끗한 출력 디렉터리에서 재빌드하십시오.

호스트에서 변경을 확인하고 필요한 파일만 커밋합니다.

```bash
git diff -- configs/raspberrypizero_custom_defconfig workspace/rootfs-overlay workspace/users.txt
git status --short
```

서브모듈 내부 수정은 메인 저장소 커밋만으로 보존되지 않습니다. 별도 패치 또는 접근 가능한 fork에 커밋·푸시한 뒤 메인 저장소에서 서브모듈 커밋을 갱신해야 합니다.

## 문제 해결

| 증상 | 확인할 내용 |
| --- | --- |
| Docker 빌드의 UID/GID 생성 오류 | 호스트 UID/GID가 이미지의 기존 계정·그룹과 충돌하는지 확인 |
| Wi-Fi 연결 실패 | 실제 wpa_supplicant.conf 존재, SSID/PSK, `ip addr show wlan0`, `dmesg \| tail` |
| Wi-Fi 펌웨어 로드 실패 | brcmfmac 모듈, /lib/firmware/brcm 파일과 심볼릭 링크, 대상 모델 |
| SSH 접속 종료 | Dropbear 프로세스, /etc/dropbear 키와 권한, 장비 콘솔 로그 |
| SSH 호스트 키 변경 경고 | 재기록·키 교체 여부와 새 지문을 먼저 확인한 뒤 `ssh-keygen -R <IP>` |
| sg 로그인 실패 | workspace/users.txt, /bin/bash 존재, /etc/shells, 홈 디렉터리 |
| /dev/i2c-1 없음 | 실제 부트 파티션의 I2C 설정, 커널 모듈, S30wifi_load 실행 여부 |
| OLED가 보이지 않음 | 배선, I2C 버스·주소, smbus/Pillow import, 모듈 전압과 화면 규격 |
| 시간 또는 날짜 오류 | 잘못된 NTP 주소, 네트워크·DNS·UDP 123 통신, Asia/Seoul 설정 |
| 파일시스템 생성 공간 부족 | ext 파일시스템 크기(현재 120M)와 패키지 크기 |

## 현재 확인이 필요한 사항

문서 통합 과정에서 확인한 아래 항목은 코드·설정 변경을 수행한 것이 아니라, 현재 저장소와 이전 문서 사이의 차이를 기록한 것입니다.

1. **보드 대상:** Pi Zero 2 W를 목표로 시작했으나 실제 이미지 다운로드와 테스트는 Pi Zero W에서 진행했습니다. 현재 defconfig·DTB·펌웨어 설정은 Pi Zero W용이며, Zero 2 W 지원은 별도 확인이 필요합니다.
2. **시각 동기화:** S45ntpdate의 잘못된 서버 주소와 실제 ntpd 구현에 맞는 옵션 수정이 필요합니다.
3. **I2C 부트 설정:** 루트 오버레이의 config.txt와 실제 FAT 부트 파티션 설정을 구분해야 합니다.
4. **재현 가능한 커널 설정:** menuconfig 및 linux-menuconfig에서 로컬로 바꾼 값이 저장된 defconfig에 모두 반영되었는지 확인해야 합니다. 별도 커스텀 커널 설정 파일은 현재 메인 저장소에 없습니다.
5. **계정과 SSH 키:** 기본 비밀번호, 공개된 호스트 개인키, 빈 비밀번호 허용 옵션은 운영 전 변경 대상입니다.
6. **중복 사용자 파일:** 실제 빌드는 workspace/users.txt를 참조합니다. 루트의 users.txt만 수정하면 적용되지 않습니다.
7. **firmware 서브모듈:** 현재 빌드에 직접 연결되어 있지 않습니다. 업데이트만으로 오버레이의 펌웨어가 바뀌지 않습니다.

통합 전 문서는 [README 원본](docs/backup/README.md)과 [README2 원본](docs/backup/README2.md)에 내용 변경 없이 보관했습니다. 현재 사용 절차는 이 README를 기준으로 합니다.

실제 이미지 다운로드와 테스트는 프로젝트 개발자가 Pi Zero W에서 수행했습니다. 이 README는 해당 개발 이력과 저장된 설정·스크립트를 기준으로 정리했으며, 문서 편집 과정에서 별도의 이미지 빌드 및 보드 부팅 재검증은 수행하지 않았습니다.
