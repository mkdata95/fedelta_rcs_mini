package com.rcscontrol.watchdog.rcs_watchdog;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

/**
 * 부팅 완료 리시버 - 지연 시간 추가
 */
public class BootCompletedReceiver extends BroadcastReceiver {
    private static final String TAG = "BootReceiver";
    private static final int BOOT_DELAY = 30 * 1000; // 부팅 후 30초 지연

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        Log.i(TAG, "부팅 리시버 호출됨: " + action);
        
        // 부팅 완료 시 서비스 시작
        if (Intent.ACTION_BOOT_COMPLETED.equals(action) ||
            "android.intent.action.QUICKBOOT_POWERON".equals(action) ||
            Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)) {
            
            try {
                Log.i(TAG, "부팅 감지됨 - " + (BOOT_DELAY / 1000) + "초 후 와치독 서비스 시작 예정");
                
                // 지연 후 서비스 시작 (시스템이 안정화될 시간 확보)
                new Handler(Looper.getMainLooper()).postDelayed(() -> {
                    try {
                        // 서비스 시작
                        Intent serviceIntent = new Intent(context, WatchdogService.class);
                        
                        // Android O 이상에서는 포그라운드 서비스 시작 필요
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            context.startForegroundService(serviceIntent);
                        } else {
                            context.startService(serviceIntent);
                        }
                        
                        Log.i(TAG, "부팅 후 지연 시간 경과, 서비스 시작 성공");
                    } catch (Exception e) {
                        Log.e(TAG, "지연 후 서비스 시작 실패: " + e.getMessage(), e);
                    }
                }, BOOT_DELAY);
                
                Log.i(TAG, "부팅 후 서비스 시작 타이머 설정 완료");
            } catch (Exception e) {
                Log.e(TAG, "부팅 후 서비스 시작 예약 실패: " + e.getMessage(), e);
            }
        }
    }
} 