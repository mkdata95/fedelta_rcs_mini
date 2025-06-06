import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'dart:convert';
import '../services/system_service.dart';

class SystemRoutes {
  Router get router {
    final router = Router();

    // 시스템 상태 정보 API
    router.get('/system/status', _getSystemStatus);

    return router;
  }

  /// 시스템 상태 정보 가져오기
  Future<Response> _getSystemStatus(Request request) async {
    try {
      print('📊 GET /api/system/status 요청 받음');
      
      // SystemService에서 실제 시스템 정보 가져오기
      final systemInfo = await SystemService.getSystemInfo();
      
      final response = {
        'success': true,
        'data': {
          'system': {
            'status': systemInfo['status'],
            'cpu_usage': systemInfo['cpu_usage'],
            'memory_usage': systemInfo['memory_usage'],
            'timestamp': systemInfo['timestamp'],
          },
          // 네트워크 정보는 여전히 더미 데이터로 유지
          'network': {
            'status': 'online',
            'speed': '1Gbps',
            'ping': '2ms',
            'timestamp': DateTime.now().toIso8601String(),
          }
        },
        'message': '시스템 정보 조회 성공'
      };
      
      print('✅ 시스템 정보 응답: CPU ${systemInfo['cpu_usage']}%, 메모리 ${systemInfo['memory_usage']}%');
      
      return Response.ok(
        json.encode(response),
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
        },
      );
      
    } catch (e) {
      print('❌ 시스템 상태 조회 실패: $e');
      
      final errorResponse = {
        'success': false,
        'error': e.toString(),
        'message': '시스템 정보 조회 실패'
      };
      
      return Response.internalServerError(
        body: json.encode(errorResponse),
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      );
    }
  }
} 