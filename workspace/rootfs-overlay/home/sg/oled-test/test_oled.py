import datetime
import time
from smbus import SMBus
import adafruit_ssd1306
from PIL import Image, ImageDraw, ImageFont

# 1. I2C 인터페이스 및 SSD1306 디스플레이 초기화 (주소 0x3C)
# Buildroot 환경의 순수 smbus 기반 매핑 레이아웃 적용
class I2C_Device:
    def __init__(self, bus_num=1, addr=0x3c):
        self.bus = SMBus(bus_num)
        self.addr = addr

    def write_i2c_block_data(self, addr, reg, data):
        self.bus.write_i2c_block_data(self.addr, reg, data)

    # 대용량 프레임 데이터를 16바이트 청크 단위로 완벽하게 쪼개어 전송
    def write(self, buf):
        if len(buf) == 0:
            return

        # 1. 첫 번째 바이트(컨트롤 바이트)를 순수 정수(Integer) 값으로 추출
        # (이 값이 SMBus의 커맨드/레지스터 번호 역할을 하게 됩니다.)
        control_byte = int(buf[0])

        if len(buf) == 1:
            # 데이터 없이 컨트롤 바이트만 단독으로 보내는 명령일 경우
            self.bus.write_byte(self.addr, control_byte)
            return

        # 2. 두 번째 바이트부터 끝까지의 순수 데이터 영역을 리스트로 추출
        data_bytes = list(buf[1:])

        # 3. SMBus 32바이트 안전 한계선에 맞춰 16바이트씩 슬라이싱하여 순차 전송
        chunk_size = 16

        for i in range(0, len(data_bytes), chunk_size):
            # 16바이트씩 쪼갠 조각 데이터 생성
            chunk = data_bytes[i:i + chunk_size]

            # ⚠️ 중요: 세 번째 인자에 전체 데이터(data)가 아닌 조각(chunk)을 명시해야 합니다.
            self.bus.write_i2c_block_data(self.addr, control_byte, chunk)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        pass


i2c = I2C_Device(bus_num=1, addr=0x3c)
display = adafruit_ssd1306.SSD1306_I2C(128, 64, i2c)

# 텍스트 출력을 위한 기본 폰트 로드
font = ImageFont.load_default()

print("OLED 실시간 시계 시작... (종료하려면 Ctrl+C)")

try:
    while True:
        # 1. 매 루프마다 화면 버퍼용 빈 캔버스 생성 (128x64, 흑백)
        image = Image.new("1", (display.width, display.height))
        draw = ImageDraw.Draw(image)

        # 2. 상단 타이틀 텍스트 그리기
        draw.text((0, 0), "Hello Buildroot!", font=font, fill=255)
        draw.text((0, 15), "System Clock", font=font, fill=255)

        # 3. 하단에 시간을 감싸줄 사각형 테두리 그리기
        # (좌상단 X:0, Y:35) 부터 (우하단 X:127, Y:63) 까지
        draw.rectangle((0, 35, 127, 63), outline=255, fill=0)

        # 4. 현재 시스템 시각 가져오기 (연-월-일 시:분:초 형식)
        now = datetime.datetime.now()
        date_str = now.strftime("%Y-%m-%d")
        time_str = now.strftime("%H:%M:%S")

        # 5. 사각형 박스 내부 중앙 정렬에 맞춰 시각 텍스트 배치
        # Y값 위치를 사각형 내부인 40, 50 레이어로 지정합니다.
        draw.text((8, 40), f"Date: {date_str}", font=font, fill=255)
        draw.text((15, 51), f"Time: {time_str}", font=font, fill=255)

        # 6. 완성된 이미지 버퍼를 OLED 하드웨어로 스트리밍 전송
        display.image(image)
        display.show()

        # 7. 1초마다 화면을 갱신하도록 대기 (CPU 점유율 폭등 방지)
        time.sleep(1)

except KeyboardInterrupt:
    # Ctrl+C 입력 시 화면을 깔끔하게 지우고 안전하게 종료
    display.fill(0)
    display.show()
    print("\nOLED 시계 가동을 안전하게 종료했습니다.")
