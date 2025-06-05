/**
 * 시간 관리 JavaScript 모듈
 * dashboard.html에서 분리된 시간 관련 함수들
 */

// 시간 카드 직접 업데이트 함수 (먼저 정의)
function forceUpdateTimeCard() {
  const now = new Date();
  const hours = now.getHours();
  const minutes = String(now.getMinutes()).padStart(2, '0');
  const seconds = String(now.getSeconds()).padStart(2, '0');
  const period = hours < 12 ? '오전' : '오후';
  const displayHours = String(hours % 12 || 12).padStart(2, '0');
  
  // 모든 가능한 방법으로 시간 카드 찾기
  let timeCard = document.getElementById('time-card-display');
  
  if (!timeCard) {
    // querySelector로 다시 찾기
    timeCard = document.querySelector('#time-card-display');
  }
  
  if (!timeCard) {
    // 클래스명으로 찾기
    const allNumbers = document.querySelectorAll('.dashboard-card-number');
    for (let element of allNumbers) {
      if (element.id === 'time-card-display' || element.textContent.includes('로딩중')) {
        timeCard = element;
        break;
      }
    }
  }
  
  if (timeCard) {
    // 새로운 구조로 시간 표시
    const periodElement = timeCard.querySelector('.time-period');
    const digitsElement = timeCard.querySelector('.time-digits');
    
    if (periodElement && digitsElement) {
      periodElement.textContent = period;
      digitsElement.textContent = `${displayHours}:${minutes}:${seconds}`;
    } else {
      // 백업: 기존 방식으로 표시
      timeCard.innerHTML = `
        <span class="time-period">${period}</span>
        <span class="time-digits">${displayHours}:${minutes}:${seconds}</span>
      `;
    }
    
    // console.log('✅ 시간 카드 업데이트 성공:', period, `${displayHours}:${minutes}:${seconds}`);
    return true;
  } else {
    // console.error('❌ 시간 카드를 찾을 수 없습니다');
    return false;
  }
}

// 현재 시간 업데이트 (네비게이션 바용)
function updateCurrentTime() {
  const now = new Date();
  
  // 년.월.요일 부분
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  const weekdays = ['일', '월', '화', '수', '목', '금', '토'];
  const weekday = weekdays[now.getDay()];
  
  // 12시간 표시 시간 부분
  let hours = now.getHours();
  const minutes = String(now.getMinutes()).padStart(2, '0');
  const seconds = String(now.getSeconds()).padStart(2, '0');
  const ampm = hours >= 12 ? '오후' : '오전';
  
  // 12시간제로 변환
  hours = hours % 12;
  hours = hours ? hours : 12; // 0시는 12시로 표시
  hours = String(hours).padStart(2, '0');
  
  // 한글 부분(요일, 오전/오후)은 작은 폰트로 표시
  const timeString = `${year}.${month}.${day}.<span style="font-size: 0.9em;">${weekday}</span>&nbsp;&nbsp;<span style="font-size: 0.8em;">${ampm}</span> ${hours}:${minutes}:${seconds}`;
  
  const timeElement = document.getElementById('navbar-time');
  if (timeElement) {
    timeElement.innerHTML = timeString;
  }
}

// 대시보드 카드용 시간 표시
function updateTimeDisplay() {
  const now = new Date();
  const hours = now.getHours();
  const minutes = String(now.getMinutes()).padStart(2, '0');
  const seconds = String(now.getSeconds()).padStart(2, '0');
  
  // 오전/오후 구분
  const period = hours < 12 ? '오전' : '오후';
  // 12시간제 시간 계산
  const displayHours = String(hours % 12 || 12).padStart(2, '0');
  
  // 대시보드 시간 카드 업데이트
  const timeCardElement = document.getElementById('time-card-display');
  // console.log('시간 업데이트 시도:', period, `${displayHours}:${minutes}:${seconds}`);
  // console.log('시간 카드 요소:', timeCardElement);
  
  if (timeCardElement) {
    // 새로운 구조로 시간 표시
    const periodElement = timeCardElement.querySelector('.time-period');
    const digitsElement = timeCardElement.querySelector('.time-digits');
    
    if (periodElement && digitsElement) {
      periodElement.textContent = period;
      digitsElement.textContent = `${displayHours}:${minutes}:${seconds}`;
      // console.log('시간 카드 업데이트 완료:', period, `${displayHours}:${minutes}:${seconds}`);
    } else {
      // 백업: 기존 방식으로 표시
      timeCardElement.innerHTML = `
        <span class="time-period">${period}</span>
        <span class="time-digits">${displayHours}:${minutes}:${seconds}</span>
      `;
      // console.log('백업 방식으로 시간 카드 업데이트 완료');
    }
  } else {
    // console.error('time-card-display 요소를 찾을 수 없습니다');
    // 요소가 없으면 다른 방법으로 찾기 시도
    const allElements = document.querySelectorAll('[id*="time"]');
    // console.log('시간 관련 요소들:', allElements);
  }
}

// 간단한 카운트다운 (콘솔 + 상단바 표시)
async function showSimpleCountdown(seconds, title, progressInfo = '') {
  return new Promise((resolve) => {
    let remainingSeconds = seconds;
    
    // 상단바 타이머 요소 가져오기
    const navbarCountdown = document.getElementById('navbar-countdown');
    const countdownText = document.getElementById('countdown-text');
    
    // 타이머 표시 시작
    if (navbarCountdown && countdownText) {
      navbarCountdown.style.setProperty('display', 'flex', 'important');
    }
    
    const updateCountdown = () => {
      const minutes = Math.floor(remainingSeconds / 60);
      const secs = remainingSeconds % 60;
      const timeString = `${minutes}:${secs.toString().padStart(2, '0')}`;
      
      // 콘솔 로그
      console.log(`⏰ ${title} - 남은 시간: ${timeString}`);
      
      // 상단바에 표시 (타이머 + 진행 정보)
      if (countdownText) {
        countdownText.innerHTML = `
          <span style="margin-right: 8px; font-size: 1.2rem;">${title}</span>
          <span style="font-weight: bold; color: #ffc107; font-size: 1.2rem;">${timeString}</span>
          ${progressInfo ? `<span style="margin-left: 12px; color: #e9ecef; font-size: 1.2rem;">| ${progressInfo}</span>` : ''}
        `;
      }
      
      remainingSeconds--;
      
      if (remainingSeconds < 0) {
        console.log(`✅ ${title} 완료!`);
        
        // 타이머 숨기기
        if (navbarCountdown) {
          navbarCountdown.style.setProperty('display', 'none', 'important');
        }
        
        resolve();
      } else {
        setTimeout(updateCountdown, 1000);
      }
    };
    
    updateCountdown();
  });
}

// 상단바에만 상태 표시하는 함수 (모든 알림 대체)
function showNavbarStatus(message, duration = 0) {
  const navbarCountdown = document.getElementById('navbar-countdown');
  const countdownText = document.getElementById('countdown-text');
  
  if (navbarCountdown && countdownText) {
    // 상단바 표시
    navbarCountdown.style.setProperty('display', 'flex', 'important');
    countdownText.innerHTML = `<span style="color: #ffc107; font-weight: bold; font-size: 1.2rem;">${message}</span>`;
    
    // 자동 숨김 - duration이 0이면 숨기지 않음 (기본값 변경)
    if (duration > 0) {
      setTimeout(() => {
        navbarCountdown.style.setProperty('display', 'none', 'important');
      }, duration);
    }
  }
}

// 시간 관리 모듈 초기화 함수
function initializeTimeManager() {
  // 현재 시간 표시
  updateCurrentTime();
  updateTimeDisplay();
  
  // 시간 카드 즉시 강제 업데이트
  forceUpdateTimeCard();
  
  // 시간 카드 즉시 업데이트
  setTimeout(function() {
    updateTimeDisplay();
    // console.log('시간 카드 초기화 완료');
  }, 100);
  
  // 1초마다 시간 갱신
  setInterval(updateCurrentTime, 1000);
  setInterval(updateTimeDisplay, 1000);
  setInterval(forceUpdateTimeCard, 1000); // 강제 업데이트도 1초마다 실행
  
  console.log('✅ 시간 관리 모듈 초기화 완료');
}

// 전역 스코프에 함수들 등록
window.forceUpdateTimeCard = forceUpdateTimeCard;
window.updateCurrentTime = updateCurrentTime;
window.updateTimeDisplay = updateTimeDisplay;
window.showSimpleCountdown = showSimpleCountdown;
window.showNavbarStatus = showNavbarStatus;
window.initializeTimeManager = initializeTimeManager;

console.log('✅ time-manager.js 로드 완료 - 전역 함수 등록됨'); 