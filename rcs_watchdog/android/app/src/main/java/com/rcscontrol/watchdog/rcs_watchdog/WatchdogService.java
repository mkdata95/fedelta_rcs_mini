package com.rcscontrol.watchdog.rcs_watchdog;

import android.app.ActivityManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.util.Log;
import androidx.core.app.NotificationCompat;

import java.util.List;

import android.content.SharedPreferences;

/**
 * 단순화된 와치독 서비스 - RCS컨트롤 앱 자동 실행 기능 추가
 */
public class WatchdogService extends Service {
    private static final String TAG = "WatchdogService";
    private static final int NOTIFICATION_ID = 1;
    private static final String MAIN_APP_PACKAGE = "com.example.my_app"; // RCS 컨트롤 앱 패키지명
    private static final long CHECK_INTERVAL = 30 * 1000; // 30초마다 확인
    
    private Handler handler;
    private Runnable checkRunnable;
    
    @Override
    public void onCreate() {
        super.onCreate();
        Log.i(TAG, "와치독 서비스 생성됨");
        
        // 핸들러 초기화
        handler = new Handler();
        
        // 최소한의 포그라운드 서비스 시작
        try {
            Notification notification = createNotification();
            startForeground(NOTIFICATION_ID, notification);
            Log.i(TAG, "포그라운드 서비스로 시작됨");
            
            // 주기적 확인 작업 시작
            startCheckTask();
        } catch (Exception e) {
            Log.e(TAG, "포그라운드 서비스 시작 중 오류 발생: " + e.getMessage(), e);
        }
    }
    
    /**
     * 주기적 앱 확인 작업 시작
     */
    private void startCheckTask() {
        try {
            // 이미 실행 중인 작업이 있으면 제거
            if (checkRunnable != null) {
                handler.removeCallbacks(checkRunnable);
                checkRunnable = null;
            }
            
            // 자동 시작 설정 확인
            SharedPreferences prefs = getSharedPreferences("watchdog_prefs", MODE_PRIVATE);
            boolean autoStartEnabled = prefs.getBoolean("auto_start_enabled", true);
            
            // 자동 시작이 비활성화된 경우 타이머를 시작하지 않음
            if (!autoStartEnabled) {
                Log.i(TAG, "자동 시작이 비활성화되어 있어 모니터링 타이머를 시작하지 않음");
                return;
            }
            
            // 새 작업 정의
            checkRunnable = new Runnable() {
                @Override
                public void run() {
                    try {
                        // 설정 다시 확인
                        SharedPreferences prefs = getSharedPreferences("watchdog_prefs", MODE_PRIVATE);
                        boolean stillEnabled = prefs.getBoolean("auto_start_enabled", true);
                        
                        if (stillEnabled) {
                            // RCS컨트롤 앱 실행 상태 확인
                            checkAndStartMainApp();
                            
                            // 다음 실행 예약
                            if (handler != null && checkRunnable != null) {
                                handler.postDelayed(checkRunnable, CHECK_INTERVAL);
                            }
                        }
                    } catch (Exception e) {
                        Log.e(TAG, "체크 작업 실행 중 오류: " + e.getMessage(), e);
                        
                        // 오류가 발생해도 다음 확인 계속 진행
                        if (handler != null && checkRunnable != null) {
                            handler.postDelayed(checkRunnable, CHECK_INTERVAL);
                        }
                    }
                }
            };
            
            // 작업 즉시 시작
            if (handler != null && checkRunnable != null) {
                handler.post(checkRunnable);
                Log.i(TAG, "RCS컨트롤 앱 주기적 확인 시작됨 (간격: " + (CHECK_INTERVAL / 1000) + "초)");
            }
        } catch (Exception e) {
            Log.e(TAG, "타이머 시작 중 오류: " + e.getMessage(), e);
        }
    }
    
    /**
     * RCS컨트롤 앱 실행 상태 확인 및 필요시 시작
     */
    private void checkAndStartMainApp() {
        try {
            // 자동 시작 설정 확인
            SharedPreferences prefs = getSharedPreferences("watchdog_prefs", MODE_PRIVATE);
            boolean autoStartEnabled = prefs.getBoolean("auto_start_enabled", true);
            
            boolean isRunning = isMainAppRunning();
            Log.i(TAG, "RCS컨트롤 앱 상태 확인: " + (isRunning ? "실행 중" : "실행되지 않음"));
            
            // 앱이 실행 중이 아니고 자동 시작이 활성화되어 있으면 시작
            if (!isRunning && autoStartEnabled) {
                startMainApp();
            } else if (!isRunning) {
                Log.i(TAG, "자동 시작 기능이 비활성화되어 앱 시작하지 않음");
            }
        } catch (Exception e) {
            Log.e(TAG, "앱 상태 확인 중 오류: " + e.getMessage(), e);
        }
    }
    
    /**
     * RCS컨트롤 앱이 실행 중인지 확인
     */
    private boolean isMainAppRunning() {
        try {
            ActivityManager am = (ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
            if (am == null) return false;
            
            List<ActivityManager.RunningAppProcessInfo> processes = am.getRunningAppProcesses();
            if (processes != null) {
                for (ActivityManager.RunningAppProcessInfo process : processes) {
                    if (MAIN_APP_PACKAGE.equals(process.processName)) {
                        return true;
                    }
                }
            }
            
            return false;
        } catch (Exception e) {
            Log.e(TAG, "앱 실행 상태 확인 중 오류: " + e.getMessage(), e);
            return false;
        }
    }
    
    /**
     * RCS컨트롤 앱 시작
     */
    private void startMainApp() {
        try {
            Log.i(TAG, "RCS컨트롤 앱 시작 시도...");
            
            // 앱이 설치되어 있는지 확인
            PackageManager pm = getPackageManager();
            Intent launchIntent = pm.getLaunchIntentForPackage(MAIN_APP_PACKAGE);
            
            if (launchIntent != null) {
                // 새 태스크로 시작
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(launchIntent);
                Log.i(TAG, "RCS컨트롤 앱 시작 성공");
            } else {
                Log.e(TAG, "RCS컨트롤 앱이 설치되어 있지 않음");
            }
        } catch (Exception e) {
            Log.e(TAG, "RCS컨트롤 앱 시작 실패: " + e.getMessage(), e);
        }
    }
    
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.i(TAG, "와치독 서비스 시작 명령 수신 [startId: " + startId + "]");
        
        if (flags == START_FLAG_REDELIVERY) {
            Log.i(TAG, "서비스가 시스템에 의해 재시작됨");
        }
        
        // 자동 시작 설정 변경 명령 처리
        if (intent != null && "UPDATE_AUTO_START".equals(intent.getAction())) {
            boolean enabled = intent.getBooleanExtra("auto_start_enabled", true);
            updateAutoStartSetting(enabled);
        }
        
        // 서비스가 종료되면 재시작
        return START_STICKY;
    }
    
    /**
     * 자동 시작 설정 업데이트
     */
    private void updateAutoStartSetting(boolean enabled) {
        try {
            // 설정 저장
            SharedPreferences prefs = getSharedPreferences("watchdog_prefs", MODE_PRIVATE);
            prefs.edit().putBoolean("auto_start_enabled", enabled).apply();
            
            Log.i(TAG, "자동 시작 설정 업데이트됨: " + (enabled ? "활성화" : "비활성화"));
            
            // 비활성화 상태에서는 타이머 중지
            if (!enabled) {
                if (handler != null && checkRunnable != null) {
                    handler.removeCallbacks(checkRunnable);
                    checkRunnable = null;
                    Log.i(TAG, "앱 모니터링 타이머 중지됨");
                }
            } else {
                // 활성화 상태에서는 타이머 시작
                startCheckTask();
            }
        } catch (Exception e) {
            Log.e(TAG, "자동 시작 설정 업데이트 중 오류: " + e.getMessage(), e);
        }
    }
    
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
    
    @Override
    public void onDestroy() {
        Log.i(TAG, "와치독 서비스 종료됨");
        
        // 실행 중인 작업 제거
        try {
            if (handler != null && checkRunnable != null) {
                handler.removeCallbacks(checkRunnable);
                checkRunnable = null;
            }
            handler = null;
        } catch (Exception e) {
            Log.e(TAG, "서비스 종료 중 오류: " + e.getMessage(), e);
        }
        
        super.onDestroy();
    }
    
    /**
     * 포그라운드 서비스용 알림 생성
     */
    private Notification createNotification() {
        String channelId = "watchdog_channel";
        
        // 안드로이드 8.0 이상에서는 채널 필요
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    channelId,
                    "와치독 서비스",
                    NotificationManager.IMPORTANCE_LOW);
            
            NotificationManager notificationManager = 
                    (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            notificationManager.createNotificationChannel(channel);
        }
        
        // 알림 클릭 시 메인 액티비티로 이동하는 인텐트
        Intent notificationIntent = new Intent(this, MainActivity.class);
        PendingIntent pendingIntent;
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            pendingIntent = PendingIntent.getActivity(this, 0, notificationIntent, 
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        } else {
            pendingIntent = PendingIntent.getActivity(this, 0, notificationIntent, 
                    PendingIntent.FLAG_UPDATE_CURRENT);
        }
        
        // 매우 간단한 알림 생성
        return new NotificationCompat.Builder(this, channelId)
                .setContentTitle("RCS 와치독")
                .setContentText("RCS컨트롤 앱 모니터링 중")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setContentIntent(pendingIntent)
                .build();
    }
} 