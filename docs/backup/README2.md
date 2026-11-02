# 라즈베리 파이 제로 W (Pi Zero W) 초경량 최적화 및 OLED 시계 빌드 가이드 (Docker 기반)

본 프로젝트는 우분투(x86_64) 호스트 시스템에 어떠한 영향도 주지 않고, **도커(Docker)** 내부에서 **Buildroot**를 이용하여 **라즈베리 파이 제로 W (Pi Zero W)**용 리눅스 커널 및 와이파이/SSH 자동 구동 시스템 이미지를 크로스 컴파일하고, SSD1306 OLED 디스플레이를 초경량 환경에서 완벽하게 제어하는 가이드를 제공합니다.

---

## 🛠 주요 특징 및 다이어트 사항
- **호스트 시스템 격리**: 도커 컨테이너를 사용하여 호스트의 라이브러리 오염을 원천 차단합니다.
- **초경량 최적화 (RAM/용량 절약)**: 임베디드 리눅스에 무거운 `Avahi` 및 `DBus` 데몬을 완전히 제거하여 싱글코어 환경에 맞춤형 다이어트를 적용했습니다.
- **공유기 기반 고정 IP 활용**: 파이 내부 설정을 static으로 꼬지 않고, 공유기의 MAC 주소 바인딩 설정을 통해 언제나 일정한 IP(예: `172.30.1.57`)로 다이렉트 SSH 진입을 가능하게 합니다.
- **독립형 ntpdate 시각 동기화**: 전원 인가 시 와이파이망이 연결되는 즉시 표준 오픈소스 `ntpdate` 패키지가 구글 시간 서버와 동기화하여 정확한 한국 표준시(KST)를 고정합니다.
- **SMBus 기반 OLED 청크 스트리밍**: 무거운 에이다프루트 전용 회로바인딩 패키지 없이, 리눅스 표준 `SMBus` 엔진을 16바이트 청크 단위로 조각내어 프레임 버퍼를 직접 스트리밍합니다.
- **상용 등급 SSH 보안**: Dropbear 호스트 키 고정 빌드를 통해 재부팅할 때마다 우분투 호스트 컴퓨터에서 `REMOTE HOST IDENTIFICATION HAS CHANGED` 경고 에러가 발생하는 버그를 완벽히 해결했습니다.
- **데이터 보존 (Persistence)**: 컨테이너를 종료(`exit`)해도 소스코드와 빌드 캐시, 결과물이 사라지지 않도록 호스트의 `workspace` 폴더를 공유(마운트)합니다.

---

## 📁 디렉터리 구조
시작하기 전, 호스트 시스템의 최종 폴더 구조는 다음과 같이 구성됩니다.
```text
~/pizero2w-build/
├── Dockerfile
├── README.md                 # 본 파일
└── workspace/                # 컨테이너와 공유되는 작업 폴더
    ├── users.txt             # 일반 사용자 계정 정의 파일
    ├── raspberrypizero_custom_defconfig # 내 빌드 설정 백업 파일
    ├── buildroot/            # Buildroot 소스 폴더
    └── rootfs-overlay/       # 최종 이미지 시스템에 덮어씌울 커스텀 파일
        ├── boot/
        │   └── firmware/     # 부트 파티션이 마운트될 빈 폴더 (config.txt 내장)
        ├── home/
        │   └── sg/           # 일반 사용자 sg의 홈 디렉터리
        │       └── oled-test/   # OLED 제어 스크립트 공간
        └── etc/
            ├── fstab         # vfat 자동 마운트 옵션 설정 (rw,umask=000 포함)
            ├── mdev.conf     # 부팅 시 /dev/i2c-1 권한 자동 제어 규칙 (0666)
            ├── modules       # 부팅 시 i2c-dev 커널 드라이버 자동 로드 목록
            ├── shells        # 유효한 로그인 셸 목록 등록 파일
            ├── dropbear/
            │   └── dropbear_rsa_host_key  # (생성 예정) 고정 SSH 호스트 키
            ├── init.d/
            │   ├── S30wifi_load # 부팅 시 무선 및 커널 I2C 모듈 자동 연동 스크립트
            │   ├── S45ntpdate   # 부팅 시 독립형 ntpdate 인터넷 시간 동기화 스크립트
            │   └── S50dropbear  # 부팅 시 고정 키 참조 Dropbear SSH 데몬 구동 스크립트
            ├── network/
            │   └── interfaces   # wlan0 자동 구동 및 경량 DHCP 설정
            └── wpa_supplicant/
                └── wpa_supplicant.conf  # 와이파이 비밀번호 세팅
```

---

## 🔧 Buildroot 내부 패키지 및 시스템 설정 (도커 내부)

도커 빌드 컨테이너 실행 후 `make menuconfig` 창에서 설정해야 할 필수 핵심 항목 명세입니다.
```bash
make menuconfig
```
1. **와이파이**: `Target packages` -> `Networking applications` -> `[*] wpa_supplicant` (하위 nl80211, wpa_cli 필수 체크)
2. **독립형 NTP 설치**: `Target packages` -> `Networking applications` -> `[*] ntp` -> 하위 메뉴에서 **`[*] ntpdate`** 반드시 체크
3. **SSH**: `Target packages` -> `Networking applications` -> `[*] dropbear`
4. **보안/셸**: `System configuration` -> `Root password` 지정 & `[*] Allow root login with password` 체크 & `default shell` ➡️ `bash`로 지정
5. **타임존 인프라 설정 (tzdata 버그 차단)**: 
   - `System configuration` -> `timezone to install` -> **`Asia/Seoul`** 입력
   - (만약 시간대 DB 컴파일 오류 발생 시 `[ ] Install timezone info` 체크 해제로 다이어트 가능)
6. **I2C & 파이썬**: 
   - `Target packages` -> `Hardware handling` -> `[*] i2c-tools`
   - `Target packages` -> `Interpreter languages and scripting` -> `[*] python3`
   - `Target packages` -> `External python modules` -> `[*] python-pillow` & `[*] python-smbus-cffi`
7. **경로 매핑**: `Custom user table` -> `/home/builduser/workspace/users.txt` 입력 & `Root filesystem overlay directories` -> `/home/builduser/workspace/rootfs-overlay` 입력 후 저장.

---

## 📶 호스트 오버레이(rootfs-overlay) 구성 파일 작성 (호스트 터미널)

### 1. 일반 사용자 등록 및 셸 예외 차단
- **`workspace/users.txt`**: 탭(Tab) 없이 공백으로만 작성하며 설명 칸 공백 누락 주의.
  ```text
  sg -1 sg -1 raspberry /home/sg /bin/bash sudo,audio,video RaspberryPi_User
  ```
- **`rootfs-overlay/etc/shells`**: `/bin/bash` 및 `/usr/bin/bash` 등록.

### 2. 하드웨어 자동 제어 및 RW 마운트 보강
- **`rootfs-overlay/boot/firmware/config.txt`**: `dtparam=i2c_arm=on` 기입하여 칩셋 인프라 활성화.
- **`rootfs-overlay/etc/fstab`**: 부트 파티션을 일반 사용자도 편집할 수 있도록 권한 개방.
  ```text
  /dev/mmcblk0p1  /boot/firmware  vfat    defaults,rw,umask=000  0       2
  ```
- **`rootfs-overlay/etc/modules`**: 부팅 시 자동으로 드라이버 인터페이스가 올라오도록 유도.
  ```text
  i2c-bcm2835
  i2c-dev
  ```
- **`rootfs-overlay/etc/mdev.conf`**: 정규식 보정을 통해 장치 생성 시 권한을 오픈합니다.
  ```text
  i2c-[0-9]+      root:root 0666
  i2c[0-9]+       root:root 0666
  ```

### 3. 무선랜 및 드라이버/모듈 자동 로더 스크립트 (`rootfs-overlay/etc/init.d/S30wifi_load`)
*BusyBox init의 한계를 극복하기 위해 `/etc/modules`를 순차 파싱하여 커널에 로드하고, I2C 장치 이중 안전장치 권한을 부여하는 POSIX 규격 스크립트입니다.*
```bash
#!/bin/sh
case "$1" in
  start)
    echo "Loading brcmfmac wireless driver..."
    modprobe brcmfmac
    
    MODULES_FILE="/etc/modules"
    if [ -f "$MODULES_FILE" ]; then
        echo "Processing custom modules from /etc/modules..."
        while read -r module || [ -n "$module" ]; do
            case "$module" in
                "") continue ;;
                *)
                    echo "  -> modprobe $module"
                    modprobe "$module" 2>/dev/null
                    ;;
            esac
        done < "$MODULES_FILE"
    fi
    sleep 2
    
    if [ -e /dev/i2c-1 ]; then
        chmod 666 /dev/i2c-1
        echo "[INIT] Successfully opened access permission for /dev/i2c-1 (0666)"
    fi
    ;;
esac
exit 0
```
*작성 후 실행 권한 필수 부여*: `chmod +x ~/pizero2w-build/workspace/rootfs-overlay/etc/init.d/S30wifi_load`

### 4. 독립형 ntpdate 시각 동기화 스크립트 (`rootfs-overlay/etc/init.d/S45ntpdate`)
```bash
#!/bin/sh
case "$1" in
  start)
    echo "Synchronizing system hardware clock via ntpdate..."
    export TZ="KST-9"
    if ntpdate -u ://google.com pool.ntp.org >/dev/null 2>&1; then
        echo "[INIT] System clock successfully synchronized via NTP."
        hwclock -w
    else
        echo "[INIT] ❌ NTP Synchronization failed (Network timeout)."
    fi
    ;;
esac
exit 0
```
*작성 후 실행 권한 필수 부여*: `chmod +x ~/pizero2w-build/workspace/rootfs-overlay/etc/init.d/S45ntpdate`

### 5. SSH 호스트 키 사전 발급 및 스크립트 동기화 (`S50dropbear`)
매번 키가 바뀌어 호스트 접속이 차단되는 버그를 잡기 위해, **우분투 호스트 터미널**에서 키를 미리 고정 발급하여 심어줍니다.
```bash
sudo apt-get install -y dropbear-bin
mkdir -p ~/pizero2w-build/workspace/rootfs-overlay/etc/dropbear
dropbearkey -t rsa -f ~/pizero2w-build/workspace/rootfs-overlay/etc/dropbear/dropbear_rsa_host_key
```
이후 `rootfs-overlay/etc/init.d/S50dropbear` 파일은 임시 링크 제어 구문을 모두 걷어내고 아래와 같이 순수 기본형태로 유지합니다:
```bash
#!/bin/sh
case "$1" in
  start)
    echo -n "Starting Dropbear SSH server: "
    dropbear -R -B
    echo "OK"
    ;;
  stop)
    echo -n "Stopping Dropbear SSH server: "
    killall dropbear
    echo "OK"
    ;;
esac
exit 0
```
*작성 후 실행 권한 필수 부여*: `chmod +x ~/pizero2w-build/workspace/rootfs-overlay/etc/init.d/S50dropbear`

---

## 📺 SSD1306 OLED 디스플레이 크로스 드라이버 아키텍처

에이다프루트(`adafruit_ssd1306`) 드라이버 내부 코드 수정을 마치고, `SMBus` 통신의 32바이트 한계를 슬라이싱 청크 기법으로 극복하여 사각형 박스 안에 현재 한국 시각을 실시간 갱신(1초마다)하는 완벽한 파이썬 소스코드입니다.

*   **파일 보관 경로**: `workspace/rootfs-overlay/home/sg/oled-test/test_oled.py`

```python
import time
import datetime
from smbus import SMBus
import adafruit_ssd1306
from PIL import Image, ImageDraw, ImageFont

class I2C_Device:
    def __init__(self, bus_num=1, addr=0x3c):
        self.bus = SMBus(bus_num)
        self.addr = addr
    def write_i2c_block_data(self, addr, reg, data):
        self.bus.write_i2c_block_data(self.addr, reg, data)
        
    # 대용량 프레임 버퍼 데이터를 SMBus 32바이트 한계에 맞춰 16B 청크 단위로 쪼개어 전송
    def write(self, buf):
        if len(buf) == 0: return
        control_byte = int(buf)
        if len(buf) == 1:
            self.bus.write_byte(self.addr, control_byte)
            return
        data_bytes = list(buf[1:])
        chunk_size = 16
        for i in range(0, len(data_bytes), chunk_size):
            chunk = data_bytes[i:i + chunk_size]
            self.bus.write_i2c_block_data(self.addr, control_byte, chunk)
            
    def __enter__(self): return self
    def __exit__(self, exc_type, exc_val, exc_tb): pass

i2c = I2C_Device(bus_num=1, addr=0x3c)
display = adafruit_ssd1306.SSD1306_I2C(128, 64, i2c)
font = ImageFont.load_default()

print("OLED 실시간 시계 시작... (종료하려면 Ctrl+C)")
try:
    while True:
        image = Image.new("1", (display.width, display.height))
        draw = ImageDraw.Draw(image)

        draw.text((0, 0), "Hello Buildroot!", font=font, fill=255)
        draw.text((0, 15), "System Clock", font=font, fill=255)
        draw.rectangle((0, 35, 127, 63), outline=255, fill=0)

        now = datetime.datetime.now()
        date_str = now.strftime("%Y-%m-%d")
        time_str = now.strftime("%H:%M:%S")

        draw.text((8, 40), f"Date: {date_str}", font=font, fill=255)
        draw.text((15, 51), f"Time: {time_str}", font=font, fill=255)

        display.image(image)
        display.show()
        time.sleep(1)
except KeyboardInterrupt:
    display.fill(0)
    display.show()
    print("\nOLED 시계를 안전하게 종료했습니다.")
```

---

## 💾 Buildroot 커스텀 설정 백업 및 복구 가이드

도커 컨테이너 내부 터미널에서 설정을 마치거나 빌드를 시작하기 전, 아래 명령어를 통해 백업해 두어야 컨테이너 삭제 시에도 자산이 유실되지 않습니다.

- **현재 세팅 외부 공유 폴더로 추출 백업**:
  ```bash
  make savedefconfig BR2_DEFCONFIG=/home/builduser/workspace/raspberrypizero_custom_defconfig
  ```
- **도커 컨테이너 재시작 시 1초 만에 세팅 복구**:
  ```bash
  make defconfig BR2_DEFCONFIG=/home/builduser/workspace/raspberrypizero_custom_defconfig
  ```

