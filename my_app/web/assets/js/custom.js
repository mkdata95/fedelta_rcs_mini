/**
 * 오프라인 리모트 컨트롤 시스템 - 커스텀 스크립트
 */

// 페이지 로드 시 실행
$(document).ready(function() {
  // 차트 초기화
  initCharts();
  
  // 이벤트 리스너 설정
  setupEventListeners();
  
  // 시뮬레이션된 로그 메시지 표시
  setInterval(simulateLogMessages, 5000);
  
  // 장치 상태 주기적 업데이트
  setInterval(updateDeviceStatus, 3000);
});

/**
 * 차트 초기화 함수
 */
function initCharts() {
  // 파이 차트 설정
  if (document.getElementById("pieChart")) {
    var ctx = document.getElementById("pieChart").getContext('2d');
    new Chart(ctx, {
      type: 'pie',
      data: {
        labels: ['PC', '빔프로젝터', 'PDU', '네트워크'],
        datasets: [{
          data: [35, 25, 20, 20],
          backgroundColor: ['#dc3545', '#28a745', '#ffc107', '#17a2b8'],
          borderWidth: 0
        }]
      },
      options: {
        legend: {
          display: false
        },
        responsive: true,
        maintainAspectRatio: false
      }
    });
  }
}

/**
 * 이벤트 리스너 설정
 */
function setupEventListeners() {
  // PC 전원 켜기 버튼
  $('.tab-pane#pc-control .btn-success').click(function() {
    sendCommand('pc', 'power_on');
    addLogMessage('PC-001 전원 켜기 명령을 보냈습니다.');
  });
  
  // PC 전원 끄기 버튼
  $('.tab-pane#pc-control .btn-danger').click(function() {
    sendCommand('pc', 'power_off');
    addLogMessage('PC-001 전원 끄기 명령을 보냈습니다.');
  });
  
  // PC 재부팅 버튼
  $('.tab-pane#pc-control .btn-warning').click(function() {
    sendCommand('pc', 'reboot');
    addLogMessage('PC-001 재부팅 명령을 보냈습니다.');
  });
  
  // 빔프로젝터 전원 켜기 버튼
  $('.tab-pane#projector-control .btn-success').click(function() {
    sendCommand('projector', 'power_on');
    addLogMessage('빔프로젝터-001 전원 켜기 명령을 보냈습니다.');
  });
  
  // 빔프로젝터 전원 끄기 버튼
  $('.tab-pane#projector-control .btn-danger').click(function() {
    sendCommand('projector', 'power_off');
    addLogMessage('빔프로젝터-001 전원 끄기 명령을 보냈습니다.');
  });
  
  // 빔프로젝터 입력 소스 변경
  $('.tab-pane#projector-control select').change(function() {
    var source = $(this).val();
    sendCommand('projector', 'change_source', source);
    addLogMessage('빔프로젝터-001 입력 소스를 ' + source + '로 변경했습니다.');
  });
  
  // PDU 스위치 토글
  $('.tab-pane#pdu-control .custom-control-input').change(function() {
    var port = $(this).attr('id').replace('port', '');
    var state = $(this).is(':checked') ? 'on' : 'off';
    sendCommand('pdu', 'toggle', { port: port, state: state });
    addLogMessage('PDU 포트 ' + port + '를 ' + (state === 'on' ? '활성화' : '비활성화') + '했습니다.');
  });
  
  // 명령 입력 폼 제출
  $('.card-footer form').submit(function(e) {
    e.preventDefault();
    var command = $(this).find('input[name="message"]').val();
    if (command.trim() !== '') {
      executeCommand(command);
      $(this).find('input[name="message"]').val('');
    }
  });
}

/**
 * 명령 전송 함수
 */
function sendCommand(device, action, params) {
  console.log('명령 전송:', device, action, params);
  // 실제 구현에서는 여기서 서버로 API 요청을 보냄
  
  // 시뮬레이션을 위한 상태 변경
  setTimeout(function() {
    if (device === 'pc') {
      if (action === 'power_on') {
        $('tr:contains("PC-001") td:nth-child(2) span').removeClass('badge-danger').addClass('badge-success').text('온라인');
      } else if (action === 'power_off') {
        $('tr:contains("PC-001") td:nth-child(2) span').removeClass('badge-success').addClass('badge-danger').text('오프라인');
      }
    } else if (device === 'projector') {
      if (action === 'power_on') {
        $('tr:contains("빔프로젝터-001") td:nth-child(2) span').removeClass('badge-danger').addClass('badge-success').text('온라인');
      } else if (action === 'power_off') {
        $('tr:contains("빔프로젝터-001") td:nth-child(2) span').removeClass('badge-success').addClass('badge-danger').text('오프라인');
      }
    } else if (device === 'pdu') {
      // PDU 포트 상태 업데이트
    }
  }, 1000);
}

/**
 * 로그 메시지 추가
 */
function addLogMessage(message) {
  var now = new Date();
  var timeString = now.getHours() + ':' + now.getMinutes();
  
  var messageHtml = `
    <div class="direct-chat-msg">
      <div class="direct-chat-infos clearfix">
        <span class="direct-chat-name float-left">시스템</span>
        <span class="direct-chat-timestamp float-right">${now.toLocaleString()}</span>
      </div>
      <div class="direct-chat-text">
        ${message}
      </div>
    </div>
  `;
  
  $('.direct-chat-messages').append(messageHtml);
  $('.direct-chat-messages').scrollTop($('.direct-chat-messages')[0].scrollHeight);
}

/**
 * 명령어 실행
 */
function executeCommand(commandText) {
  addLogMessage('명령 실행: ' + commandText);
  
  // 명령어 파싱 및 처리 로직
  if (commandText.includes('켜기') || commandText.includes('on')) {
    if (commandText.includes('pc')) {
      sendCommand('pc', 'power_on');
    } else if (commandText.includes('빔프로젝터') || commandText.includes('프로젝터')) {
      sendCommand('projector', 'power_on');
    }
  } else if (commandText.includes('끄기') || commandText.includes('off')) {
    if (commandText.includes('pc')) {
      sendCommand('pc', 'power_off');
    } else if (commandText.includes('빔프로젝터') || commandText.includes('프로젝터')) {
      sendCommand('projector', 'power_off');
    }
  } else if (commandText.includes('재부팅') || commandText.includes('reboot')) {
    if (commandText.includes('pc')) {
      sendCommand('pc', 'reboot');
    }
  } else if (commandText.includes('포트') && commandText.includes('pdu')) {
    var portMatch = commandText.match(/포트\s*(\d+)/);
    if (portMatch && portMatch[1]) {
      var port = portMatch[1];
      var state = commandText.includes('켜기') || commandText.includes('on') ? 'on' : 'off';
      sendCommand('pdu', 'toggle', { port: port, state: state });
    }
  } else {
    addLogMessage('알 수 없는 명령입니다.');
  }
}

/**
 * 시뮬레이션된 로그 메시지
 */
function simulateLogMessages() {
  var messages = [
    '네트워크 스위치 상태 확인 중...',
    'PC-001 상태 확인 중...',
    '빔프로젝터-001 상태 확인 중...',
    'PDU 상태 확인 중...'
  ];
  
  // 로그 시뮬레이션 빈도를 줄임 (30% -> 10%)
  if (Math.random() < 0.1) {
    var randomIndex = Math.floor(Math.random() * messages.length);
    addLogMessage(messages[randomIndex]);
  }
}

/**
 * 장치 상태 업데이트
 */
function updateDeviceStatus() {
  // 장치 상태 업데이트 시뮬레이션
  $('tr td:nth-child(3)').each(function() {
    var time = parseInt($(this).text());
    if (time.toString().includes('분')) {
      var minutes = parseInt(time);
      if (minutes < 60) {
        $(this).text((minutes + 1) + '분 전');
      } else {
        $(this).text('1시간 전');
      }
    } else if (time.toString().includes('시간')) {
      // 시간은 그대로 둠
    }
  });
} 