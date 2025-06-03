import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../database/pdu_database_helper.dart';
import '../database/pc_database_helper.dart';
import 'projector_service.dart';
import 'pdu_service.dart';
import 'pc_service.dart';

class ScheduleService {
  static final ScheduleService _instance = ScheduleService._internal();
  final DatabaseHelper _db = DatabaseHelper();
  final ProjectorService _projectorService = ProjectorService();
  final PduService _pduService = PduService();
  final PDUDatabaseHelper _pduDb = PDUDatabaseHelper();
  final PCDatabaseHelper _pcDb = PCDatabaseHelper();
  final PcService _pcService = PcService();
  Timer? _timer;

  // 싱글톤 패턴
  factory ScheduleService() => _instance;
  ScheduleService._internal();

  // 서비스 시작
  void start() {
    _timer?.cancel();
    // 30초마다 스케줄 체크
    _timer = Timer.periodic(const Duration(seconds: 30), _checkSchedules);
    debugPrint('스케줄 서비스가 시작되었습니다. (실행 주기: 30초)');
  }

  // 서비스 중지
  void stop() {
    _timer?.cancel();
    _timer = null;
    debugPrint('스케줄 서비스가 중지되었습니다.');
  }

  // 스케줄 체크 및 실행
  Future<void> _checkSchedules(Timer timer) async {
    try {
      final now = DateTime.now();
      final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      // 일요일(7)을 0으로 변환하여 일요일도 인식하도록 수정
      final currentDay = (now.weekday == 7) ? '0' : now.weekday.toString();  // 0 = 일요일, 1-6 = 월-토요일
      
      debugPrint('스케줄 체크 시작: $currentTime, 요일: $currentDay (0=일요일, 1-6=월-토요일)');
      
      // 일반 스케줄 확인
      final schedules = await _db.getAllSchedules();

      for (final schedule in schedules) {
        if (schedule['is_active'] != 1) continue;  // 비활성화된 스케줄 무시
        
        final deviceType = schedule['device_type'] as String;
        final powerOnTime = schedule['power_on_time'] as String;
        final powerOffTime = schedule['power_off_time'] as String;
        final days = schedule['days'] as String;  // 쉼표로 구분된 요일 문자열

        // 현재 요일이 스케줄에 포함되어 있는지 확인
        if (!days.split(',').contains(currentDay)) continue;

        if (currentTime == powerOnTime) {
          await _executeSchedule(deviceType, 'power_on');
        } else if (currentTime == powerOffTime) {
          await _executeSchedule(deviceType, 'power_off');
        }
      }
      
      // 공통 PDU 스케줄 확인
      await _checkCommonPDUSchedules(currentTime, currentDay);
      
      // 공통 PC 스케줄 확인 (새로 추가)
      await _checkPCSchedules(currentTime, currentDay);
      
    } catch (e) {
      debugPrint('스케줄 체크 중 오류 발생: $e');
    }
  }
  
  // 공통 PDU 스케줄 확인 및 실행
  Future<void> _checkCommonPDUSchedules(String currentTime, String currentDay) async {
    try {
      debugPrint('공통 PDU 스케줄 확인 중...');
      debugPrint('현재 요일: $currentDay (0=일요일, 1-6=월-토요일)');
      
      // PDU 스케줄 가져오기 (단일 스케줄)
      final schedules = await _pduDb.getPDUSchedule();
      
      if (schedules.isEmpty) {
        debugPrint('등록된 PDU 스케줄이 없습니다.');
        return;
      }
      
      final schedule = schedules.first;
      if (schedule['is_active'] != 1) {
        debugPrint('PDU 스케줄이 비활성화되어 있습니다.');
        return;
      }
      
      final powerOnTime = schedule['power_on_time'] as String;
      final powerOffTime = schedule['power_off_time'] as String;
      final days = schedule['days'] as String;  // 쉼표로 구분된 요일 문자열

      debugPrint('PDU 스케줄: 켜기=$powerOnTime, 끄기=$powerOffTime, 요일=$days');
      
      // 현재 요일이 스케줄에 포함되어 있는지 확인
      if (!days.split(',').contains(currentDay)) {
        debugPrint('현재 요일($currentDay)은 스케줄 요일에 포함되지 않습니다.');
        return;
      }

      // 시간 체크 및 명령 실행
      if (currentTime == powerOnTime) {
        debugPrint('PDU 전원 켜기 시간입니다! 시간: $currentTime');
        await _executePDUCommandForAll('power_on');
      } else if (currentTime == powerOffTime) {
        debugPrint('PDU 전원 끄기 시간입니다! 시간: $currentTime');
        await _executePDUCommandForAll('power_off');
      }
    } catch (e) {
      debugPrint('PDU 스케줄 체크 중 오류 발생: $e');
    }
  }
  
  // 모든 PDU에 명령 실행
  Future<void> _executePDUCommandForAll(String action) async {
    try {
      debugPrint('모든 PDU에 $action 명령 실행 시작');
      
      // 모든 PDU 가져오기
      final pdus = await _pduDb.getAllPDUs();
      debugPrint('총 ${pdus.length}개의 PDU에 명령 실행');
      
      if (pdus.isEmpty) {
        debugPrint('등록된 PDU가 없습니다.');
        return;
      }
      
      int successCount = 0;
      int failCount = 0;
      
      for (final pdu in pdus) {
        final id = pdu['id'];
        final uuid = pdu['uuid'];
        final name = pdu['name'] ?? 'PDU';
        
        // UUID 또는 ID를 사용하여 명령 실행
        try {
          debugPrint('PDU "$name" ($uuid)에 $action 명령 실행 중...');
          final payload = uuid != null && uuid.toString().isNotEmpty 
              ? jsonEncode({'pdu_uuid': uuid, 'outlet_id': 0, 'action': action})
              : jsonEncode({'pdu_id': id, 'outlet_id': 0, 'action': action});
              
          final result = await _pduService.executeCommand(payload);
          
          // 결과 확인
          if (result.contains('"success":true')) {
            debugPrint('PDU "$name" $action 명령 성공');
            successCount++;
          } else {
            debugPrint('PDU "$name" $action 명령 실패: $result');
            failCount++;
          }
        } catch (e) {
          debugPrint('PDU "$name" $action 명령 실행 중 오류: $e');
          failCount++;
        }
      }
      
      debugPrint('PDU 명령 실행 완료: 성공=$successCount, 실패=$failCount');
    } catch (e) {
      debugPrint('모든 PDU 명령 실행 중 오류 발생: $e');
    }
  }

  // PC 스케줄 확인 및 실행
  Future<void> _checkPCSchedules(String currentTime, String currentDay) async {
    try {
      print('PC 스케줄 확인 중...');
      // 현재 요일을 1-7 형식으로 변환 (1=월요일, 7=일요일)
      int weekday = DateTime.now().weekday;  // 1-7 (월-일)
      String adjustedDay = weekday.toString();
      if (weekday == 7) {
        adjustedDay = '0';  // 일요일은 0으로 저장되어 있음
      }
      
      print('현재 요일: $adjustedDay (1-6=월-토요일, 0=일요일)');
      
      // PC 스케줄 가져오기
      final schedules = await _pcDb.getPCSchedule();
      
      if (schedules.isEmpty) {
        print('등록된 PC 스케줄이 없습니다.');
        return;
      }
      
      final schedule = schedules.first;
      if (schedule['is_active'] != 1) {
        print('PC 스케줄이 비활성화되어 있습니다.');
        return;
      }
      
      final wakeOnTime = schedule['wake_on_time'] as String?;
      final shutdownTime = schedule['shutdown_time'] as String?;
      final days = schedule['days'] as String;

      print('PC 스케줄: 켜기=${wakeOnTime ?? "없음"}, 끄기=${shutdownTime ?? "없음"}, 요일=$days');
      
      // 현재 요일이 스케줄에 포함되어 있는지 확인
      if (!days.split(',').contains(adjustedDay)) {
        print('현재 요일($adjustedDay)은 PC 스케줄 요일에 포함되지 않습니다.');
        return;
      }

      // WOL 시간 체크 및 명령 실행
      if (wakeOnTime != null && currentTime == wakeOnTime) {
        print('PC Wake On LAN 시간입니다! 시간: $currentTime');
        await _executePCWakeAction(0);
      }
      
      // 종료 시간 체크 및 명령 실행
      if (shutdownTime != null && currentTime == shutdownTime) {
        print('PC 종료 시간입니다! 시간: $currentTime');
        await _executePCShutdownAction(0);
      }
    } catch (e) {
      print('PC 스케줄 체크 중 오류 발생: $e');
    }
  }

  // 스케줄 실행
  Future<void> _executeSchedule(String deviceType, String action) async {
    try {
      switch (deviceType) {
        case 'projector':
          final projectors = await _db.getProjectors();
          for (final projector in projectors) {
            final ip = projector['ip'] as String;
            final result = await _projectorService.executeCommand(
              '{"ip": "$ip", "command": "$action"}'
            );
            await _logScheduleExecution(deviceType, action, result);
          }
          break;
        case 'pdu':
          // PDU 가져오기
          final pduDatabaseHelper = PDUDatabaseHelper();
          final pdus = await pduDatabaseHelper.getAllPDUs();
          debugPrint('PDU 스케줄 실행: $action, PDU 개수: ${pdus.length}');
          
          for (final pdu in pdus) {
            final id = pdu['id'];
            final uuid = pdu['uuid'];
            
            // UUID를 사용하여 명령 실행
            if (uuid != null && uuid.toString().isNotEmpty) {
              final result = await _pduService.executeCommand(jsonEncode({
                'pdu_uuid': uuid,
                'outlet_id': 0,
                'action': action
              }));
              await _logScheduleExecution('pdu', action, result);
              debugPrint('PDU 스케줄 명령 실행: $uuid, 결과: $result');
            } 
            // UUID가 없을 경우 ID 사용
            else if (id != null) {
              final result = await _pduService.executeCommand(jsonEncode({
                'pdu_id': id,
                'outlet_id': 0,
                'action': action
              }));
              await _logScheduleExecution('pdu', action, result);
              debugPrint('PDU 스케줄 명령 실행: $id, 결과: $result');
            }
          }
          break;
        // TODO: 다른 장치 타입에 대한 처리 추가
      }
    } catch (e) {
      debugPrint('스케줄 실행 중 오류 발생: $e');
      await _logScheduleExecution(deviceType, action, '{"success": false, "error": "$e"}');
    }
  }

  // 스케줄 로그 기록
  Future<void> _logScheduleExecution(String deviceType, String action, String result) async {
    try {
      final status = result.contains('"success":true') ? 'success' : 'failed';
      await _db.logScheduleExecution(deviceType, action, status);
    } catch (e) {
      debugPrint('스케줄 로그 기록 중 오류 발생: $e');
    }
  }

  // 스케줄 설정
  Future<String> setSchedule(String deviceType, String powerOnTime, String powerOffTime, String days) async {
    try {
      // 요일 형식 검증 (1-7, 쉼표로 구분)
      final daysList = days.split(',');
      for (final day in daysList) {
        final dayNum = int.tryParse(day);
        if (dayNum == null || dayNum < 1 || dayNum > 7) {
          return '{"success": false, "error": "잘못된 요일 형식입니다. 1(월요일)부터 7(일요일)까지의 숫자를 쉼표로 구분하여 입력하세요."}';
        }
      }

      await _db.updateSchedule(deviceType, powerOnTime, powerOffTime, days);
      return '{"success": true, "message": "스케줄이 성공적으로 설정되었습니다."}';
    } catch (e) {
      return '{"success": false, "error": "$e"}';
    }
  }

  // 스케줄 조회
  Future<String> getSchedule(String deviceType) async {
    try {
      final schedule = await _db.getScheduleByType(deviceType);
      return '{"success": true, "schedule": ${schedule.toString()}}';
    } catch (e) {
      return '{"success": false, "error": "$e"}';
    }
  }

  // 스케줄 로그 조회
  Future<String> getLogs() async {
    try {
      final logs = await _db.getScheduleLogs();
      return '{"success": true, "logs": ${logs.toString()}}';
    } catch (e) {
      return '{"success": false, "error": "$e"}';
    }
  }

  // PC 켜기 명령 실행
  Future<void> _executePCWakeAction(int groupId) async {
    try {
      List<Map<String, dynamic>> pcs;
      
      if (groupId == 0) {
        // 모든 PC 가져오기
        pcs = await _pcDb.getAllPCs();
      } else {
        // 특정 그룹의 PC 가져오기
        pcs = await _pcDb.getPCsByGroup(groupId);
      }
      
      if (pcs.isEmpty) {
        print('켤 PC가 없습니다.');
        return;
      }
      
      int successCount = 0;
      
      for (final pc in pcs) {
        try {
          // PC 켜기 명령 실행
          final payload = jsonEncode({
            'pc_uuid': pc['uuid'],
            'action': 'wake'
          });
          
          final result = await _pcService.executeCommand(payload);
          final data = jsonDecode(result);
          
          if (data['success']) {
            print('PC "${pc['name']}" 켜기 성공');
            successCount++;
          } else {
            print('PC "${pc['name']}" 켜기 실패: ${data['error'] ?? "알 수 없는 오류"}');
          }
        } catch (e) {
          print('PC "${pc['name']}" 켜기 중 오류: $e');
        }
      }
      
      print('PC 켜기 완료: $successCount/${pcs.length} 성공');
    } catch (e) {
      print('PC 켜기 액션 실행 오류: $e');
    }
  }
  
  // PC 끄기 명령 실행
  Future<void> _executePCShutdownAction(int groupId) async {
    try {
      List<Map<String, dynamic>> pcs;
      
      if (groupId == 0) {
        // 모든 PC 가져오기
        pcs = await _pcDb.getAllPCs();
      } else {
        // 특정 그룹의 PC 가져오기
        pcs = await _pcDb.getPCsByGroup(groupId);
      }
      
      if (pcs.isEmpty) {
        print('끌 PC가 없습니다.');
        return;
      }
      
      int successCount = 0;
      
      for (final pc in pcs) {
        try {
          final ipAddress = pc['ip'];
          print('스케줄에 의한 PC "${pc['name']}" 종료 시작 (IP: $ipAddress)');
          
          // 기존 방식: PC 서비스 통한 종료 명령
          final payload = jsonEncode({
            'pc_uuid': pc['uuid'],
            'action': 'shutdown'
          });
          
          // 먼저 기존 방식으로 시도
          bool success = false;
          try {
            final result = await _pcService.executeCommand(payload);
            final data = jsonDecode(result);
            
            // 기존 종료 명령 성공 여부 확인
            if (data['success']) {
              print('PC "${pc['name']}" 종료 명령 전송 성공 (기존 방식)');
              success = true;
            } else {
              print('PC "${pc['name']}" 종료 명령 실패 (기존 방식): ${data['error'] ?? "알 수 없는 오류"}');
            }
          } catch (e) {
            print('PC 서비스 명령 실행 중 오류: $e');
          }
          
          // 성공 여부와 관계없이 항상 직접 ShutdownServer 호출을 시도
          // (이중 보장을 위해 두 가지 방식 모두 시도)
          try {
            print('직접 ShutdownServer 호출 시도: http://$ipAddress:8081/shutdown');
            
            // 웹 인터페이스와 동일한 방식으로 요청 (HttpClient 대신 http 패키지 사용)
            try {
              // 명령어 실행으로 curl 사용 - 웹 인터페이스와 유사한 요청 방식
              final process = await Process.run('curl', [
                '-X', 'POST',
                '-H', 'Content-Type: application/json',
                '-d', '{"action":"shutdown"}',
                'http://$ipAddress:8081/shutdown',
                '--connect-timeout', '5'  // 연결 타임아웃 5초
              ]);
              
              if (process.exitCode == 0) {
                print('PC "${pc['name']}" 종료 요청 성공 (curl 호출)');
                success = true;
              } else {
                print('PC "${pc['name']}" 종료 요청 실패 (curl 호출): ${process.stderr}');
              }
            } catch (curlError) {
              print('curl 명령 실행 오류: $curlError');
              
              // curl 실패 시 기본 HttpClient 사용 (백업 방법)
              final client = HttpClient();
              client.connectionTimeout = Duration(seconds: 5); // 연결 타임아웃 설정
              
              try {
                final request = await client.postUrl(Uri.parse('http://$ipAddress:8081/shutdown'));
                request.headers.set('Content-Type', 'application/json');
                request.add(utf8.encode(jsonEncode({'action': 'shutdown'})));
                final response = await request.close();
                
                if (response.statusCode >= 200 && response.statusCode < 300) {
                  print('PC "${pc['name']}" 종료 요청 성공 (HttpClient 직접 호출)');
                  success = true;
                } else {
                  print('PC "${pc['name']}" 종료 요청 실패 (HttpClient 직접 호출): 상태 코드 ${response.statusCode}');
                }
              } finally {
                client.close();
              }
            }
          } catch (directError) {
            print('PC "${pc['name']}" ShutdownServer 호출 중 오류: $directError');
          }
          
          if (success) {
            successCount++;
            
            // 성공 시 PC 상태 업데이트
            try {
              await _pcDb.updatePCStatus(pc['id'], 'shutting_down');
              print('PC "${pc['name']}" 상태 업데이트: shutting_down');
            } catch (e) {
              print('PC 상태 업데이트 오류: $e');
            }
          }
        } catch (e) {
          print('PC "${pc['name']}" 끄기 중 오류: $e');
        }
      }
      
      print('PC 끄기 완료: $successCount/${pcs.length} 성공');
    } catch (e) {
      print('PC 끄기 액션 실행 오류: $e');
    }
  }
} 