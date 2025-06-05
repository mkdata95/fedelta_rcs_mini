/**
 * 전체 제어 JavaScript 모듈
 * dashboard.html에서 분리된 전체 제어 관련 함수들
 */

// 전체 제어 진행 상태 추적 변수
let isProcessing = false;
let currentProcessType = '';

// 전체 켜기 확인 모달 함수
function showBulkOnConfirm() {
  console.log('🟢 showBulkOnConfirm 함수 호출됨 - 바로 실행');
  
  // 진행 중인지 확인
  if (isProcessing) {
    console.log('⚠️ 이미 처리 중입니다:', currentProcessType);
    showNavbarStatus(`현재 ${currentProcessType} 처리 중입니다. 잠시만 기다려 주세요.`, 5000);
    return;
  }
  
  // 확인 없이 바로 실행
  try {
    console.log('✅ 확인 없이 바로 전체 켜기 실행');
    executeBulkControl('on');
  } catch (error) {
    console.error('❌ 전체 켜기 실행 중 오류:', error);
    // 오류도 상단바에 간단히 표시
    showNavbarStatus(`전체 켜기 오류: ${error.message}`, 10000);
  }
}

// 전체 끄기 확인 모달 함수
function showBulkOffConfirm() {
  console.log('🔴 showBulkOffConfirm 함수 호출됨 - 바로 실행');
  
  // 진행 중인지 확인
  if (isProcessing) {
    console.log('⚠️ 이미 처리 중입니다:', currentProcessType);
    showNavbarStatus(`현재 ${currentProcessType} 처리 중입니다. 잠시만 기다려 주세요.`, 5000);
    return;
  }
  
  // 확인 없이 바로 실행
  try {
    console.log('✅ 확인 없이 바로 전체 끄기 실행');
    executeBulkControl('off');
  } catch (error) {
    console.error('❌ 전체 끄기 실행 중 오류:', error);
    // 오류도 상단바에 간단히 표시
    showNavbarStatus(`전체 끄기 오류: ${error.message}`, 10000);
  }
}

// 전체 제어 실행 함수
async function executeBulkControl(action) {
  console.log(`🚀 executeBulkControl(${action}) 함수 시작`);
  
  // 진행 상태 설정
  isProcessing = true;
  currentProcessType = action === 'on' ? '전체 켜기' : '전체 끄기';
  
  // 시작 메시지 제거 - 바로 카운트다운으로 넘어감
  const actionText = action === 'on' ? '켜기' : '끄기';
  
  try {
    // 프로젝터와 PC 목록만 가져오기 (PDU 제외)
    console.log('📡 장치 목록 가져오기 시작...');
    
    const [projectors, pcs] = await Promise.all([
      fetchAllProjectors(),
      fetchAllPCs()
    ]);
    
    console.log('📊 가져온 장치 목록:', { 
      projectors: projectors.length, 
      pcs: pcs.length,
      projectorList: projectors,
      pcList: pcs
    });
    
    const totalDevices = projectors.length + pcs.length;
    
    if (totalDevices === 0) {
      console.warn('⚠️ 제어할 장치가 없습니다');
      showNavbarStatus('제어할 장치가 없습니다', 5000);
      return;
    }
    
    console.log(`🎯 총 ${totalDevices}개 장치 제어 시작`);
    
    // 켜기와 끄기에 따른 시퀀스 실행
    if (action === 'on') {
      console.log('🟢 켜기 시퀀스 시작');
      await executeStartupSequenceSimple(projectors, pcs);
    } else {
      console.log('🔴 끄기 시퀀스 시작');
      await executeShutdownSequenceSimple(projectors, pcs);
    }
    
    console.log('✅ executeBulkControl 완료');
    showNavbarStatus(`전체 ${actionText} 완료!`, 5000);
    
    // 완료 후 장치 목록 새로고침
    setTimeout(() => {
      loadDashboardProjectorList();
      loadDashboardPCList();
    }, 1000);
    
  } catch (error) {
    console.error('❌ 전체 제어 실행 중 오류:', error);
    showNavbarStatus(`전체 ${actionText} 오류: ${error.message}`, 10000);
  } finally {
    // 진행 상태 해제
    isProcessing = false;
    currentProcessType = '';
    console.log('🔓 진행 상태 해제됨');
  }
}

// 켜기 시퀀스: 프로젝터 먼저 → 2분 대기 → PC 켜기
async function executeStartupSequenceSimple(projectors, pcs) {
  try {
    console.log('🟢 1단계: 빔프로젝터 켜기 시작');
    
    // 1단계: 빔프로젝터 켜기 (2초 간격으로 순차 실행)
    if (projectors.length > 0) {
      for (let i = 0; i < projectors.length; i++) {
        const projector = projectors[i];
        try {
          await controlDevice({ ...projector, type: 'projector' }, 'on');
          console.log(`✅ 프로젝터 ${i + 1}/${projectors.length} 켜기 완료: ${projector.name}`);
          
          // 마지막이 아니면 2초 대기
          if (i < projectors.length - 1) {
            await new Promise(resolve => setTimeout(resolve, 2000));
          }
        } catch (error) {
          console.error(`❌ 프로젝터 제어 실패 (${projector.name}):`, error);
        }
      }
    }
    
    console.log('🟡 2단계: 빔프로젝터 예열 대기 시작 (2분)');
    
    // 2단계: 2분 대기 (프로젝터 예열 시간) - 상단바에만 표시
    await showSimpleCountdown(120, '빔프로젝터 예열 중', '전체 켜기 진행 처리중'); // 120초 = 2분
    
    console.log('🟢 3단계: PC 켜기 시작');
    
    // 3단계: PC 켜기
    if (pcs.length > 0) {
      // PC는 동시에 켜기
      const pcPromises = pcs.map(async (pc, index) => {
        try {
          await controlDevice({ ...pc, type: 'pc' }, 'on');
          console.log(`✅ PC ${index + 1}/${pcs.length} 켜기 완료: ${pc.name}`);
          return { success: true, device: pc };
        } catch (error) {
          console.error(`❌ PC 제어 실패 (${pc.name}):`, error);
          return { success: false, device: pc, error };
        }
      });
      
      await Promise.all(pcPromises);
    }
    
    console.log('🚀 켜기 시퀀스 완료');
    
  } catch (error) {
    console.error('❌ 켜기 시퀀스 실행 중 오류:', error);
    throw error;
  }
}

// 끄기 시퀀스: PC 먼저 → 2분 대기 → 프로젝터 끄기
async function executeShutdownSequenceSimple(projectors, pcs) {
  console.log('🔴 1단계: PC 끄기 시작');
  console.log('🔴 끄기할 PC 목록:', pcs);
  
  // 1단계: PC 끄기 - 오류가 발생해도 계속 진행
  if (pcs.length > 0) {
    console.log(`🔴 총 ${pcs.length}개 PC 끄기 시작`);
    
    // PC는 동시에 끄기
    const pcPromises = pcs.map(async (pc, index) => {
      try {
        console.log(`🔴 PC ${index + 1}/${pcs.length} 끄기 시도: ${pc.name} (ID: ${pc.id})`);
        await controlDevice({ ...pc, type: 'pc' }, 'off');
        console.log(`✅ PC ${index + 1}/${pcs.length} 끄기 완료: ${pc.name}`);
        return { success: true, device: pc };
      } catch (error) {
        console.error(`❌ PC 제어 실패 (${pc.name}):`, error);
        return { success: false, device: pc, error };
      }
    });
    
    const pcResults = await Promise.all(pcPromises);
    console.log('🔴 PC 끄기 결과:', pcResults);
    
    // 성공/실패 개수 확인
    const successCount = pcResults.filter(r => r.success).length;
    const failCount = pcResults.filter(r => !r.success).length;
    console.log(`🔴 PC 끄기 완료: 성공 ${successCount}개, 실패 ${failCount}개`);
    
    // PC 끄기 실패가 있어도 계속 진행
    if (failCount > 0) {
      console.warn(`⚠️ ${failCount}개 PC 끄기 실패했지만 시퀀스 계속 진행`);
    }
  } else {
    console.log('🔴 끄기할 PC가 없습니다');
  }
  
  console.log('🟡 2단계: PC 완전 종료 대기 시작 (2분)');
  
  // 2단계: 2분 대기 (PC 완전 종료 시간) - 상단바에만 표시
  try {
    await showSimpleCountdown(120, 'PC 완전 종료 대기 중', '전체 끄기 진행 처리중'); // 120초 = 2분
    console.log('🟡 2분 대기 완료');
  } catch (error) {
    console.error('❌ 카운트다운 오류:', error);
    // 카운트다운 오류가 발생해도 계속 진행
  }
  
  console.log('🔴 3단계: 빔프로젝터 끄기 시작');
  console.log('🔴 끄기할 프로젝터 목록:', projectors);
  
  // 3단계: 빔프로젝터 끄기 (2초 간격으로 순차 실행)
  if (projectors.length > 0) {
    console.log(`🔴 총 ${projectors.length}개 프로젝터 끄기 시작`);
    
    for (let i = 0; i < projectors.length; i++) {
      const projector = projectors[i];
      try {
        console.log(`🔴 프로젝터 ${i + 1}/${projectors.length} 끄기 시도: ${projector.name} (IP: ${projector.ip})`);
        await controlDevice({ ...projector, type: 'projector' }, 'off');
        console.log(`✅ 프로젝터 ${i + 1}/${projectors.length} 끄기 완료: ${projector.name}`);
        
        // 마지막이 아니면 2초 대기
        if (i < projectors.length - 1) {
          console.log('🔴 다음 프로젝터까지 2초 대기...');
          await new Promise(resolve => setTimeout(resolve, 2000));
        }
      } catch (error) {
        console.error(`❌ 프로젝터 제어 실패 (${projector.name}):`, error);
        // 프로젝터 제어 실패해도 다음 프로젝터 계속 진행
      }
    }
  } else {
    console.log('🔴 끄기할 프로젝터가 없습니다');
  }
  
  console.log('🔴 끄기 시퀀스 완료');
}

// 알림바 표시 함수를 완전히 비활성화 (빈 함수로 교체)
function showNotification(message, type = 'info', duration = 4000) {
  // 완전히 비활성화 - 아무것도 하지 않음
  console.log('알림 무시됨:', message);
}

// 알림바 숨기기 함수를 완전히 비활성화
function hideNotificationBar() {
  // 완전히 비활성화 - 아무것도 하지 않음
}

// showToast 함수를 완전히 비활성화 (빈 함수로 교체)
function showToast(title, message = '', type = 'info', duration = 4000) {
  // 완전히 비활성화 - 아무것도 하지 않음
  console.log('토스트 무시됨:', title, message);
}

// 전체 제어 모듈 초기화 함수
function initializeBulkControl() {
  // 전체 켜기/끄기 버튼 클릭 이벤트 확인을 위한 추가 로그
  console.log('🔍 전체 제어 버튼들 확인 중...');
  
  // 전체 켜기 버튼 확인
  const bulkOnCard = document.querySelector('div[onclick="showBulkOnConfirm()"]');
  if (bulkOnCard) {
    console.log('✅ 전체 켜기 버튼 찾음:', bulkOnCard);
    // 추가 클릭 이벤트 로그
    bulkOnCard.addEventListener('click', function() {
      console.log('🟢 전체 켜기 버튼 클릭 감지됨!');
    });
  } else {
    console.error('❌ 전체 켜기 버튼을 찾을 수 없음');
  }
  
  // 전체 끄기 버튼 확인
  const bulkOffCard = document.querySelector('div[onclick="showBulkOffConfirm()"]');
  if (bulkOffCard) {
    console.log('✅ 전체 끄기 버튼 찾음:', bulkOffCard);
    // 추가 클릭 이벤트 로그
    bulkOffCard.addEventListener('click', function() {
      console.log('🔴 전체 끄기 버튼 클릭 감지됨!');
    });
  } else {
    console.error('❌ 전체 끄기 버튼을 찾을 수 없음');
  }
  
  console.log('✅ 전체 제어 모듈 초기화 완료');
}

// 전역 스코프에 함수들 등록
window.showBulkOnConfirm = showBulkOnConfirm;
window.showBulkOffConfirm = showBulkOffConfirm;
window.executeBulkControl = executeBulkControl;
window.executeStartupSequenceSimple = executeStartupSequenceSimple;
window.executeShutdownSequenceSimple = executeShutdownSequenceSimple;
window.showNotification = showNotification;
window.hideNotificationBar = hideNotificationBar;
window.showToast = showToast;
window.initializeBulkControl = initializeBulkControl;

console.log('✅ bulk-control.js 로드 완료 - 전역 함수 등록됨'); 