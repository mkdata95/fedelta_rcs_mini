/**
 * 장치 관리 JavaScript 모듈
 * dashboard.html에서 분리된 장치 관련 함수들
 */

// 장치 수량 가져오기 함수
function fetchDeviceCounts() {
  try {
    // TODO: 실제 API 호출로 장치 수량 가져오기
    // 예시: fetch('/api/devices/count').then(...)
    
    // 임시로 0으로 초기화 (실제 데이터가 로드되면 업데이트됨)
    updateDashboardCard('projector', 0);
    updateDashboardCard('pc', 0);
    updateDashboardCard('pdu', 0);
    
    // console.log('장치 수량 초기화 완료 - 실제 데이터 로드 대기중');
  } catch (error) {
    console.error('장치 수량 가져오기 실패:', error);
  }
}

// 대시보드 카드 업데이트 함수
function updateDashboardCard(type, count) {
  const cards = document.querySelectorAll('.dashboard-card');
  cards.forEach(card => {
    const title = card.querySelector('.dashboard-card-title');
    if (title) {
      const titleText = title.textContent.toLowerCase();
      if ((type === 'projector' && titleText.includes('빔프로젝터')) ||
          (type === 'pc' && titleText.includes('pc')) ||
          (type === 'pdu' && titleText.includes('pdu'))) {
        const numberElement = card.querySelector('.dashboard-card-number');
        if (numberElement && !numberElement.id) { // 시간 카드가 아닌 경우
          numberElement.textContent = count;
        }
      }
    }
  });
}

// 대시보드용 프로젝터 목록 로드
async function loadDashboardProjectorList() {
  try {
    // 데이터 로드
    const response = await fetch('/api/projector/list');
    const data = await response.json();
    
    // 프로젝터 테이블 초기화
    const tbody = document.querySelector('#dashboardProjectorTable tbody');
    if (!tbody) {
      console.error('프로젝터 목록 테이블을 찾을 수 없습니다.');
      return;
    }
    
    // 테이블 초기화
    tbody.innerHTML = '';
    
    // 데이터 없음 처리
    if (!data.devices || data.devices.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" class="text-center">등록된 빔프로젝터가 없습니다.</td></tr>';
      
      // 대시보드 카드의 프로젝터 수량 업데이트
      const projectorElement = document.querySelector('.dashboard-card.blue .dashboard-card-number');
      if (projectorElement) {
        projectorElement.textContent = '0';
      }
      return;
    }
    
    // 대시보드 카드의 프로젝터 수량 업데이트
    const projectorElement = document.querySelector('.dashboard-card.blue .dashboard-card-number');
    if (projectorElement) {
      projectorElement.textContent = data.devices.length;
    }
    
    // 프로젝터 목록 렌더링
    data.devices.forEach((projector, index) => {
      const tr = document.createElement('tr');
      tr.setAttribute('data-id', projector.id);
      tr.setAttribute('data-ip', projector.ip);
      
      // extra 데이터 파싱
      let extraData = {};
      try {
        if (projector.extra) {
          extraData = JSON.parse(projector.extra);
        }
      } catch (e) {
        console.warn(`프로젝터 ID ${projector.id}의 extra 데이터 파싱 오류:`, e);
      }
      
      // 네트워크 상태 배지 CSS 클래스
      const networkStatusClass = projector.network_status === 'online' ? 'badge-online' : 'badge-offline';
      const networkStatusText = projector.network_status === 'online' ? '연결됨' : '대기중';
      
      // 장비 상태 배지 CSS 클래스
      let statusClass = 'badge-offline';
      let statusText = '꺼짐';
      
      // 네트워크 상태가 online일 때만 실제 장비 상태 사용, 아닐 경우 항상 꺼짐으로 표시
      if (projector.network_status === 'online') {
        switch(projector.status) {
          case 'online':
            statusClass = 'badge-online';
            statusText = '켜짐';
            break;
          case 'warming':
            statusClass = 'badge-warning';
            statusText = '예열중';
            break;
          case 'cooling':
            statusClass = 'badge-warning';
            statusText = '냉각중';
            break;
        }
      }
      
      // 행 내용 구성 (순번 추가)
      tr.innerHTML = `
        <td class="text-center">${index + 1}</td>
        <td class="text-center">${projector.name || ''}</td>
        <td class="text-center">${projector.ip || ''}</td>
        <td class="text-center">${extraData.model || '미지정'}</td>
        <td class="text-center"><span class="badge ${networkStatusClass}" title="네트워크 연결 상태">${networkStatusText}</span></td>
        <td class="text-center"><span class="badge ${statusClass}" title="장비 전원 상태">${statusText}</span></td>
      `;
      
      tbody.appendChild(tr);
    });
  } catch (error) {
    console.error('프로젝터 목록 로딩 중 오류:', error);
    // 오류 발생 시 사용자에게 표시
    const tbody = document.querySelector('#dashboardProjectorTable tbody');
    if (tbody) {
      tbody.innerHTML = '<tr><td colspan="6" class="text-center text-danger">데이터 로딩 중 오류가 발생했습니다.</td></tr>';
    }
  }
}

// 대시보드용 PC 목록 로드
async function loadDashboardPCList() {
  try {
    // 데이터 로드
    const response = await fetch('/api/pc/list');
    const data = await response.json();
    
    // 디버깅: PC API 응답 구조 확인
    console.log('PC API 응답 전체:', data);
    console.log('PC API 응답 키들:', Object.keys(data));
    
    // PC 테이블 초기화
    const tbody = document.querySelector('#dashboardPCTable tbody');
    if (!tbody) {
      console.error('PC 목록 테이블을 찾을 수 없습니다.');
      return;
    }
    
    // 테이블 초기화
    tbody.innerHTML = '';
    
    
    // PC 데이터 배열 찾기 - 다양한 가능한 필드명 확인
    let pcList = [];
    if (data.pcs && Array.isArray(data.pcs)) {
      pcList = data.pcs;
    } else if (data.devices && Array.isArray(data.devices)) {
      pcList = data.devices;
    } else if (data.computers && Array.isArray(data.computers)) {
      pcList = data.computers;
    } else if (data.pc_list && Array.isArray(data.pc_list)) {
      pcList = data.pc_list;
    } else if (Array.isArray(data)) {
      pcList = data;
    }
    
    console.log('PC 목록 데이터:', pcList);
    
    // 데이터 없음 처리
    if (!pcList || pcList.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" class="text-center">등록된 PC가 없습니다.</td></tr>';
      
      // 대시보드 카드의 PC 수량 업데이트
      const pcElement = document.querySelector('.dashboard-card.green .dashboard-card-number');
      if (pcElement) {
        pcElement.textContent = '0';
      }
      return;
    }
    
    // 대시보드 카드의 PC 수량 업데이트
    const pcElement = document.querySelector('.dashboard-card.green .dashboard-card-number');
    if (pcElement) {
      pcElement.textContent = pcList.length;
    }
    
    // PC 목록 렌더링
    pcList.forEach((pc, index) => {
      console.log(`PC ${index + 1} 데이터:`, pc);
      console.log(`PC ${pc.name || pc.id} 원본 상태 필드들:`, {
        network_status: pc.network_status,
        ping_status: pc.ping_status,
        connection_status: pc.connection_status,
        status: pc.status,
        power_status: pc.power_status,
        state: pc.state,
        power: pc.power
      });
      
      const tr = document.createElement('tr');
      tr.setAttribute('data-id', pc.id);
      tr.setAttribute('data-ip', pc.ip);
      
      // 네트워크 상태 처리 - 객체인 경우 값 추출
      let networkStatus = pc.network_status || pc.ping_status || pc.connection_status;
      
      // 객체인 경우 처리
      if (typeof networkStatus === 'object' && networkStatus !== null) {
        console.log(`PC ${pc.name || pc.id} 네트워크 상태 객체:`, networkStatus);
        // 객체에서 실제 상태 값 추출
        networkStatus = networkStatus.status || networkStatus.state || networkStatus.value || 
                       networkStatus.online || networkStatus.connected;
      }
      
      console.log(`PC ${pc.name || pc.id} 처리된 네트워크 상태:`, networkStatus);
      
      const isNetworkOnline = networkStatus === 'online' || networkStatus === 1 || networkStatus === true || 
                             networkStatus === 'connected' || networkStatus === 'up';
      const networkStatusClass = isNetworkOnline ? 'badge-online' : 'badge-offline';
      const networkStatusText = isNetworkOnline ? '연결됨' : '대기중';
      
      // PC 전원 상태 처리 - 객체인 경우 값 추출
      let pcStatus = pc.status || pc.power_status || pc.state || pc.power;
      
      // 객체인 경우 처리
      if (typeof pcStatus === 'object' && pcStatus !== null) {
        console.log(`PC ${pc.name || pc.id} 전원 상태 객체:`, pcStatus);
        // 객체에서 실제 상태 값 추출
        pcStatus = pcStatus.status || pcStatus.state || pcStatus.value || 
                   pcStatus.power || pcStatus.running || pcStatus.active;
      }
      
      console.log(`PC ${pc.name || pc.id} 처리된 전원 상태:`, pcStatus);
      
      // PC 상태 배지 CSS 클래스와 텍스트
      let statusClass = 'badge-offline';
      let statusText = '꺼짐';
      
      switch(String(pcStatus).toLowerCase()) {
        case 'online':
        case 'on':
        case 'true':
        case '1':
        case 'running':
        case 'active':
        case 'up':
          statusClass = 'badge-online';
          statusText = '작동중';
          break;
        case 'starting':
        case 'booting':
          statusClass = 'badge-warning';
          statusText = '시작중';
          break;
        case 'shutting_down':
        case 'shutdown':
          statusClass = 'badge-warning';
          statusText = '종료중';
          break;
        case 'rebooting':
        case 'reboot':
          statusClass = 'badge-warning';
          statusText = '재부팅중';
          break;
        case 'offline':
        case 'off':
        case 'false':
        case '0':
        case 'stopped':
        case 'down':
        default:
          statusClass = 'badge-offline';
          statusText = '꺼짐';
          break;
      }
      
      console.log(`PC ${pc.name || pc.id} 최종 표시:`, {
        네트워크: { 상태: networkStatusText, 클래스: networkStatusClass },
        전원: { 상태: statusText, 클래스: statusClass }
      });
      
      // 행 내용 구성
      tr.innerHTML = `
        <td class="text-center">${index + 1}</td>
        <td class="text-center">${pc.name || ''}</td>
        <td class="text-center">${pc.ip || ''}</td>
        <td class="text-center">${pc.mac || ''}</td>
        <td class="text-center"><span class="badge ${networkStatusClass}" title="네트워크 연결 상태">${networkStatusText}</span></td>
        <td class="text-center"><span class="badge ${statusClass}" title="PC 전원 상태">${statusText}</span></td>
      `;
      
      tbody.appendChild(tr);
    });
  } catch (error) {
    console.error('PC 목록 로딩 중 오류:', error);
    // 오류 발생 시 사용자에게 표시
    const tbody = document.querySelector('#dashboardPCTable tbody');
    if (tbody) {
      tbody.innerHTML = '<tr><td colspan="6" class="text-center text-danger">데이터 로딩 중 오류가 발생했습니다.</td></tr>';
    }
  }
}

// 대시보드용 PDU 목록 로드
async function loadDashboardPDUList() {
  try {
    // 데이터 로드
    const response = await fetch('/api/pdu/list');
    const data = await response.json();
    
    // PDU 테이블 초기화
    const tbody = document.querySelector('#dashboardPDUTable tbody');
    if (!tbody) {
      console.error('PDU 목록 테이블을 찾을 수 없습니다.');
      return;
    }
    
    // 테이블 초기화
    tbody.innerHTML = '';
    
    // 데이터 없음 처리 - PDU는 data.pdus 배열 사용
    if (!data.pdus || data.pdus.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" class="text-center">등록된 PDU가 없습니다.</td></tr>';
      
      // 대시보드 카드의 PDU 수량 업데이트
      const pduElement = document.querySelector('.dashboard-card.yellow .dashboard-card-number');
      if (pduElement) {
        pduElement.textContent = '0';
      }
      return;
    }
    
    // 대시보드 카드의 PDU 수량 업데이트
    const pduElement = document.querySelector('.dashboard-card.yellow .dashboard-card-number');
    if (pduElement) {
      pduElement.textContent = data.pdus.length;
    }
    
    // PDU 목록 렌더링
    data.pdus.forEach((pdu, index) => {
      const tr = document.createElement('tr');
      tr.setAttribute('data-id', pdu.id);
      tr.setAttribute('data-ip', pdu.ip);
      
      // 네트워크 상태 배지 CSS 클래스
      const networkStatusClass = pdu.network_status === 'online' ? 'badge-online' : 'badge-offline';
      const networkStatusText = pdu.network_status === 'online' ? '연결됨' : '대기중';
      
      // PDU 전원 상태 배지 CSS 클래스
      let statusClass = 'badge-offline';
      let statusText = '꺼짐';
      
      // power_status 필드로 상태 확인 (power_status가 우선, 없으면 status 사용)
      if (pdu.power_status === 'on' || pdu.power_status === 'online') {
        statusClass = 'badge-online';
        statusText = '켜짐';
      } else if (pdu.status === 'on' || pdu.status === 'online') {
        // 하위 호환성을 위해 status 필드도 확인
        statusClass = 'badge-online';
        statusText = '켜짐';
      }
      
      // 행 내용 구성
      tr.innerHTML = `
        <td class="text-center">${index + 1}</td>
        <td class="text-center">${pdu.name || ''}</td>
        <td class="text-center">${pdu.ip || ''}</td>
        <td class="text-center">${pdu.port || ''}</td>
        <td class="text-center"><span class="badge ${networkStatusClass}" title="네트워크 연결 상태">${networkStatusText}</span></td>
        <td class="text-center"><span class="badge ${statusClass}" title="PDU 전원 상태">${statusText}</span></td>
      `;
      
      tbody.appendChild(tr);
    });
  } catch (error) {
    console.error('PDU 목록 로딩 중 오류:', error);
    // 오류 발생 시 사용자에게 표시
    const tbody = document.querySelector('#dashboardPDUTable tbody');
    if (tbody) {
      tbody.innerHTML = '<tr><td colspan="6" class="text-center text-danger">데이터 로딩 중 오류가 발생했습니다.</td></tr>';
    }
  }
}

// 룸 개수 가져오기 함수
function fetchRoomCount() {
  try {
    // TODO: 실제 API 호출로 룸 개수 가져오기
    // 예시: fetch('/api/rooms/count').then(...)
    // console.log('룸 개수 가져오기 시도 완료');
  } catch (error) {
    console.error('룸 개수 가져오기 실패:', error);
  }
}

// 시스템 상태 가져오기 함수
function fetchSystemStatus() {
  try {
    // TODO: 실제 API 호출로 시스템 상태 가져오기
    // 예시: fetch('/api/system/status').then(...)
    // console.log('시스템 상태 가져오기 시도 완료');
  } catch (error) {
    console.error('시스템 상태 가져오기 실패:', error);
  }
}

// 모든 프로젝터 가져오기
async function fetchAllProjectors() {
  console.log('📡 fetchAllProjectors 시작');
  try {
    const response = await fetch('/api/projector/list');
    console.log('📡 프로젝터 API 응답 상태:', response.status, response.statusText);
    
    const data = await response.json();
    console.log('📊 프로젝터 API 응답 데이터:', data);
    
    let devices = [];
    if (data.success && data.devices) {
      devices = data.devices.map(p => ({ ...p, type: 'projector' }));
      console.log('✅ data.devices 사용:', devices);
    } else {
      const fallbackDevices = data.data?.devices || data.data?.projectors || data.projectors || [];
      devices = fallbackDevices.map(p => ({ ...p, type: 'projector' }));
      console.log('✅ 폴백 데이터 사용:', devices);
    }
    
    console.log(`✅ fetchAllProjectors 완료: ${devices.length}개 프로젝터`);
    return devices;
  } catch (error) {
    console.error('❌ 프로젝터 목록 가져오기 실패:', error);
    return [];
  }
}

// 모든 PC 가져오기 
async function fetchAllPCs() {
  console.log('📡 fetchAllPCs 시작');
  try {
    const response = await fetch('/api/pc/list');
    console.log('📡 PC API 응답 상태:', response.status, response.statusText);
    
    const data = await response.json();
    console.log('📊 PC API 응답 데이터:', data);
    
    let devices = [];
    
    // PC API는 pc_list 키를 사용
    if (data.success && data.pc_list) {
      devices = data.pc_list.map(p => ({ ...p, type: 'pc' }));
      console.log('✅ data.pc_list 사용:', devices);
    } else if (data.success && data.devices) {
      devices = data.devices.map(p => ({ ...p, type: 'pc' }));
      console.log('✅ data.devices 사용:', devices);
    } else {
      // 다양한 폴백 시도
      const fallbackDevices = data.pc_list || data.devices || data.data?.devices || data.data?.pcs || data.data?.computers || data.pcs || data.computers || [];
      devices = fallbackDevices.map(p => ({ ...p, type: 'pc' }));
      console.log('✅ 폴백 데이터 사용:', devices);
    }
    
    // PC 상태 정보 정규화
    devices = devices.map(pc => {
      // 네트워크 상태 정규화
      let networkStatus = pc.network_status || pc.ping_status || pc.connection_status;
      if (typeof networkStatus === 'object' && networkStatus !== null) {
        networkStatus = networkStatus.status || networkStatus.state || networkStatus.value || 
                       networkStatus.online || networkStatus.connected;
      }
      
      // 전원 상태 정규화
      let powerStatus = pc.status || pc.power_status || pc.state || pc.power;
      if (typeof powerStatus === 'object' && powerStatus !== null) {
        powerStatus = powerStatus.status || powerStatus.state || powerStatus.value || 
                     powerStatus.power || powerStatus.running || powerStatus.active;
      }
      
      console.log(`PC ${pc.name || pc.id} 상태 정규화:`, {
        원본_네트워크: pc.network_status,
        정규화된_네트워크: networkStatus,
        원본_전원: pc.status || pc.power_status,
        정규화된_전원: powerStatus
      });
      
      return {
        ...pc,
        type: 'pc',
        network_status: networkStatus,
        power_status: powerStatus
      };
    });
    
    console.log(`✅ fetchAllPCs 완료: ${devices.length}개 PC (상태 정규화됨)`);
    return devices;
  } catch (error) {
    console.error('❌ PC 목록 가져오기 실패:', error);
    return [];
  }
}

// 모든 PDU 가져오기
async function fetchAllPDUs() {
  try {
    const response = await fetch('/api/pdu/list');
    const data = await response.json();
    
    if (data.success && data.devices) {
      return data.devices;
    }
    return data.data?.devices || data.data?.pdus || data.pdus || [];
  } catch (error) {
    console.error('PDU 목록 가져오기 실패:', error);
    return [];
  }
}

// 개별 장치 제어
async function controlDevice(device, action) {
  console.log(`🎯 controlDevice 호출: ${device.type} ${device.name} ${action}`);
  
  if (device.type === 'projector') {
    // 프로젝터는 /api/projector/command 사용
    const command = action === 'on' ? 'power_on' : 'power_off';
    
    const response = await fetch('/api/projector/command', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        ip: device.ip,
        command: command
      })
    });
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    
    const result = await response.json();
    if (!result.success) {
      throw new Error(result.error || result.message || '제어 실패');
    }
    
    console.log(`✅ 프로젝터 제어 성공: ${device.name} ${action}`);
    return result;
    
  } else if (device.type === 'pc') {
    // PC는 각 PC에 설치된 C# 종료 서버 사용 (포트 8081)
    console.log(`🔧 PC 제어 (C# 종료 서버): ${device.name} ${action}`);
    
    if (action === 'off') {
      // PC 끄기: 다양한 방법 시도
      console.log(`🔧 PC 종료 시도: ${device.name} (IP: ${device.ip})`);
      
      // 방법 1: 각 PC의 8081 포트로 POST 요청 (C# 종료 서버)
      try {
        const shutdownUrl = `http://${device.ip}:8081/shutdown`;
        console.log(`📡 방법 1 - C# 종료 서버 요청: ${shutdownUrl}`);
        
        const response = await fetch(shutdownUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({}),
          // 타임아웃 설정 (5초)
          signal: AbortSignal.timeout(5000)
        });
        
        console.log(`📡 C# 종료 서버 응답 상태: ${response.status} ${response.statusText}`);
        
        if (response.ok) {
          const result = await response.text();
          console.log(`✅ C# 종료 서버로 PC 종료 성공: ${device.name}`);
          return { success: true, message: 'C# 종료 서버를 통한 종료 완료' };
        } else {
          throw new Error(`HTTP ${response.status} - C# 종료 서버 응답 실패`);
        }
        
      } catch (error) {
        console.warn(`⚠️ 방법 1 실패 (C# 종료 서버): ${error.message}`);
        
        // 방법 2: 기존 API로 PC 종료 시도
        try {
          console.log(`📡 방법 2 - 기존 API로 PC 종료 시도: ${device.name}`);
          
          const response = await fetch('/api/pc/control', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json'
            },
            body: JSON.stringify({
              pc_id: device.id,
              ip: device.ip,
              action: 'off'
            }),
            // 타임아웃 설정 (10초)
            signal: AbortSignal.timeout(10000)
          });
          
          console.log(`📡 PC 종료 API 응답 상태: ${response.status} ${response.statusText}`);
          
          if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
          }
          
          const result = await response.json();
          console.log(`📊 PC 종료 API 응답:`, result);
          
          if (result.success) {
            console.log(`✅ 기존 API로 PC 종료 성공: ${device.name}`);
            return result;
          } else {
            throw new Error(result.error || result.message || '기존 API를 통한 PC 종료 실패');
          }
          
        } catch (apiError) {
          console.warn(`⚠️ 방법 2 실패 (기존 API): ${apiError.message}`);
          
          // 방법 3: WMI를 통한 원격 종료 시도
          try {
            console.log(`📡 방법 3 - WMI 원격 종료 시도: ${device.name}`);
            
            const response = await fetch('/api/pc/shutdown', {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json'
              },
              body: JSON.stringify({
                ip: device.ip,
                name: device.name,
                method: 'wmi'
              }),
              // 타임아웃 설정 (15초)
              signal: AbortSignal.timeout(15000)
            });
            
            console.log(`📡 WMI 원격 종료 API 응답 상태: ${response.status} ${response.statusText}`);
            
            if (response.ok) {
              const result = await response.json();
              console.log(`📊 WMI 원격 종료 API 응답:`, result);
              
              if (result.success) {
                console.log(`✅ WMI를 통한 PC 종료 성공: ${device.name}`);
                return result;
              } else {
                throw new Error(result.error || 'WMI 원격 종료 실패');
              }
            } else {
              throw new Error(`HTTP ${response.status}`);
            }
            
          } catch (wmiError) {
            console.error(`❌ 방법 3 실패 (WMI): ${wmiError.message}`);
            
            // 모든 방법 실패
            const errorMessage = `모든 PC 종료 방법 실패:\n1. C# 종료 서버: ${error.message}\n2. 기존 API: ${apiError.message}\n3. WMI 원격 종료: ${wmiError.message}`;
            console.error(`❌ PC 종료 완전 실패 (${device.name}):`, errorMessage);
            throw new Error(`PC 종료 실패: ${device.name} - 모든 종료 방법 시도 실패`);
          }
        }
      }
      
    } else if (action === 'on') {
      // PC 켜기: Wake-on-LAN 또는 기존 API 사용
      console.log(`🔧 PC 켜기 시도: ${device.name} (WOL 또는 기존 API)`);
      
      try {
        // 기존 API로 PC 켜기 시도 (WOL 등)
        const response = await fetch('/api/pc/control', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            pc_id: device.id,
            ip: device.ip,
            action: 'on'
          }),
          // 타임아웃 설정 (10초)
          signal: AbortSignal.timeout(10000)
        });
        
        console.log(`📡 PC 켜기 API 응답 상태: ${response.status} ${response.statusText}`);
        
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`);
        }
        
        const result = await response.json();
        console.log(`📊 PC 켜기 API 응답:`, result);
        
        if (!result.success) {
          throw new Error(result.error || result.message || 'PC 켜기 실패');
        }
        
        console.log(`✅ PC 켜기 성공: ${device.name}`);
        return result;
        
      } catch (error) {
        console.error(`❌ PC 켜기 실패 (${device.name}):`, error);
        throw new Error(`PC 켜기 실패: ${error.message}`);
      }
    } else {
      throw new Error(`지원하지 않는 PC 작업: ${action}`);
    }
    
  } else {
    throw new Error(`지원하지 않는 장치 타입: ${device.type}`);
  }
}

// 제어 엔드포인트 가져오기
function getControlEndpoint(deviceType, action) {
  const endpoints = {
    projector: {
      on: '/api/projector/power-on',
      off: '/api/projector/power-off'
    },
    pc: {
      on: '/api/pc/power-on',
      off: '/api/pc/power-off'
    },
    pdu: {
      on: '/api/pdu/power-on',
      off: '/api/pdu/power-off'
    }
  };
  
  return endpoints[deviceType]?.[action] || '/api/device/control';
}

// 장치 관리 모듈 초기화 함수
function initializeDeviceManager() {
  // 장치 수량 가져오기
  fetchDeviceCounts();
  
  // 룸 개수 가져오기
  fetchRoomCount();
  
  // 모든 장치 목록 가져오기
  loadDashboardProjectorList();
  loadDashboardPCList();
  loadDashboardPDUList();
  
  // 시스템 상태 가져오기
  fetchSystemStatus();
  
  // 20초마다 장치 목록 자동 새로고침
  setInterval(loadDashboardProjectorList, 20000);
  setInterval(loadDashboardPCList, 20000);
  setInterval(loadDashboardPDUList, 20000);
  
  console.log('✅ 장치 관리 모듈 초기화 완료');
}

// 전역 스코프에 함수들 등록
window.fetchDeviceCounts = fetchDeviceCounts;
window.updateDashboardCard = updateDashboardCard;
window.loadDashboardProjectorList = loadDashboardProjectorList;
window.loadDashboardPCList = loadDashboardPCList;
window.loadDashboardPDUList = loadDashboardPDUList;
window.fetchRoomCount = fetchRoomCount;
window.fetchSystemStatus = fetchSystemStatus;
window.fetchAllProjectors = fetchAllProjectors;
window.fetchAllPCs = fetchAllPCs;
window.fetchAllPDUs = fetchAllPDUs;
window.controlDevice = controlDevice;
window.getControlEndpoint = getControlEndpoint;
window.initializeDeviceManager = initializeDeviceManager;

console.log('✅ device-management.js 로드 완료 - 전역 함수 등록됨'); 