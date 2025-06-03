/**
 * RCS 컨트롤 시스템 - 공통 JavaScript 파일
 */

// 페이지 로드 시 실행
document.addEventListener('DOMContentLoaded', function() {
  // 현재 페이지 URL 가져오기
  const currentPath = window.location.pathname;
  const pageName = currentPath.split('/').pop();
  
  // 사이드바 로드 (이미 HTML에 정의된 경우 건너뜀)
  if (!document.querySelector('.main-sidebar')) {
  loadSidebar();
  }
  
  // 현재 페이지에 따라 메뉴 활성화
  activateMenu(pageName);
  
  // 현재 시간 표시
  updateCurrentTime();
  setInterval(updateCurrentTime, 1000);
  
  // 페이지 내 모든 링크에 페이지 이동 이벤트 추가
  setupNavigation();
});

/**
 * 사이드바 HTML 로드 및 삽입
 */
function loadSidebar() {
  const sidebarHtml = `
    <!-- 메인 사이드바 컨테이너 -->
    <aside class="main-sidebar sidebar-dark-primary elevation-4">
      <!-- 브랜드 로고 -->
      <a href="index.html" class="brand-link" onclick="navigateTo('index.html'); return false;">
        <span class="brand-text font-weight-bold ml-3">RCS 컨트롤</span>
      </a>

      <!-- 사이드바 -->
      <div class="sidebar">
        <!-- 사이드바 사용자 패널 -->
        

        <!-- 사이드바 메뉴 -->
        <nav class="mt-2">
          <ul class="nav nav-pills nav-sidebar flex-column" data-widget="treeview" role="menu" data-accordion="false">
            <li class="nav-item">
              <a href="dashboard.html" class="nav-link" onclick="navigateTo('dashboard.html'); return false;">
                <i class="nav-icon fas fa-tachometer-alt"></i>
                <p>
                  대시보드
                </p>
              </a>
            </li>
            <li class="nav-item">
              <a href="projector.html" class="nav-link" onclick="navigateTo('projector.html'); return false;">
                <i class="nav-icon fas fa-projector"></i>
                <p>
                  빔프로젝터관리
                </p>
              </a>
            </li>
            <li class="nav-item">
              <a href="pc.html" class="nav-link" onclick="navigateTo('pc.html'); return false;">
                <i class="nav-icon fas fa-desktop"></i>
                <p>
                  PC관리
                </p>
              </a>
            </li>
            <li class="nav-item">
              <a href="pdu.html" class="nav-link" onclick="navigateTo('pdu.html'); return false;">
                <i class="nav-icon fas fa-plug"></i>
                <p>
                  PDU관리
                </p>
              </a>
            </li>
            <!-- 그룹원격제어 메뉴 숨김 -->
            <!--
            <li class="nav-item">
              <a href="group-control.html" class="nav-link" onclick="navigateTo('group-control.html'); return false;">
                <i class="nav-icon fas fa-layer-group"></i>
                <p>
                  그룹원격제어
                </p>
              </a>
            </li>
            -->
            <!-- 설정 메뉴 숨김 -->
            <!--
            <li class="nav-item">
              <a href="settings.html" class="nav-link" onclick="navigateTo('settings.html'); return false;">
                <i class="nav-icon fas fa-cog"></i>
                <p>
                  설정
                </p>
              </a>
            </li>
            -->
          </ul>
        </nav>
        <!-- /.sidebar-menu -->
      </div>
      <!-- /.sidebar -->
    </aside>
  `;
  
  // 기존 사이드바 대체
  const existingSidebar = document.querySelector('.main-sidebar');
  if (existingSidebar) {
    existingSidebar.outerHTML = sidebarHtml;
  } else {
    // 사이드바가 없는 경우 추가
    const wrapper = document.querySelector('.wrapper');
    if (wrapper) {
      const navbar = document.querySelector('.main-header');
      // 네비게이션 바 다음에 사이드바 추가
      if (navbar) {
        // DOM 요소 생성
        const tempDiv = document.createElement('div');
        tempDiv.innerHTML = sidebarHtml;
        
        // 첫 번째 자식(사이드바)을 추출하여 추가
        const sidebarElement = tempDiv.firstElementChild;
        wrapper.insertBefore(sidebarElement, navbar.nextSibling);
      } else {
        // 네비게이션 바가 없는 경우 래퍼 시작 부분에 추가
        wrapper.insertAdjacentHTML('afterbegin', sidebarHtml);
      }
    }
  }
}

/**
 * 현재 페이지에 따라 메뉴 활성화
 */
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
      activeLink = document.querySelector('.nav-sidebar a[href="index.html"]');
      break;
    case 'dashboard.html':
      activeLink = document.querySelector('.nav-sidebar a[href="dashboard.html"]');
      break;
    case 'projector.html':
      activeLink = document.querySelector('.nav-sidebar a[href="projector.html"]');
      break;
    case 'pc.html':
      activeLink = document.querySelector('.nav-sidebar a[href="pc.html"]');
      break;
    case 'pdu.html':
      activeLink = document.querySelector('.nav-sidebar a[href="pdu.html"]');
      break;
    case 'settings.html':
      activeLink = document.querySelector('.nav-sidebar a[href="settings.html"]');
      break;
    case 'group-control.html':
      activeLink = document.querySelector('.nav-sidebar a[href="group-control.html"]');
      break;
    default:
      // 기본값으로 대시보드 활성화
      activeLink = document.querySelector('.nav-sidebar a[href="dashboard.html"]');
  }
  
  if (activeLink) {
    activeLink.classList.add('active');
  }
}

/**
 * 현재 시간 업데이트
 */
function updateCurrentTime() {
  const now = new Date();
  const options = {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false
  };
  const timeString = now.toLocaleString('ko-KR', options);
  const timeElement = document.getElementById('current-time');
  if (timeElement) {
    timeElement.textContent = timeString;
  }
}

/**
 * 모든 링크에 이벤트 추가
 */
function setupNavigation() {
  document.querySelectorAll('a[href$=".html"]').forEach(function(link) {
    // 이미 처리된 링크는 건너뜁니다
    if (!link.getAttribute('onclick')) {
      const url = link.getAttribute('href');
      link.addEventListener('click', function(e) {
        e.preventDefault();
        navigateTo(url);
      });
    }
  });
}

/**
 * 페이지 이동 함수 (navigateToPage 별칭)
 */
function navigateToPage(url) {
  navigateTo(url);
}

/**
 * 페이지 이동 함수
 */
function navigateTo(url) {
  console.log('페이지 이동:', url);
  
  // 기본 이동 방식 시도
  try {
    window.location.href = url;
  } catch (e) {
    console.error('기본 이동 실패:', e);
    
    // WebView와 통신 시도
    try {
      if (window.AndroidChannel) {
        window.AndroidChannel.postMessage('navigate:' + url);
      } else {
        console.log('AndroidChannel을 찾을 수 없음, 직접 이동 시도');
        document.location.href = url;
      }
    } catch (e2) {
      console.error('대체 이동 실패:', e2);
    }
  }
} 