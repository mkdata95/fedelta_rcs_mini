import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// PJLink 프로토콜을 사용하여 프로젝터를 제어하는 클라이언트
class PJLinkClient {
  /// PJLink 기본 포트
  static const int DEFAULT_PORT = 4352;
  
  /// 소켓 통신 타임아웃 (밀리초)
  static const int SOCKET_TIMEOUT = 5000;
  
  /// PJLink 명령어
  static const String CMD_POWER_ON = "POWR 1";
  static const String CMD_POWER_OFF = "POWR 0";
  static const String CMD_POWER_STATUS = "POWR ?";
  static const String CMD_INPUT_STATUS = "INPT ?";
  static const String CMD_ERROR_STATUS = "ERST ?";
  static const String CMD_LAMP_STATUS = "LAMP ?";
  static const String CMD_NAME = "NAME ?";
  static const String CMD_INFO = "INFO ?";
  
  /// PJLink 응답 코드
  static const String RESP_OK = "OK";
  static const String RESP_ERR_UNDEFINED = "ERR1";
  static const String RESP_ERR_PARAMETER = "ERR2";
  static const String RESP_ERR_UNAVAILABLE = "ERR3";
  static const String RESP_ERR_PROJECTOR = "ERR4";
  
  /// PJLink 전원 상태 응답
  static const String POWER_OFF = "0";
  static const String POWER_ON = "1";
  static const String POWER_COOLING = "2";
  static const String POWER_WARMING = "3";
  static const String POWER_STATUS_ERROR = "ERR";

  /// 프로젝터 IP 주소
  final String ip;
  
  /// PJLink 포트 (기본값: 4352)
  final int port;
  
  /// 인증에 사용될 사용자 이름
  final String? username;
  
  /// 인증에 사용될 비밀번호
  final String? password;
  
  /// 디버그 모드 활성화 여부
  final bool debug;

  /// PJLink 클라이언트 생성자
  PJLinkClient({
    required this.ip, 
    this.port = DEFAULT_PORT, 
    this.username, 
    this.password,
    this.debug = false
  });

  /// PJLink 명령 실행
  Future<String> executeCommand(String command) async {
    Socket? socket;
    
    try {
      if (debug) {
        print('PJLink: 연결 중... $ip:$port');
      }
      
      socket = await Socket.connect(ip, port, timeout: Duration(milliseconds: SOCKET_TIMEOUT));
      
      Completer<String> completer = Completer<String>();
      List<int> responseData = [];
      bool commandSent = false;
      
      socket.listen(
        (List<int> data) {
          responseData.addAll(data);
          String response = utf8.decode(responseData);
          
          if (debug) {
            print('PJLink 응답: $response');
          }
          
          if (!completer.isCompleted) {
            if (response.startsWith('PJLINK ') && !commandSent) {
              // 인증 응답 처리
              String authPrefix = _handleAuthentication(response);
              String fullCommand = '$authPrefix%1$command\r';
              commandSent = true;
              
              if (debug) {
                print('PJLink 명령 전송: $fullCommand');
              }
              
              socket?.write(fullCommand);
            } else if (commandSent && response.contains('\r')) {
              // 응답 데이터 처리
              completer.complete(response.trim());
            }
          }
        },
        onError: (error) {
          if (debug) {
            print('PJLink 오류: $error');
          }
          if (!completer.isCompleted) {
            completer.completeError('통신 오류: $error');
          }
        },
        onDone: () {
          if (debug) {
            print('PJLink 연결 종료');
          }
          if (!completer.isCompleted) {
            if (responseData.isEmpty) {
              completer.completeError('응답 없음');
            } else {
              completer.complete(utf8.decode(responseData).trim());
            }
          }
        },
      );
      
      // 타임아웃 설정
      Timer(Duration(milliseconds: SOCKET_TIMEOUT), () {
        if (!completer.isCompleted) {
          completer.completeError('타임아웃');
          socket?.destroy();
        }
      });
      
      // 응답 대기
      final response = await completer.future;
      socket.destroy();
      return _parseResponse(response);
      
    } catch (e) {
      if (debug) {
        print('PJLink 예외: $e');
      }
      socket?.destroy();
      return 'ERR:$e';
    }
  }
  
  /// 인증 처리
  String _handleAuthentication(String challenge) {
    if (!challenge.startsWith('PJLINK ')) {
      return '';
    }
    
    if (challenge.startsWith('PJLINK 0')) {
      // 인증 필요 없음
      return '';
    }
    
    if (challenge.startsWith('PJLINK 1')) {
      // 인증 필요
      if (password == null || password!.isEmpty) {
        if (debug) {
          print('PJLink 인증 필요하지만 비밀번호 없음');
        }
        return '';
      }
      
      // 랜덤 시드 추출
      String seed = challenge.substring(9).trim();
      if (debug) {
        print('PJLink 인증 시드: $seed');
      }
      
      // 인증 토큰 생성 (MD5)
      String token = md5.convert(utf8.encode(seed + password!)).toString();
      if (debug) {
        print('PJLink 인증 토큰: $token');
      }
      
      return token;
    }
    
    return '';
  }
  
  /// 응답 파싱
  String _parseResponse(String response) {
    if (debug) {
      print('PJLink 원본 응답: $response');
    }
    
    // 인증 헤더 제거
    if (response.startsWith("PJLINK ")) {
      int endOfHeader = response.indexOf("\r");
      if (endOfHeader > 0) {
        response = response.substring(endOfHeader + 1);
      }
    }
    
    if (debug) {
      print('PJLink 헤더 제거 후 응답: $response');
    }

    if (response.contains("POWR=")) {
      // POWR 명령에 대한 응답 파싱
      final match = RegExp(r'%1POWR=([0123]|ERR[1-4])').firstMatch(response);
      if (match != null && match.groupCount >= 1) {
        return match.group(1)!;
      }
    } else if (response.startsWith('%1')) {
      // 일반 응답
      int equalsIndex = response.indexOf('=');
      if (equalsIndex > 0) {
        return response.substring(equalsIndex + 1);
      }
    }
    
    // OK 응답 처리
    if (response.contains("OK")) {
      return RESP_OK;
    }
    
    return response;
  }
  
  /// 프로젝터 전원 켜기
  Future<bool> powerOn() async {
    try {
      String response = await executeCommand(CMD_POWER_ON);
      return response == RESP_OK;
    } catch (e) {
      if (debug) {
        print('전원 켜기 실패: $e');
      }
      return false;
    }
  }
  
  /// 프로젝터 전원 끄기
  Future<bool> powerOff() async {
    try {
      String response = await executeCommand(CMD_POWER_OFF);
      return response == RESP_OK;
    } catch (e) {
      if (debug) {
        print('전원 끄기 실패: $e');
      }
      return false;
    }
  }
  
  /// 프로젝터 전원 상태 확인
  Future<String> getPowerStatus() async {
    try {
      String response = await executeCommand(CMD_POWER_STATUS);
      return response;
    } catch (e) {
      if (debug) {
        print('전원 상태 확인 실패: $e');
      }
      return POWER_STATUS_ERROR;
    }
  }
  
  /// 프로젝터 정보 확인
  Future<String> getInfo() async {
    try {
      String response = await executeCommand(CMD_INFO);
      return response;
    } catch (e) {
      if (debug) {
        print('정보 확인 실패: $e');
      }
      return "ERR";
    }
  }
  
  /// 프로젝터 이름 확인
  Future<String> getName() async {
    try {
      String response = await executeCommand(CMD_NAME);
      return response;
    } catch (e) {
      if (debug) {
        print('이름 확인 실패: $e');
      }
      return "ERR";
    }
  }
} 