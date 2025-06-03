import 'dart:async';
import 'dart:convert';

import '../database/database_helper.dart';
import '../services/projector_service.dart';

class ProjectorScheduleService {
  final DatabaseHelper _db = DatabaseHelper();
  final ProjectorService _projectorService = ProjectorService();
  Timer? _timer;
  
  // 마지막 실행 시간 기록을 위한 변수 추가
  String _lastOnTime = '';
  String _lastOffTime = '';
  
  // 서비스 시작
  void start() {
    print('프로젝터 스케줄 서비스 시작...');
    // 기존 타이머가 있으면 취소
    _timer?.cancel();
    
    // 30초마다 스케줄 체크
    _timer = Timer.periodic(Duration(seconds: 30), (timer) {
      _checkSchedule();
    });
    
    // 서비스 시작시 즉시 한 번 실행
    _checkSchedule();
  }
  
  // 서비스 중지
  void stop() {
    print('프로젝터 스케줄 서비스 중지...');
    _timer?.cancel();
    _timer = null;
  }
  
  // 스케줄 확인
  Future<void> _checkSchedule() async {
    try {
      final now = DateTime.now();
      final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final currentDay = now.weekday.toString();
      
      print('프로젝터 스케줄 확인 중... 현재 시간: $currentTime, 요일: $currentDay');
      
      // 스케줄 조회
      final db = await _db.database;
      final List<Map<String, dynamic>> schedules = await db.query(
        'schedules',
        where: 'device_type = ?',
        whereArgs: ['projector'],
      );
      
      if (schedules.isEmpty) {
        print('설정된 프로젝터 스케줄이 없습니다.');
        return;
      }
      
      final schedule = schedules.first;
      
      // 스케줄이 활성화되어 있는지 확인
      final isActive = schedule['is_active'] == 1;
      if (!isActive) {
        print('프로젝터 스케줄이 비활성화되어 있습니다.');
        return;
      }
      
      // 요일 확인
      final List<String> days = schedule['days'].toString().split(',');
      if (!days.contains(currentDay)) {
        print('오늘($currentDay)은 스케줄에 포함되지 않은 요일입니다.');
        return;
      }
      
      // 시간에 따른 동작 수행 - 중복 실행 방지 로직 추가
      if (schedule['power_on_time'] == currentTime && _lastOnTime != currentTime) {
        print('프로젝터 전원 켜기 시간입니다!');
        await _executeProjectorCommand('on');
        // 마지막 실행 시간 기록
        _lastOnTime = currentTime;
      } else if (schedule['power_off_time'] == currentTime && _lastOffTime != currentTime) {
        print('프로젝터 전원 끄기 시간입니다!');
        await _executeProjectorCommand('off');
        // 마지막 실행 시간 기록
        _lastOffTime = currentTime;
      }
      
      // 분이 바뀌면 마지막 실행 시간 초기화 (다음 날 같은 시간에 다시 실행되도록)
      if (now.minute == 0 && now.second < 30) {
        _resetLastExecutionTimes();
      }
    } catch (e) {
      print('프로젝터 스케줄 확인 중 오류 발생: $e');
    }
  }
  
  // 마지막 실행 시간 초기화
  void _resetLastExecutionTimes() {
    _lastOnTime = '';
    _lastOffTime = '';
  }
  
  // 모든 프로젝터에 명령 실행
  Future<void> _executeProjectorCommand(String command) async {
    try {
      // 모든 프로젝터 가져오기
      final projectors = await _db.getProjectors();
      
      // 로그 출력 최소화
      // print('${projectors.length}개의 프로젝터에 $command 명령을 전송합니다.');
      
      for (final projector in projectors) {
        try {
          final id = projector['id'].toString();
          final ip = projector['ip'].toString();
          // 상세 로그 출력 최소화
          // print('프로젝터 ID: $id, IP: $ip에 $command 명령 실행 중...');
          
          // 명령 실행
          final resultJson = await _projectorService.executeCommand(jsonEncode({
            'ip': ip,
            'command': command == 'on' ? 'power_on' : 'power_off'
          }));
          
          final result = jsonDecode(resultJson);
          
          // 결과 로깅
          await _db.logScheduleExecution(
            'projector', 
            command == 'on' ? 'power_on' : 'power_off',
            result['success'] ? 'success' : 'failed'
          );
          
          // 결과 로그 중요한 것만 출력
          if (!result['success']) {
            print('프로젝터 ID: $id에 $command 명령 실행 실패');
          }
        } catch (e) {
          // 오류 로그만 유지
          print('프로젝터 명령 실행 중 오류: $e');
        }
      }
    } catch (e) {
      // 오류 로그만 유지
      print('프로젝터 스케줄 명령 실행 중 오류: $e');
    }
  }
} 