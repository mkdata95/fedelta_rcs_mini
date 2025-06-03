import 'dart:async';
import 'package:flutter/material.dart';
import '../database/pdu_database_helper.dart';
import 'pdu_service.dart';

class PDUScheduleService {
  final PDUDatabaseHelper _db = PDUDatabaseHelper();
  final PduService _pduService = PduService();
  Timer? _timer;
  
  // 마지막 실행 시간 기록을 위한 변수 추가
  Map<String, String> _lastExecutedScheduleTimes = {
    'on': '',
    'off': ''
  };
  
  // 서비스 시작
  void start() {
    if (_timer != null) {
      print('[PDU-SCHEDULE] 이미 실행 중인 타이머가 있어 중지 후 재시작합니다.');
      _timer?.cancel();
    }
    
    // 타이머 시작 전 현재 시간 기록
    final now = DateTime.now();
    final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    
    print('[PDU-SCHEDULE] PDU 스케줄 서비스 시작됨 (현재 시간: $currentTime)');
    
    // 스케줄 서비스 시작 여부를 확인할 수 있는 로그 추가
    print('[PDU-SCHEDULE] 30초 간격으로 스케줄 확인 타이머 시작됨');
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      print('[PDU-SCHEDULE] 타이머 실행: ${timer.tick}번째 실행');
      _checkSchedules(timer);
    });
    
    // 시작과 동시에 한 번 실행
    print('[PDU-SCHEDULE] 초기 스케줄 확인 실행');
    _checkSchedules(null);
  }
  
  // 서비스 종료
  void stop() {
    _timer?.cancel();
    _timer = null;
    print('[PDU-SCHEDULE] PDU 스케줄 서비스 종료됨');
  }
  
  // 스케줄 실행
  Future<void> executeSchedule() async {
    print('[PDU-SCHEDULE] 수동 스케줄 실행 요청됨');
    await _checkSchedules(null);
  }
  
  // 스케줄 확인 및 실행
  Future<void> _checkSchedules(Timer? timer) async {
    try {
      final now = DateTime.now();
      final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      
      // 현재 요일 (Dart의 weekday는 1-7, 월-일)
      // 스케줄에서는 1-7 형식을 사용하므로 변환할 필요 없음
      final currentDay = now.weekday.toString();
      
      print('[PDU-SCHEDULE] 스케줄 확인 중... (현재 시간: $currentTime, 요일: $currentDay)');
      
      // 스케줄 가져오기 (단일 스케줄 방식)
      final schedules = await _db.getPDUSchedule();
      if (schedules.isEmpty) {
        print('[PDU-SCHEDULE] 등록된 PDU 스케줄이 없습니다.');
        return;
      }
      
      // 단일 스케줄 사용
      final schedule = schedules.first;
      if (schedule['is_active'] != 1) {
        print('[PDU-SCHEDULE] PDU 스케줄이 비활성화되어 있습니다.');
        return;
      }
      
      // 요일 체크
      final days = schedule['days'].split(',');
      if (!days.contains(currentDay)) {
        print('[PDU-SCHEDULE] 현재 요일($currentDay)은 스케줄 실행일이 아님 (스케줄 요일: ${schedule['days']})');
        return;  // 오늘은 스케줄 실행일이 아님
      }
      
      final powerOnTime = schedule['power_on_time'];
      final powerOffTime = schedule['power_off_time'];
      
      // 마지막 실행 시간 확인 (중복 실행 방지)
      
      // 켜기 시간 검사
      if (powerOnTime == currentTime && _lastExecutedScheduleTimes['on'] != currentTime) {
        print('[PDU-SCHEDULE] 스케줄에 따라 모든 PDU 전원 켜기 시작: $currentTime');
        
        // 마지막 실행 시간 업데이트
        _lastExecutedScheduleTimes['on'] = currentTime;
        
        // 모든 PDU에 명령 실행
        await _executeAllPDUs('on');
      }
      
      // 끄기 시간 검사
      if (powerOffTime == currentTime && _lastExecutedScheduleTimes['off'] != currentTime) {
        print('[PDU-SCHEDULE] 스케줄에 따라 모든 PDU 전원 끄기 시작: $currentTime');
        
        // 마지막 실행 시간 업데이트
        _lastExecutedScheduleTimes['off'] = currentTime;
        
        // 모든 PDU에 명령 실행
        await _executeAllPDUs('off');
      }
    } catch (e) {
      print('[PDU-SCHEDULE] 스케줄 실행 오류: $e');
      print('[PDU-SCHEDULE] 오류 세부 정보: ${e.toString()}');
    }
  }
  
  // 모든 PDU에 명령 실행
  Future<void> _executeAllPDUs(String action) async {
    try {
      // 모든 PDU 가져오기
      final pdus = await _db.getAllPDUs();
      print('[PDU-SCHEDULE] 총 ${pdus.length}개의 PDU에 명령 실행');
      
      if (pdus.isEmpty) {
        print('[PDU-SCHEDULE] 등록된 PDU가 없습니다.');
        return;
      }
      
      int successCount = 0;
      int offlineCount = 0;
      
      for (final pdu in pdus) {
        // PDU 네트워크 상태 확인
        if (pdu['network_status'] != 'online') {
          print('[PDU-SCHEDULE] PDU ${pdu['name']} (${pdu['ip']})의 네트워크 상태가 오프라인이므로 건너뜁니다.');
          offlineCount++;
          continue;
        }
        
        print('[PDU-SCHEDULE] 스케줄 명령 실행: ${pdu['name']}, 액션: $action');
        
        final result = await _pduService.executeScheduledCommand(pdu, action);
        if (result['success'] == true) {
          successCount++;
          print('[PDU-SCHEDULE] PDU ${pdu['name']} 전원 ${action == 'on' ? '켜기' : '끄기'} 성공! (스케줄)');
          print('[PDU-SCHEDULE] 응답 내용: ${result['response'] ?? "없음"}');
        } else {
          print('[PDU-SCHEDULE] PDU ${pdu['name']} 전원 ${action == 'on' ? '켜기' : '끄기'} 실패: ${result['error']} (스케줄)');
          print('[PDU-SCHEDULE] 실패 상세: ${result['response'] ?? "없음"}');
        }
        
        // PDU 로그에 기록
        await _db.insertPDULog({
          'pdu_id': pdu['id'],
          'outlet_id': 0,
          'action': 'scheduled_$action',
          'result': '{"success": ${result['success']}, "action": "$action"}'
        });
      }
      
      print('[PDU-SCHEDULE] 스케줄 실행 완료: 총 ${pdus.length}개 중 $successCount개 성공, ${offlineCount}개 오프라인');
    } catch (e) {
      print('[PDU-SCHEDULE] 모든 PDU 명령 실행 중 오류: $e');
    }
  }
  
  // 수동으로 모든 PDU 전원 켜기
  Future<void> turnOnAllPDUs() async {
    await _executeAllPDUs('on');
  }
  
  // 수동으로 모든 PDU 전원 끄기
  Future<void> turnOffAllPDUs() async {
    await _executeAllPDUs('off');
  }
} 