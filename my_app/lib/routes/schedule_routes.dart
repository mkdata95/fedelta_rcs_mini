import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../services/schedule_service.dart';

class ScheduleRoutes {
  final Router _router = Router();
  final ScheduleService _service = ScheduleService();

  Router get router => _router;

  ScheduleRoutes() {
    _router.get('/get/<type>', _getSchedule);
    _router.post('/set', _setSchedule);
    _router.get('/logs', _getLogs);
  }

  Future<Response> _getSchedule(Request request, String type) async {
    final result = await _service.getSchedule(type);
    return Response.ok(
      result,
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _setSchedule(Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      
      if (!data.containsKey('device_type') || 
          !data.containsKey('power_on_time') || 
          !data.containsKey('power_off_time') ||
          !data.containsKey('days')) {
        return Response(400, 
          body: '{"success": false, "error": "필수 파라미터가 누락되었습니다. device_type, power_on_time, power_off_time, days가 필요합니다."}',
          headers: {'content-type': 'application/json'},
        );
      }

      final result = await _service.setSchedule(
        data['device_type'],
        data['power_on_time'],
        data['power_off_time'],
        data['days'],
      );

      return Response.ok(
        result,
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response(500,
        body: '{"success": false, "error": "$e"}',
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> _getLogs(Request request) async {
    final result = await _service.getLogs();
    return Response.ok(
      result,
      headers: {'content-type': 'application/json'},
    );
  }
} 