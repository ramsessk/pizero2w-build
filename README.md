# 라즈베리 파이 제로 W (Pi Zero W) 초경량 최적화 빌드 가이드 (Docker 기반)

본 프로젝트는 우분투(x86_64) 호스트 시스템에 어떠한 영향도 주지 않고, **도커(Docker)** 내부에서 **Buildroot**를 이용하여 **라즈베리 파이 제로 W (Pi Zero W)**용 리눅스 커널 및 와이파이/SSH 자동 구동 시스템 이미지를 크로스 컴파일하는 환경을 제공합니다.

---

## 🛠 주요 특징 및 다이어트 사항
- **호스트 시스템 격리**: 도커 컨테이너를 사용하여 호스트의 라이브러리 오염을 원천 차단합니다.
- **초경량 최적화 (RAM/용량 절약)**: 임베디드 리눅스에 무거운 `Avahi` 및 `DBus` 데몬을 완전히 제거하여 싱글코어 환경에 맞춤형 다이어트를 적용했습니다.
- **공유기 기반 고정 IP 활용**: 파이 내부 설정을 static으로 꼬지 않고, 공유기의 MAC 주소 바인딩 설정을 통해 언제나 일정한 IP(예: `172.30.1.57`)로 다이렉트 SSH 진입을 가능하게 합니다.
- **데이터 보존 (Persistence)**: 컨테이너를 종료(`exit`)해도 소스코드와 빌드 캐시, 결과물이 사라지지 않도록 호스트의 `workspace` 폴더를 공유(마운트)합니다.
- **권한 오류 방지**: 호스트 사용자의 ID(`UID`/`GID`)를 도커 내 계정과 동기화하여, 빌드 결과물이 `root` 권한으로 잠기는 현상을 방지합니다.
- **일반 사용자 최적화**: 디폴트 셸을 `bash`로 지정하고, 보안을 위한 일반 사용자 계정 분리 및 부트 파티션(vfat) 자동 마운트를 지원합니다.

---

## 📁 디렉터리 구조
시작하기 전, 호스트 시스템의 최종 폴더 구조는 다음과 같이 구성됩니다.
```text
~/pizero2w-build/
├── Dockerfile
├── README.md                 # 본 파일
└── workspace/                # 컨테이너와 공유되는 작업 폴더
    ├── users.txt             # 일반 사용자 계정 정의 파일
    ├── raspberrypizero_custom_defconfig # (생성 예정) 내 설정 백업 파일
    ├── buildroot/            # Buildroot 소스 폴더 (진행 중 생성됨)
    └── rootfs-overlay/       # 최종 이미지 시스템에 덮어씌울 커스텀 파일
        ├── boot/
        │   └── firmware/     # 부트 파티션이 마운트될 빈 폴더
        ├── home/
        │   └── sg/           # 일반 사용자 sg의 홈 디렉터리 (오류 방지용)
        └── etc/
            ├── fstab         # 가상 파일시스템 및 vfat 자동 마운트 설정
            ├── shells        # 유효한 로그인 셸 목록 등록 파일
            ├── init.d/
            │   ├── S30wifi_load # 부팅 시 무선랜 드라이버 강제 로드 스크립트
            │   └── S50dropbear  # 부팅 시 SSH 및 임시 키 폴더 자동 생성 스크립트
            ├── network/
            │   └── interfaces   # wlan0 자동 구동 및 경량 DHCP 설정
            └── wpa_supplicant/
                └── wpa_supplicant.conf  # 와이파이 비밀번호 세팅
```

---

## 🚀 환경 구축 및 빌드 순서

### 1단계: 호스트 작업 디렉터리 생성
우분투 호스트 터미널에서 데이터를 보존할 작업 공간을 만듭니다.
```bash
mkdir -p ~/pizero2w-build/workspace
cd ~/pizero2w-build
```

### 2단계: Dockerfile 작성 (`~/pizero2w-build/Dockerfile`)
```dockerfile
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Buildroot 필수 의존성 패키지 설치
RUN apt-get update && apt-get install -y \
    build-essential bash bc binutils bzip2 cpio file git \
    graphviz gzip libncurses5-dev locales make patch perl \
    python3 python3-matplotlib rsync sed tar unzip wget \
    && rm -rf /var/lib/apt/lists/*

# 로케일 설정 (Buildroot 필수 요구사항)
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8

# 호스트 사용자의 UID와 GID를 전달받기 위한 변수 정의
ARG USER_ID=1000
ARG GROUP_ID=1000

# 호스트 사용자와 권한이 동일한 builduser 계정 생성
RUN groupadd -g ${GROUP_ID} builduser && \
    useradd -u ${USER_ID} -g builduser -ms /bin/bash builduser

USER builduser
WORKDIR /home/builduser
```

### 3단계: 도커 이미지 빌드 및 컨테이너 실행
```bash
# 이미지 빌드 (호스트 UID/GID 주입)
docker build \
  --build-arg USER_ID=$(id -u) \
  --build-arg GROUP_ID=$(id -g) \
  -t buildroot-builder .

# 컨테이너 구동 (workspace 연동 및 종료 시 데이터 보존)
docker run -it --rm \
  -v $(pwd)/workspace:/home/builduser/workspace \
  buildroot-builder bash
```

---

## 🔧 Buildroot 내부 패키지 및 시스템 설정 (도커 내부)

```bash
cd workspace
git clone https://github.com
cd buildroot
git checkout 2024.02.x
make raspberrypizero_defconfig
make menuconfig
```

### 1. 와이파이 패키지 활성화
- `Target packages` -> `Networking applications` -> `[*] wpa_supplicant`
  - `[*] Enable nl80211 support`
  - `[*] Install wpa_passphrase/wpa_cli`

### 2. SSH 서버 활성화 및 root 패스워드 설정
- `Target packages` -> `Networking applications` -> `[*] dropbear`
- `System configuration` -> `Root password` -> 사용할 비밀번호 입력 (예: `raspberry`)
- `System configuration` -> `[*] Allow root login with password` -> **체크**

### 3. 디폴트 셸을 Bash로 변경
- `Target packages` -> `Shells and utilities` -> `[*] bash`
- `System configuration` -> `default shell` -> **`bash`** 선택

### 4. 경로 매핑 및 저장
- `System configuration` -> `Custom user table` -> `/home/builduser/workspace/users.txt` 입력
- `System configuration` -> `Root filesystem overlay directories` -> `/home/builduser/workspace/rootfs-overlay` 입력
- `Exit` 후 저장(`Yes`)

---

## 📶 호스트 오버레이(rootfs-overlay) 구성 파일 작성 (호스트 터미널)

### 1. 일반 사용자 계정 정의 (`workspace/users.txt`)
*주의: 파싱 에러 방지를 위해 탭(Tab) 대신 순수 공백(스페이스바)만 사용해야 하며, 마지막 설명 칸에는 띄어쓰기 대신 언더바(`_`)를 써야 비밀번호 해시가 깨지거나 Login incorrect가 발생하는 버그를 막을 수 있습니다.*
```text
sg -1 sg -1 raspberry /home/sg /bin/bash sudo,audio,video RaspberryPi_User
```

### 2. 와이파이 펌웨어 수동 복사 및 필수 세팅
라즈베리 파이 공식 저장소 등에서 수집한 원본 `bin`, `txt`, `clm_blob` 파일을 복사해 넣고 아래와 같이 제로 W 모델명 호환 링크를 만듭니다. 또한 계정 분리를 위해 홈 폴더를 미리 생성해 둡니다.
```bash
cd ~/pizero2w-build/workspace
mkdir -p rootfs-overlay/lib/firmware/brcm
mkdir -p rootfs-overlay/home/sg

# ⚠️ [필수 원본 파일 배치] 아래 3개 파일이 해당 폴더에 수동 보관되어 있어야 합니다.
# 1. brcmfmac43430-sdio.bin      (펌웨어 바이너리)
# 2. brcmfmac43430-sdio.clm_blob  (국가별 규격 블롭)
# 3. brcmfmac43430-sdio.txt       (NVRAM 설정 파일)

# ⚠️ 라즈베리 파이 제로 W 무선랜 구동을 위한 필수 심볼릭 링크 최종 구성
cd rootfs-overlay/lib/firmware/brcm
ln -sf brcmfmac43430-sdio.bin brcmfmac43430-sdio.raspberrypi,model-zero-w.bin
ln -sf brcmfmac43430-sdio.txt brcmfmac43430-sdio.raspberrypi,model-zero-w.txt
```

**💡 정상 구성 완료 시 파일 목록 체크리스트 (`ls -l rootfs-overlay/lib/firmware/brcm` 결과):**
```text
-rw-r--r-- 1 steven steven brcmfmac43430-sdio.bin
-rw-r--r-- 1 steven steven brcmfmac43430-sdio.clm_blob
lrwxrwxrwx 1 steven steven brcmfmac43430-sdio.raspberrypi,model-zero-w.bin -> brcmfmac43430-sdio.bin
lrwxrwxrwx 1 steven steven brcmfmac43430-sdio.raspberrypi,model-zero-w.txt -> brcmfmac43430-sdio.txt
-rw-r--r-- 1 steven steven brcmfmac43430-sdio.txt
```

### 3. 로그인 셸 목록 등록 (`rootfs-overlay/etc/shells`)
*기본 셸이 bash인 일반 계정의 `Login incorrect` 에러를 원천 차단하기 위해 유효 셸 목록을 명시합니다.*
```text
/bin/sh
/bin/ash
/bin/bash
/usr/bin/bash
```

### 4. 와이파이 비밀번호 설정 (`rootfs-overlay/etc/wpa_supplicant/wpa_supplicant.conf`)
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

### 5. 와이파이 드라이버 강제 로드 스크립트 (`rootfs-overlay/etc/init.d/S30wifi_load`)
```bash
#!/bin/sh
case "$1" in
  start)
    echo "Loading brcmfmac driver..."
    modprobe brcmfmac
    sleep 2
    ;;
esac
exit 0
```
*작성 후 실행 권한 필수 부여*: `chmod +x ~/pizero2w-build/workspace/rootfs-overlay/etc/init.d/S30wifi_load`

### 6. 무선 네트워크 인터페이스 설정 (`rootfs-overlay/etc/network/interfaces`)
```text
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

# 공유기의 MAC 주소 고정 기능을 활용하므로 클라이언트는 경량 dhcp 방식을 유지합니다.
auto wlan0
iface wlan0 inet dhcp
    pre-up ip link set wlan0 up
    pre-up sleep 2
    pre-up wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
    post-down killall wpa_supplicant
```

### 7. SSH 자동 기동 스크립트 (`rootfs-overlay/etc/init.d/S50dropbear`)
```bash
#!/bin/sh
case "$1" in
  start)
    mkdir -p /var/run/dropbear
    echo -n "Starting Dropbear SSH server: "
    dropbear -R -B
    echo "OK"
    ;;
  stop)
    echo -n "Stopping Dropbear SSH server: "
    killall dropbear
    echo "OK"
    ;;
  restart|reload)
    $0 stop
    sleep 1
    $0 start
    ;;
  *)
    echo "Usage: $0 {start|stop|restart}"
    exit 1
    ;;
esac
exit 0
```
*작성 후 실행 권한 필수 부여*: `chmod +x ~/pizero2w-build/workspace/rootfs-overlay/etc/init.d/S50dropbear`

### 8. vfat 부트 파티션 자동 마운트 (`rootfs-overlay/etc/fstab`)
```bash
mkdir -p ~/pizero2w-build/workspace/rootfs-overlay/boot/firmware
```
`rootfs-overlay/etc/fstab` 내용:
```text
/dev/root       /               ext4    noatime,rw      0       1
proc            /proc           proc    defaults        0       0
sysfs           /sys            sysfs   defaults        0       0
devpts          /dev/pts        devpts  defaults,gid=5,mode=620 0       0
tmpfs           /dev/shm        tmpfs   mode=0777       0       0
tmpfs           /tmp            tmpfs   mode=1777       0       0
tmpfs           /run            tmpfs   mode=0755       0       0

# 라즈베리 파이 vfat 부트 파티션 자동 마운트
/dev/mmcblk0p1  /boot/firmware  vfat    defaults        0       2
```

---

## 💾 Buildroot 커텀 설정 백업 및 복구 가이드

도커 컨테이너는 종료 시 내부 데이터가 초기화되므로, `menuconfig`에서 공들여 수정한 설정 값들을 외부 공유 폴더(`workspace`)에 파일로 영구 백업해 두어야 합니다 [INDEX: 1.2.65].

### 1. 현재 설정 백업하기 (도커 내부에서 실행)
빌드 트랙을 시작하기 전이나 설정을 마친 직후, 아래 명령어를 실행하여 미니멀한 설정 파일(`defconfig`)을 생성합니다 [INDEX: 1.2.56].
```bash
make savedefconfig BR2_DEFCONFIG=/home/builduser/workspace/raspberrypizero_custom_defconfig
```
명령이 완료되면 호스트의 `workspace/` 폴더에 `raspberrypizero_custom_defconfig` 파일이 안전하게 보존됩니다.

### 2. 백업본에서 설정 복구하기 (도커 재시작 시 실행)
컨테이너를 새로 켰거나 설정을 초기 상태에서 다시 불러와야 할 때, 아래 명령 한 줄로 모든 패키지 세팅 및 경로 설정을 1초 만에 복구할 수 있습니다 [INDEX: 1.2.56].
```bash
make defconfig BR2_DEFCONFIG=/home/builduser/workspace/raspberrypizero_custom_defconfig
```

---

## 🏗 시스템 빌드 및 실행
1. 도커 컨테이너에서 **`make`** 실행하여 컴파일.
2. 컴파일 완료 후 호스트로 복귀하여 이미지 플래싱:
   ```bash
   sudo dd if=workspace/buildroot/output/images/sdcard.img of=/Dev/sdX bs=4M status=progress && sync
   ```
3. 부팅 후 공유기 페이지에 설정해 둔 IP로 다이렉트 진입:
   ```bash
   ssh sg@<공유기가_고정한_IP>
   ```

---

## 💡 실전 트러블슈팅 및 팁
- **SSH 접속 시 즉시 튕기는 경우 (Connection closed)**: 
  파이 콘솔에 진입하여 `/var/run/dropbear` 폴더가 실제 존재하는지 확인하고, `dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key` 명령어로 암호화 키가 제대로 만들어지는지 디버깅하세요.
- **일반 사용자로 로그인 후 최고 관리자 권한 획득**:
  초경량화를 위해 `sudo` 패키지를 제외했으므로, 관리자 권한이 필요할 때는 다음 명령어를 사용해 `root` 계정으로 전환합니다:
  ```bash
  su -
  # 이후 menuconfig에서 세팅한 root 패스워드 입력
  ```

