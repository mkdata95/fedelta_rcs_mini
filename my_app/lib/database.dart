  // PC 로그 가져오기
  Future<List<Map<String, dynamic>>> getPCLogs(int pcId, {int limit = 20}) async {
    final db = await database;
    return await db.query(
      'pc_logs',
      where: 'pc_id = ?',
      whereArgs: [pcId],
      orderBy: 'created_at DESC',
      limit: limit
    );
  }
  
  // PC 상태 변경 마지막 로그 가져오기
  Future<Map<String, dynamic>> getLastStatusLog(int pcId) async {
    final db = await database;
    final List<Map<String, dynamic>> results = await db.query(
      'pc_logs',
      where: 'pc_id = ? AND action IN (?, ?, ?, ?, ?)',
      whereArgs: [pcId, 'wake', 'shutdown', 'reboot', 'status_change', 'auto_status_change'],
      orderBy: 'created_at DESC',
      limit: 1
    );
    
    if (results.isNotEmpty) {
      return results.first;
    }
    
    // 로그가 없는 경우 null 반환
    return null;
  } 