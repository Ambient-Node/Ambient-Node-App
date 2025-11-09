#!/bin/bash

# Bluetooth 자동 페어링 설정 스크립트
echo "Setting up Bluetooth for automatic pairing..."

# 1. 현재 설정 확인
echo "현재 Bluetooth 설정을 확인합니다..."
sudo systemctl status bluetooth

# 2. bluetoothctl로 안전하게 설정
echo "bluetoothctl로 페어링 설정을 변경합니다..."
sudo bluetoothctl << EOF
agent NoInputNoOutput
default-agent
pairable on
discoverable on
exit
EOF

# 3. 기존 페어링 기록 완전 삭제
echo "기존 페어링 기록을 완전히 삭제합니다..."
sudo rm -rf /var/lib/bluetooth/*/cache/
PAIRED_DEVICES=$(sudo bluetoothctl devices | cut -f2 -d' ')
for device in $PAIRED_DEVICES; do
    echo "삭제 중: $device"
    sudo bluetoothctl remove $device
done

# 4. Bluetooth 서비스 재시작
echo "Bluetooth 서비스를 재시작합니다..."
sudo systemctl restart bluetooth
sleep 2

# 5. 다시 설정 적용
echo "설정을 다시 적용합니다..."
sudo bluetoothctl << EOF
agent NoInputNoOutput
default-agent
pairable on
discoverable on
exit
EOF

echo ""
echo "=== 설정 완료 ==="
echo "모든 기존 페어링 기록이 삭제되었습니다."
echo "NoInputNoOutput 에이전트가 설정되었습니다."
echo "이제 Python 스크립트를 실행하세요: python3 ble_test_original.py"
echo ""
echo "Android에서도 Bluetooth 설정에서 'AmbientNode' 기기를 삭제하세요!"

# 실행 방법 : chmod +x bluetooth_setup.sh && ./bluetooth_setup.sh