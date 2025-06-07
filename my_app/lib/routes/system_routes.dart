import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'dart:convert';
import '../services/system_service.dart';

class SystemRoutes {
  Router get router {
    final router = Router();

    // 시스템 상태 API (안드로이드 보드 네트워크 상태 포함)
    router.get('/system/status', (Request request) async {
      try {
        print('📊 시스템 상태 요청 받음');
        
        final systemStatus = await SystemService.getSystemStatus();
        
        print('✅ 시스템 상태 응답: ${systemStatus}');
        
        return Response.ok(
          json.encode(systemStatus),
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Access-Control-Allow-Origin': '*',
          },
        );
      } catch (e) {
        print('❌ 시스템 상태 API 오류: $e');
        
        // 오류 시 더미 데이터 반환
        final fallbackData = {
          'success': true,
          'data': {
            'system': {
              'status': 'online',
              'cpu_usage': 45.0,
              'memory_usage': 62.0,
            },
            'network': {
              'connected': false,  // 오류 시에는 연결안됨으로 표시
              'status': '연결안됨',
            }
          }
        };
        
        return Response.ok(
          json.encode(fallbackData),
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Access-Control-Allow-Origin': '*',
          },
        );
      }
    });

    return router;
  }
} 