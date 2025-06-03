import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 와치독 서비스 상태 및 기능 구현을 담당하는 서비스 클래스
class WatchdogService {
  // 네이티브 플랫폼과 통신할 메서드 채널
  static const MethodChannel _channel = MethodChannel('com.rcscontrol.watchdog/app_control');
  
  // 싱글톤 인스턴스
  static final WatchdogService _instance = WatchdogService._internal();
  
  // 상태 관리
  bool _isServiceRunning = false;
  Timer? _watchdogTimer;
  
  // 팩토리 생성자
  factory WatchdogService() {
    return _instance;
  }
  
  // 내부 생성자
  WatchdogService._internal();
  
  // 서비스 초기화
  Future<void> initialize() async {
    try {
      // 이전 상태 확인
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('watchdog_running') ?? true;
      
      // 활성화 상태라면 서비스 시작
      if (enabled) {
        await startService();
      }
      
      developer.log('와치독 서비스 초기화 완료', name: 'WatchdogService');
    } catch (e) {
      developer.log('와치독 서비스 초기화 실패: $e', name: 'WatchdogService');
    }
  }
  
  // 와치독 서비스 시작
  Future<bool> startService() async {
    if (_isServiceRunning) {
      developer.log('와치독 서비스가 이미 실행 중입니다', name: 'WatchdogService');
      return true;
    }
    
    try {
      // 네이티브 서비스 시작 요청
      final result = await _channel.invokeMethod('startWatchdogService');
      
      if (result == true) {
        _isServiceRunning = true;
        _startWatchdogTimer();
        
        // 상태 저장
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('watchdog_running', true);
        
        developer.log('와치독 서비스 시작 성공', name: 'WatchdogService');
        return true;
      } else {
        developer.log('와치독 서비스 시작 실패', name: 'WatchdogService');
        return false;
      }
    } catch (e) {
      developer.log('와치독 서비스 시작 오류: $e', name: 'WatchdogService');
      return false;
    }
  }
  
  // 와치독 서비스 중지
  Future<bool> stopService() async {
    if (!_isServiceRunning) {
      developer.log('와치독 서비스가 이미 중지되었습니다', name: 'WatchdogService');
      return true;
    }
    
    try {
      // 네이티브 서비스 중지 요청
      final result = await _channel.invokeMethod('stopWatchdogService');
      
      if (result == true) {
        _isServiceRunning = false;
        _stopWatchdogTimer();
        
        // 상태 저장
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('watchdog_running', false);
        
        developer.log('와치독 서비스 중지 성공', name: 'WatchdogService');
        return true;
      } else {
        developer.log('와치독 서비스 중지 실패', name: 'WatchdogService');
        return false;
      }
    } catch (e) {
      developer.log('와치독 서비스 중지 오류: $e', name: 'WatchdogService');
      
      // 네이티브 서비스 중지 시도가 실패해도 앱 내 상태는 중지로 설정
      _isServiceRunning = false;
      _stopWatchdogTimer();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('watchdog_running', false);
      
      return false;
    }
  }
  
  // 정기적으로 서비스 상태를 확인하는 타이머 시작
  void _startWatchdogTimer() {
    _stopWatchdogTimer(); // 기존 타이머가 있다면 중지
    
    // 30초마다 서비스 상태 확인
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _checkServiceStatus();
    });
    
    developer.log('와치독 모니터링 타이머 시작됨', name: 'WatchdogService');
  }
  
  // 타이머 중지
  void _stopWatchdogTimer() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    developer.log('와치독 모니터링 타이머 중지됨', name: 'WatchdogService');
  }
  
  // 서비스 상태 확인
  Future<void> _checkServiceStatus() async {
    try {
      // 네이티브 서비스 상태 확인
      final isRunning = await _channel.invokeMethod('isWatchdogServiceRunning');
      
      // 서비스 상태가 예상과 다르면 로그 기록
      if (isRunning != _isServiceRunning) {
        developer.log(
          '와치독 서비스 상태 불일치: Flutter($_isServiceRunning) / Native($isRunning)', 
          name: 'WatchdogService'
        );
        
        // 실행 중이어야 하는데 중지되었다면 재시작 시도
        if (_isServiceRunning && !isRunning) {
          developer.log('와치독 서비스 재시작 시도', name: 'WatchdogService');
          await _channel.invokeMethod('startWatchdogService');
        }
      }
    } catch (e) {
      developer.log('서비스 상태 확인 오류: $e', name: 'WatchdogService');
    }
  }
  
  // 메인 앱 시작
  Future<bool> startMainApp() async {
    try {
      final result = await _channel.invokeMethod('startMainApp');
      return result == true;
    } catch (e) {
      developer.log('메인 앱 시작 오류: $e', name: 'WatchdogService');
      return false;
    }
  }
  
  // 자동 시작 기능 설정
  Future<void> setAutoStartEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setAutoStartEnabled', {'enabled': enabled});
      
      // 설정 저장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_start_enabled', enabled);
      
      developer.log('자동 시작 설정 변경: $enabled', name: 'WatchdogService');
    } catch (e) {
      developer.log('자동 시작 설정 변경 오류: $e', name: 'WatchdogService');
    }
  }
  
  // 서비스 상태 확인
  Future<bool> isServiceRunning() async {
    try {
      final isRunning = await _channel.invokeMethod('isWatchdogServiceRunning');
      _isServiceRunning = isRunning == true;
      return _isServiceRunning;
    } catch (e) {
      developer.log('서비스 상태 확인 오류: $e', name: 'WatchdogService');
      return _isServiceRunning; // 확인 실패 시 현재 상태 반환
    }
  }
  
  // 메인 앱 실행 상태 확인
  Future<bool> isMainAppRunning() async {
    try {
      final isRunning = await _channel.invokeMethod('isMainAppRunning');
      return isRunning == true;
    } catch (e) {
      developer.log('메인 앱 상태 확인 오류: $e', name: 'WatchdogService');
      return false;
    }
  }
} 