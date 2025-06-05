/**
 * 메인 대시보드 JavaScript 모듈
 * dashboard.html에서 분리된 초기화 및 공통 함수들
 */

// 웹뷰 플랫폼 감지 및 스타일 적용 함수
function detectPlatformAndApplyStyles() {
  const userAgent = navigator.userAgent || navigator.vendor || window.opera;
  const body = document.body;
  
  // Android WebView 감지
  if (/android/i.test(userAgent) && /wv\)/i.test(userAgent)) {
    body.classList.add('webview');
    body.setAttribute('data-platform', 'android');
    // console.log('Android WebView 감지됨 - 웹뷰 스타일 적용');
  }
  // iOS WebView 감지 (WKWebView)
  else if (/iPhone|iPad|iPod/i.test(userAgent) && window.webkit && window.webkit.messageHandlers) {
    body.classList.add('webview');
    body.setAttribute('data-platform', 'ios');
    // console.log('iOS WebView 감지됨 - 웹뷰 스타일 적용');
  }
  // 일반적인 WebView 감지 (추가 체크)
  else if (window.AndroidChannel || window.webkit) {
    body.classList.add('webview');
    body.setAttribute('data-platform', 'webview');
    // console.log('WebView 환경 감지됨 - 웹뷰 스타일 적용');
  }
  // 데스크톱 브라우저
  else {
    body.setAttribute('data-platform', 'browser');
    // console.log('일반 브라우저 환경');
  }
}

// 웹뷰 상단 헤더 숨기기 함수
function hideWebViewHeader() {
  // Android WebView
  if (window.AndroidChannel) {
    try {
      window.AndroidChannel.postMessage('hideHeader:true');
      window.AndroidChannel.postMessage('hideStatusBar:true');
      window.AndroidChannel.postMessage('fullscreen:true');
      window.AndroidChannel.postMessage('hideSystemUI:true');
    } catch (e) {
      console.error('Android WebView 통신 오류:', e);
    }
  }
  
  // iOS WKWebView
  try {
    window.webkit.messageHandlers.hideHeader.postMessage(true);
    window.webkit.messageHandlers.hideStatusBar.postMessage(true);
    window.webkit.messageHandlers.fullscreen.postMessage(true);
    window.webkit.messageHandlers.hideSystemUI.postMessage(true);
  } catch (e) {
    // iOS 핸들러가 없는 경우 무시
  }
  
  // 상단 메시지 요소 직접 숨기기
  const possibleSelectors = [
    '.webview-message', 
    '.webview-title', 
    '.webview-status',
    '.server-status',
    '.status-bar',
    '.app-title-bar',
    '.app-header-original',
    'div[class*="webview-"]',
    'div[id*="webview-"]',
    'div[id*="header"]',
    'div[class*="header"]',
    'div[id*="status"]',
    'div[class*="status"]',
    '.system-message',
    '.system-status',
    '.offline-remote-header',
    '#offline-remote-header',
    '.offline-remote-status',
    '#offline-remote-status',
    '.remote-control-header',
    '#remote-control-header',
    '#app-header',
    '.app-header',
    '#status-bar',
    '.status-bar',
    '#title-bar',
    '.title-bar'
  ];
  
  // 모든 선택자를 대상으로 요소를 찾아 숨김 처리
  possibleSelectors.forEach(selector => {
    const elements = document.querySelectorAll(selector);
    elements.forEach(element => {
      // 요소의 스타일 속성 변경
      element.style.display = 'none';
      element.style.height = '0';
      element.style.visibility = 'hidden';
      element.style.opacity = '0';
      element.style.position = 'absolute';
      element.style.zIndex = '-9999';
      
      // 가능하면 DOM에서 제거
      if(element.parentNode) {
        element.parentNode.removeChild(element);
      }
    });
  });
}

// 네비게이션 설정 함수
function setupNavigation() {
  // 모든 네비게이션 링크에 이벤트 리스너 추가
  document.querySelectorAll('a[onclick*="navigateToPage"]').forEach(link => {
    link.addEventListener('click', function(e) {
      e.preventDefault();
      const page = this.getAttribute('onclick').match(/navigateToPage\('(.+?)'\)/)[1];
      navigateToPage(page);
    });
  });
}

// 페이지 이동 함수
function navigateToPage(page) {
  window.location.href = page;
}

// 메뉴 활성화 함수
function activateMenu(pageName) {
  // 모든 메뉴 링크 비활성화
  document.querySelectorAll('.nav-sidebar .nav-link').forEach(link => {
    link.classList.remove('active');
  });
  
  // 현재 페이지에 맞는 메뉴 활성화
  let activeLink = null;
  
  switch(pageName) {
    case 'index.html':
    case '':
      activeLink = document.querySelector('#dashboard-link');
      break;
    case 'dashboard.html':
      activeLink = document.querySelector('#dashboard-link');
      break;
    case 'projector.html':
      activeLink = document.querySelector('#projector-link');
      break;
    case 'pc.html':
      activeLink = document.querySelector('#pc-link');
      break;
    case 'pdu.html':
      activeLink = document.querySelector('#pdu-link');
      break;
    default:
      // 기본값으로 대시보드 활성화
      activeLink = document.querySelector('#dashboard-link');
  }
  
  if (activeLink) {
    activeLink.classList.add('active');
  }
}

// FontAwesome 아이콘 확인 및 폴백 처리
function checkIcon(iconClass, fallbackClass) {
  var icons = document.querySelectorAll(iconClass);
  icons.forEach(function(icon) {
    // 아이콘이 제대로 로드되지 않았는지 확인
    if (icon.offsetWidth === 0 || getComputedStyle(icon).display === 'none') {
      // 부모 요소에서 폴백 SVG 찾기
      var parent = icon.parentElement;
      if (parent) {
        var fallback = parent.querySelector(fallbackClass);
        if (fallback) {
          // 아이콘은 숨기고 SVG 표시
          icon.style.display = 'none';
          fallback.style.display = 'block';
        }
      }
    }
  });
}

// 실제 프로젝터 데이터 로드 함수 (API 연결용)
function loadRealProjectorData() {
  return fetch('/api/projectors')
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      return response.json();
    })
    .then(data => {
      console.log('프로젝터 API 응답:', data);
      const tbody = document.getElementById('dashboard-projector-list');
      
      if (!tbody) {
        console.error('dashboard-projector-list 테이블을 찾을 수 없습니다');
        return data;
      }
      
      // API 응답 구조 처리 - data가 배열이거나 객체일 수 있음
      let projectorList = [];
      if (Array.isArray(data)) {
        projectorList = data;
      } else if (data && Array.isArray(data.projectors)) {
        projectorList = data.projectors;
      } else if (data && Array.isArray(data.data)) {
        projectorList = data.data;
      } else if (data && data.success && Array.isArray(data.data)) {
        projectorList = data.data;
      }
      
      console.log('처리된 프로젝터 목록:', projectorList);
      
      if (projectorList && projectorList.length > 0) {
        tbody.innerHTML = projectorList.map((projector, index) => `
          <tr>
            <td class="text-center">${index + 1}</td>
            <td class="text-center">${projector.name || projector.device_name || '이름 없음'}</td>
            <td class="text-center">${projector.ip || projector.ip_address || 'N/A'}</td>
            <td class="text-center">${projector.model || projector.device_type || projector.type || '모델 정보 없음'}</td>
            <td class="text-center">
              <span class="badge ${(projector.networkStatus === 'online' || projector.network_status === 'online' || projector.status === 'online') ? 'badge-online' : 'badge-offline'}">
                ${(projector.networkStatus === 'online' || projector.network_status === 'online' || projector.status === 'online') ? '온라인' : '오프라인'}
              </span>
            </td>
            <td class="text-center">
              <span class="badge ${(projector.powerStatus === 'on' || projector.power_status === 'on' || projector.power === 'on') ? 'badge-online' : 'badge-offline'}">
                ${(projector.powerStatus === 'on' || projector.power_status === 'on' || projector.power === 'on') ? '켜짐' : '꺼짐'}
              </span>
            </td>
          </tr>
        `).join('');
        updateDashboardCard('projector', projectorList.length);
        console.log(`프로젝터 ${projectorList.length}개 표시 완료`);
      } else {
        tbody.innerHTML = '<tr><td colspan="6" class="text-center text-muted">등록된 빔프로젝터가 없습니다.</td></tr>';
        updateDashboardCard('projector', 0);
        console.log('프로젝터 데이터가 없음');
      }
      
      return data;
    })
    .catch(error => {
      console.error('프로젝터 API 호출 실패:', error);
      const tbody = document.getElementById('dashboard-projector-list');
      if (tbody) {
        tbody.innerHTML = '<tr><td colspan="6" class="text-center text-danger">데이터 로드 실패</td></tr>';
      }
      return null;
    });
}

// 실제 PC 데이터 로드 함수 (API 연결용)
function loadRealPCData() {
  return fetch('/api/pcs')
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      return response.json();
    })
    .then(data => {
      console.log('PC API 응답:', data);
      const tbody = document.getElementById('dashboard-pc-list');
      
      if (!tbody) {
        console.error('dashboard-pc-list 테이블을 찾을 수 없습니다');
        return data;
      }
      
      // API 응답 구조 처리
      let pcList = [];
      if (Array.isArray(data)) {
        pcList = data;
      } else if (data && Array.isArray(data.pcs)) {
        pcList = data.pcs;
      } else if (data && Array.isArray(data.data)) {
        pcList = data.data;
      } else if (data && data.success && Array.isArray(data.data)) {
        pcList = data.data;
      }
      
      console.log('처리된 PC 목록:', pcList);
      
      if (pcList && pcList.length > 0) {
        tbody.innerHTML = pcList.map((pc, index) => `
          <tr>
            <td class="text-center">${index + 1}</td>
            <td class="text-center">${pc.name || pc.device_name || '이름 없음'}</td>
            <td class="text-center">${pc.ip || pc.ip_address || 'N/A'}</td>
            <td class="text-center">${pc.mac || pc.mac_address || 'N/A'}</td>
            <td class="text-center">
              <span class="badge ${(pc.networkStatus === 'online' || pc.network_status === 'online' || pc.status === 'online') ? 'badge-online' : 'badge-offline'}">
                ${(pc.networkStatus === 'online' || pc.network_status === 'online' || pc.status === 'online') ? '온라인' : '오프라인'}
              </span>
            </td>
            <td class="text-center">
              <span class="badge ${(pc.powerStatus === 'on' || pc.power_status === 'on' || pc.power === 'on') ? 'badge-online' : 'badge-offline'}">
                ${(pc.powerStatus === 'on' || pc.power_status === 'on' || pc.power === 'on') ? '켜짐' : '꺼짐'}
              </span>
            </td>
          </tr>
        `).join('');
        updateDashboardCard('pc', pcList.length);
        console.log(`PC ${pcList.length}개 표시 완료`);
      } else {
        tbody.innerHTML = '<tr><td colspan="6" class="text-center text-muted">등록된 PC가 없습니다.</td></tr>';
        updateDashboardCard('pc', 0);
        console.log('PC 데이터가 없음');
      }
      
      return data;
    })
    .catch(error => {
      console.error('PC API 호출 실패:', error);
      const tbody = document.getElementById('dashboard-pc-list');
      if (tbody) {
        tbody.innerHTML = '<tr><td colspan="6" class="text-center text-danger">데이터 로드 실패</td></tr>';
      }
      return null;
    });
}

// 실제 PDU 데이터 로드 함수 (API 연결용)
function loadRealPDUData() {
  return fetch('/api/pdus')
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      return response.json();
    })
    .then(data => {
      console.log('PDU API 응답:', data);
      const tbody = document.getElementById('dashboard-pdu-list');
      
      if (!tbody) {
        console.error('dashboard-pdu-list 테이블을 찾을 수 없습니다');
        return data;
      }
      
      // API 응답 구조 처리
      let pduList = [];
      if (Array.isArray(data)) {
        pduList = data;
      } else if (data && Array.isArray(data.pdus)) {
        pduList = data.pdus;
      } else if (data && Array.isArray(data.data)) {
        pduList = data.data;
      } else if (data && data.success && Array.isArray(data.data)) {
        pduList = data.data;
      }
      
      console.log('처리된 PDU 목록:', pduList);
      
      if (pduList && pduList.length > 0) {
        tbody.innerHTML = pduList.map((pdu, index) => `
          <tr>
            <td class="text-center">${index + 1}</td>
            <td class="text-center">${pdu.name || pdu.device_name || '이름 없음'}</td>
            <td class="text-center">${pdu.ip || pdu.ip_address || 'N/A'}</td>
            <td class="text-center">${pdu.port || pdu.port_number || 'N/A'}</td>
            <td class="text-center">
              <span class="badge ${(pdu.networkStatus === 'online' || pdu.network_status === 'online' || pdu.status === 'online') ? 'badge-online' : 'badge-offline'}">
                ${(pdu.networkStatus === 'online' || pdu.network_status === 'online' || pdu.status === 'online') ? '온라인' : '오프라인'}
              </span>
            </td>
            <td class="text-center">
              <span class="badge ${(pdu.powerStatus === 'on' || pdu.power_status === 'on' || pdu.power === 'on') ? 'badge-online' : 'badge-offline'}">
                ${(pdu.powerStatus === 'on' || pdu.power_status === 'on' || pdu.power === 'on') ? '켜짐' : '꺼짐'}
              </span>
            </td>
          </tr>
        `).join('');
        updateDashboardCard('pdu', pduList.length);
        console.log(`PDU ${pduList.length}개 표시 완료`);
      } else {
        tbody.innerHTML = '<tr><td colspan="6" class="text-center text-muted">등록된 PDU가 없습니다.</td></tr>';
        updateDashboardCard('pdu', 0);
        console.log('PDU 데이터가 없음');
      }
      
      return data;
    })
    .catch(error => {
      console.error('PDU API 호출 실패:', error);
      const tbody = document.getElementById('dashboard-pdu-list');
      if (tbody) {
        tbody.innerHTML = '<tr><td colspan="6" class="text-center text-danger">데이터 로드 실패</td></tr>';
      }
      return null;
    });
}

// 메인 대시보드 초기화 함수
function initializeDashboard() {
  console.log('🚀 대시보드 초기화 시작...');
  
  // 페이지 제목 설정
  document.title = "대시보드 - RCS 컨트롤 시스템";
  
  // 웹뷰 플랫폼 감지 및 클래스 추가
  detectPlatformAndApplyStyles();
  
  // DOM이 변경될 때마다 웹뷰 메시지 요소를 찾아 제거
  var observer = new MutationObserver(function(mutations) {
    var selectors = [
      '.webview-message', 
      '.webview-title', 
      '.webview-status',
      '.server-status',
      '.status-bar',
      '.app-title-bar',
      '.app-header-original',
      '[id*="title-container"]',
      '[class*="title-container"]',
      '[id*="server-status"]',
      '[class*="server-status"]',
      '[id*="app-header"]',
      '[class*="app-header"]',
      '.offline-remote-header',
      '#offline-remote-header',
      '.server-status-container',
      '#server-status-container'
    ];
    
    selectors.forEach(function(selector) {
      var elements = document.querySelectorAll(selector);
      elements.forEach(function(el) {
        if(el && el.parentNode) {
          el.style.display = 'none';
          el.style.height = '0';
          el.style.visibility = 'hidden';
          el.style.opacity = '0';
          el.style.position = 'absolute';
          el.style.zIndex = '-9999';
          // 부모 노드에서 요소 제거
          el.parentNode.removeChild(el);
        }
      });
    });
    
    // 첫 번째 요소가 wrapper가 아니면 제거
    var firstElement = document.body.firstElementChild;
    if(firstElement && !firstElement.classList.contains('wrapper') && 
       !firstElement.tagName.toLowerCase().match(/^(script|style|link|meta)$/)) {
      firstElement.style.display = 'none';
      if(firstElement.parentNode) {
        firstElement.parentNode.removeChild(firstElement);
      }
    }
  });
  
  // document.body가 존재할 때만 observer 시작
  if (document.body) {
    observer.observe(document.body, { childList: true, subtree: true });
    
    // 1초마다 반복 실행하여 웹뷰 메시지 요소 제거
    var interval = setInterval(function() {
      observer.takeRecords(); // 현재까지 발생한 변경 확인
    }, 500);
    
    // 30초 후 interval 정지
    setTimeout(function() {
      clearInterval(interval);
    }, 30000);
  }
  
  // 웹뷰 상단 메시지 숨기기
  hideWebViewHeader();
  
  // 모든 링크에 이벤트 추가
  setupNavigation();
  
  // 현재 URL에 맞는 메뉴 활성화
  const currentPath = window.location.pathname;
  const pageName = currentPath.split('/').pop() || 'dashboard.html';
  
  activateMenu(pageName);
  
  // 브라우저 히스토리 상태 설정
  if (history.replaceState) {
    history.replaceState({ page: pageName }, '', pageName);
  }
  
  // 각 모듈 초기화
  initializeTimeManager();
  initializeDeviceManager();
  initializeBulkControl();
  
  // 폰트어썸 아이콘 확인
  setTimeout(function() {
    // 아이콘 폴백 처리 함수
    // 각 아이콘 유형 확인
    checkIcon('.fa-video', '.svg-fallback');
    
    // 다른 아이콘들도 체크 (PC, PDU, 클럭, 그룹 등)
    checkIcon('.fa-desktop', '.svg-fallback-pc');
    checkIcon('.fa-power-off', '.svg-fallback-power');
    checkIcon('.fa-clock', '.svg-fallback-clock');
    checkIcon('.fa-users', '.svg-fallback-group');
  }, 1000); // 페이지 로드 후 1초 후에 확인
  
  console.log('✅ 대시보드 초기화 완료');
} 

// 전역 스코프에 함수들 등록 (다른 파일에서 접근 가능)
window.detectPlatformAndApplyStyles = detectPlatformAndApplyStyles;
window.hideWebViewHeader = hideWebViewHeader;
window.setupNavigation = setupNavigation;
window.navigateToPage = navigateToPage;
window.activateMenu = activateMenu;
window.checkIcon = checkIcon;
window.loadRealProjectorData = loadRealProjectorData;
window.loadRealPCData = loadRealPCData;
window.loadRealPDUData = loadRealPDUData;
window.initializeDashboard = initializeDashboard;

console.log('✅ dashboard-main.js 로드 완료 - 전역 함수 등록됨'); 