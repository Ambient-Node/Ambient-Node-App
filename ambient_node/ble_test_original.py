import json
import asyncio
import threading
import sys
from datetime import datetime
from bluezero import peripheral

SERVICE_UUID = '12345678-1234-5678-1234-56789abcdef0'
CHAR_UUID = '12345678-1234-5678-1234-56789abcdef1'  # Write 특성 (Flutter → RPi)
NOTIFY_CHAR_UUID = '12345678-1234-5678-1234-56789abcdef2'  # Notify 특성 (RPi → Flutter)
DEVICE_NAME = 'AmbientNode'

_last_payload = {}
_connected_devices = {}  # MAC 주소 -> 기기 정보 저장
_app_running = True  # 앱 실행 상태
_notify_char = None  # Notification 특성 참조


def get_client_info(options):
    """BLE 클라이언트 정보 추출"""
    try:
        # options에서 클라이언트 정보 추출 (bluezero 라이브러리 버전에 따라 다를 수 있음)
        if options and isinstance(options, dict):
            # 일반적인 BLE 옵션에서 device 정보 추출
            device_path = options.get('device', '')
            if device_path:
                # device path에서 MAC 주소 추출 (예: /org/bluez/hci0/dev_XX_XX_XX_XX_XX_XX)
                if 'dev_' in device_path:
                    mac_part = device_path.split('dev_')[-1]
                    mac_address = mac_part.replace('_', ':')
                    return {
                        'address': mac_address,
                        'name': f"Device-{mac_address[-5:].replace(':', '')}"  # 기본 이름
                    }
        
        # 기본값 반환
        return {'address': 'Unknown', 'name': 'Unknown'}
    except Exception as e:
        print(f"클라이언트 정보 추출 오류: {e}")
        return {'address': 'Unknown', 'name': 'Unknown'}


def print_connected_devices():
    """연결된 기기 목록 출력"""
    current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"\n[{current_time}] === 연결된 기기 목록 ===")
    
    if not _connected_devices:
        print("현재 연결된 기기가 없습니다.")
    else:
        print(f"총 {len(_connected_devices)}개 기기가 연결되어 있습니다:")
        for i, (address, info) in enumerate(_connected_devices.items(), 1):
            last_seen = info['last_seen'].strftime('%H:%M:%S')
            client_name = info.get('client_name', 'Unknown')
            ble_name = info.get('ble_name', 'Unknown')
            
            print(f"  {i}. {info['name']} ({address})")
            print(f"      └ 앱 이름: {client_name}, BLE 이름: {ble_name}")
            print(f"      └ 마지막 활동: {last_seen}")
    
    print("=" * 60)


def print_help():
    """도움말 출력"""
    print("\n=== 사용 가능한 명령어 ===")
    print("list, l     : 연결된 기기 목록 출력")
    print("help, h     : 도움말 출력")
    print("clear, c    : 화면 지우기")
    print("status, s   : 시스템 상태 출력")
    print("quit, q     : 프로그램 종료")
    print("=" * 30)


def print_status():
    """시스템 상태 출력"""
    current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"\n[{current_time}] === 시스템 상태 ===")
    print(f"서비스 이름: {DEVICE_NAME}")
    print(f"서비스 UUID: {SERVICE_UUID}")
    print(f"특성 UUID: {CHAR_UUID}")
    print(f"연결된 기기 수: {len(_connected_devices)}")
    if _last_payload:
        print(f"마지막 수신 데이터: {_last_payload}")
    print("=" * 40)


async def handle_terminal_input():
    """터미널 입력 처리 (비동기)"""
    global _app_running
    
    def input_thread():
        global _app_running
        while _app_running:
            try:
                command = input().strip().lower()
                
                if command in ['list', 'l']:
                    print_connected_devices()
                elif command in ['help', 'h']:
                    print_help()
                elif command in ['clear', 'c']:
                    print('\033[2J\033[H')  # 화면 지우기
                elif command in ['status', 's']:
                    print_status()
                elif command in ['quit', 'q']:
                    print("\n프로그램을 종료합니다...")
                    _app_running = False
                    break
                elif command == '':
                    continue  # 빈 입력 무시
                else:
                    print(f"알 수 없는 명령어: '{command}'. 'help' 또는 'h'를 입력하세요.")
                    
            except (EOFError, KeyboardInterrupt):
                print("\n프로그램을 종료합니다...")
                _app_running = False
                break
    
    # 별도 스레드에서 입력 처리
    input_thread_obj = threading.Thread(target=input_thread, daemon=True)
    input_thread_obj.start()
    
    # 메인 루프에서 앱 상태 확인
    while _app_running:
        await asyncio.sleep(0.1)
    
    return input_thread_obj


def send_pairing_success(device_address):
    """페어링 성공 응답을 Flutter로 전송"""
    global _notify_char
    try:
        if _notify_char:
            response_data = {
                'type': 'pairing_success',
                'device_address': device_address,
                'timestamp': datetime.now().isoformat(),
                'message': 'Pairing completed successfully'
            }
            response_json = json.dumps(response_data)
            # Notification으로 응답 전송
            _notify_char.set_value(response_json.encode('utf-8'))
            print(f"[NOTIFY] Pairing success sent to {device_address}")
        else:
            print("[ERROR] Notify characteristic not available")
    except Exception as e:
        print(f"[ERROR] Failed to send pairing success: {e}")


def on_write(value, options):
    global _last_payload, _connected_devices
    try:
        data = bytes(value).decode('utf-8')
        payload = json.loads(data)
        _last_payload = payload

        # 페이로드에서 데이터 추출 (먼저 해야 함)
        power_on = payload.get('powerOn')
        speed = payload.get('speed')
        tracking = payload.get('trackingOn')
        selected_face = payload.get('selectedFaceId')
        manual = payload.get('manual')  # {'x': float, 'y': float}
        client_device_name = payload.get('deviceName', 'Unknown')  # Flutter에서 보낸 기기 이름
        client_timestamp = payload.get('timestamp')

        # 클라이언트 정보 추출
        client_info = get_client_info(options)
        device_name = client_info.get('name', 'Unknown')
        device_address = client_info.get('address', 'Unknown')
        
        # 연결된 기기 정보 업데이트
        if device_address != 'Unknown':
            # Flutter에서 보낸 이름을 우선 사용
            final_name = client_device_name if client_device_name != 'Unknown' else device_name
            
            # 새로운 기기인지 확인
            is_new_device = device_address not in _connected_devices
            
            _connected_devices[device_address] = {
                'name': final_name,
                'last_seen': datetime.now(),
                'client_name': client_device_name,
                'ble_name': device_name
            }
            
            # 새로운 기기라면 페어링 성공 응답 전송
            if is_new_device:
                print(f"[NEW DEVICE] {final_name} ({device_address}) 연결됨")
                send_pairing_success(device_address)

        # 현재 시간 가져오기
        current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        
        # 전원 상태와 무관하게 BLE 연결은 항상 유지
        # selectedFaceId 처리 (빈 문자열이면 NONE으로 표시)
        face_display = selected_face if selected_face and selected_face != "" else "NONE"
        
        # 기기 이름 표시 우선순위: Flutter에서 보낸 이름 > BLE에서 추출한 이름 > MAC 주소
        if client_device_name and client_device_name != 'Unknown':
            device_display = f"{client_device_name}({device_address[-8:]})" if device_address != 'Unknown' else client_device_name
        elif device_name != 'Unknown':
            device_display = f"{device_name}({device_address[-8:]})" if device_address != 'Unknown' else device_name
        else:
            device_display = device_address if device_address != 'Unknown' else "Unknown"
        
        if power_on:
            print(f'[{current_time}] [BLE] [{device_display}] POWER:ON SPEED:{speed}% TRACK:{tracking} FACE:{face_display}')
        else:
            print(f'[{current_time}] [BLE] [{device_display}] POWER:OFF SPEED:STOP TRACK:OFF FACE:NONE (BLE 연결 유지)')
        
        # TODO: 이 값을 사용해 모터/서보를 제어하도록 연결
    except Exception as e:
        current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        print(f'[{current_time}] [BLE] write parse error:', e)


async def main():
    global _notify_char
    
    # 어댑터 주소 확인
    ada = peripheral.adapter.Adapter()
    adapter_addr = ada.address

    # GATT 애플리케이션/서비스/특성 구성 (localGATT 사용)
    app = peripheral.localGATT.Application()
    srv = peripheral.localGATT.Service(1, SERVICE_UUID, True)
    
    print(f"Setting up service with UUID: {SERVICE_UUID}")
    print("Using write-without-response to avoid pairing")
    
    # Write 특성 (Flutter → RPi)
    write_ch = peripheral.localGATT.Characteristic(
        1,                      # service_id
        1,                      # characteristic_id
        CHAR_UUID,
        [],                     # 초기 값 (byte list)
        False,                  # notifying
        ['write-without-response'],  # write 제거, write-without-response만 사용
        read_callback=None,
        write_callback=on_write,
        notify_callback=None,
    )
    
    # Notify 특성 (RPi → Flutter) - 실시간 응답
    _notify_char = peripheral.localGATT.Characteristic(
        1,                      # service_id
        2,                      # characteristic_id
        NOTIFY_CHAR_UUID,
        [],                     # 초기 값 (byte list)
        False,                  # notifying
        ['notify'],             # notify 속성
        read_callback=None,
        write_callback=None,
        notify_callback=None,
    )

    app.add_managed_object(srv)
    app.add_managed_object(write_ch)
    app.add_managed_object(_notify_char)

    # GATT 매니저에 앱 등록
    gatt_mgr = peripheral.GATT.GattManager(adapter_addr)
    gatt_mgr.register_application(app, {})

    # 광고 설정 및 등록
    advert = peripheral.advertisement.Advertisement(1, 'peripheral')
    advert.local_name = DEVICE_NAME
    advert.service_UUIDs = [SERVICE_UUID]
    ad_mgr = peripheral.advertisement.AdvertisingManager(adapter_addr)
    ad_mgr.register_advertisement(advert, {})

    print('Advertising as', DEVICE_NAME)
    print('BLE 연결은 전원 상태와 무관하게 유지됩니다.')
    print('여러 기기가 동시에 연결될 수 있습니다.')
    print('데이터 수신 대기 중...')
    print()
    print('=== 페어링 안내 ===')
    print('Android에서 인증번호가 뜨면:')
    print('1. 라즈베리파이 터미널에서 동일한 번호 확인')
    print('2. Android에서 "예" 또는 "페어링" 버튼 클릭')
    print('3. 페어링 완료 후 자동으로 연결됩니다')
    print('로그에서 [기기이름(MAC주소)] 형태로 기기를 구분할 수 있습니다.')
    print()
    print('=== 터미널 명령어 ===')
    print('list 또는 l    : 연결된 기기 목록')
    print('help 또는 h    : 도움말')
    print('status 또는 s  : 시스템 상태')
    print('quit 또는 q    : 프로그램 종료')
    print('=' * 50)
    
    # BLE 서비스 시작 (별도 스레드)
    def start_ble_service():
        try:
            app.start()
        except Exception as e:
            print(f"BLE 서비스 오류: {e}")
    
    ble_thread = threading.Thread(target=start_ble_service, daemon=True)
    ble_thread.start()
    
    try:
        # 터미널 입력 처리 시작
        await handle_terminal_input()
    except KeyboardInterrupt:
        print('\n프로그램을 종료합니다...')
    finally:
        global _app_running
        _app_running = False
        # 정리 작업
        try:
            ad_mgr.unregister_advertisement(advert)
            gatt_mgr.unregister_application(app)
        except:
            pass
        print('BLE 서비스가 정상적으로 종료되었습니다.')


if __name__ == '__main__':
    asyncio.run(main())


