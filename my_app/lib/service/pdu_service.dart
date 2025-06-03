  // PDU 전원 상태 변경
  Future<bool> changePowerState(String uuid, bool powerOn) async {
    try {
      print('PDU 전원 상태 변경 시도: uuid=$uuid, powerOn=$powerOn');
      PDUModel? pdu = await dbHelper.getPDUByUUID(uuid);
      
      if (pdu == null) {
        print('PDU를 찾을 수 없음: uuid=$uuid');
        return false;
      }
      
      final String command = powerOn ? 'ON' : 'OFF';
      final response = await sendPDUCommand(pdu, command);
      
      if (response['success']) {
        String newStatus = powerOn ? 'online' : 'standby';
        // 상태와 전원 상태 모두 업데이트
        await dbHelper.updatePDUStatusByUUID(uuid, newStatus);
        await dbHelper.updatePDUPowerStatusByUUID(uuid, newStatus);
        print('PDU 전원 상태 변경 성공: $newStatus');
        return true;
      } else {
        print('PDU 전원 상태 변경 실패: ${response['message']}');
        return false;
      }
    } catch (e) {
      print('PDU 전원 상태 변경 중 오류 발생: $e');
      return false;
    }
  } 