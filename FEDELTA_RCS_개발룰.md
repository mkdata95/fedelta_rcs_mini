# 🚀 FEDELTA RCS 개발 룰 문서

## 📋 목차
1. [시스템 & 네트워크 정보 관리 룰](#시스템--네트워크-정보-관리-룰)
2. [대시보드 디자인 룰](#대시보드-디자인-룰)
3. [테이블 헤더 디자인 룰](#테이블-헤더-디자인-룰)
4. [JavaScript 모듈 관리 룰](#javascript-모듈-관리-룰)
5. [Git 백업 및 복구 룰](#git-백업-및-복구-룰)
6. [버그 발생 시 대응 룰](#버그-발생-시-대응-룰)

---

## 🖥️ 시스템 & 네트워크 정보 관리 룰

### ⚠️ **CRITICAL RULE: 더미 데이터 유지 필수**

1. **시스템/네트워크 상태는 반드시 더미 데이터로 유지할 것**
   - ✅ 허용: HTML 하드코딩된 고정값
   - ❌ 금지: 실제 시스템 API 호출

2. **고정 표시 값:**
   ```html
   시스템 상태: "정상"
   CPU 사용량: "CPU: 45%"
   메모리 사용량: "메모리: 62%"
   네트워크 상태: "연결됨"
   네트워크 속도: "속도: 1Gbps"
   핑 상태: "핑: 2ms"
   ```

3. **fetchSystemStatus 함수 구현 금지:**
   ```javascript
   // ✅ 올바른 구현 (아무것도 하지 않음)
   function fetchSystemStatus() {
     console.log('📊 fetchSystemStatus 실행 (현재 구현되지 않음)');
     // TODO: 실제 API 호출로 시스템 상태 가져오기
   }
   ```

4. **시스템 서비스 추가 금지:**
   - ❌ `system_service.dart` 생성 금지
   - ❌ `network_service.dart` 생성 금지  
   - ❌ `system_routes.dart` 생성 금지

**🚨 위반 시 발생하는 문제:**
- 전체 켜기 시 빔프로젝터는 켜지지만 PC가 켜지지 않는 심각한 버그 발생

---

## 🎨 대시보드 디자인 룰

### 1. **테이블 제목 관리 룰**
- ✅ **허용**: 테이블당 1개 제목만 유지
- ❌ **금지**: 3개 제목 (상단 제목 + 카드 헤더 + 추가 헤더) 사용

**올바른 구조:**
```html
<h4>빔프로젝터 모니터링</h4>  <!-- 1개 제목만 -->
<div class="card">
  <table>...</table>
</div>
```

### 2. **헤더 스타일 룰**
- ❌ **금지**: 큰 색상 박스 헤더 (무거운 느낌)
- ✅ **허용**: 깔끔한 제목 + 얇은 색상 라인

**색상 라인 스펙:**
```css
height: 12px;  /* 3px는 너무 얇음 */
background: linear-gradient(90deg, #color1, #color2);
border-radius: 4px;
box-shadow: 0 2px 4px rgba(0,0,0,0.1);
```

### 3. **장비별 색상 구분 룰**
- **파란색**: 빔프로젝터
- **초록색**: PC  
- **노란색**: PDU

### 4. **폰트 크기 통일 룰**
- **제목**: h5, font-size: 1.1rem
- **모든 텍스트**: 시계(1.1rem)와 동일한 크기로 통일
- **한글/숫자 폰트 크기 불일치 문제 해결 필수**

---

## 📊 테이블 헤더 디자인 룰

### 1. **헤더 스타일 템플릿**
```html
<h4 class="mb-4 ml-2" style="color: #e9ecef; font-size: 1.1rem; font-weight: 600; font-family: 'Noto Sans KR', -apple-system, BlinkMacSystemFont, sans-serif; letter-spacing: 0.5px;">
  [장비명] 모니터링
</h4>

<div class="card shadow-sm">
  <div class="card-header" style="background-color: [장비색상]; border-radius: 5px 5px 0 0;">
    <!-- 헤더 내용 -->
  </div>
</div>
```

### 2. **색상 라인 추가 룰**
- 각 테이블 상단에 12px 높이의 색상 라인 필수
- 그라데이션 효과 적용
- 테두리와 그림자 효과 추가

---

## ⚙️ JavaScript 모듈 관리 룰

### 1. **MIME 타입 문제 해결 룰**
- ❌ **금지**: 별도 .js 파일로 분리
- ✅ **허용**: HTML 파일 내 인라인 스크립트만 사용

**이유:** 브라우저에서 JavaScript 파일이 text/html로 서빙되어 실행 거부됨

### 2. **모듈 구조 룰**
```javascript
// 1. time-manager.js 내용 인라인
<script>
  // 시간 관리 함수들
  function forceUpdateTimeCard() { ... }
  function updateCurrentTime() { ... }
  
  // 전역 스코프 등록
  window.forceUpdateTimeCard = forceUpdateTimeCard;
</script>

// 2. device-management.js 내용 인라인  
<script>
  // 장치 관리 함수들
  function loadDashboardProjectorList() { ... }
  function loadDashboardPCList() { ... }
</script>
```

### 3. **자동 새로고침 룰**
- **장치 목록**: 20초마다 자동 새로고침
- **시간 표시**: 1초마다 업데이트
- **상단 카드 숫자**: 장비 등록 시 자동 업데이트

---

## 🔄 Git 백업 및 복구 룰

### 1. **GitHub 백업 확인 룰**
```bash
# 1. 원격 저장소 확인
git remote -v

# 2. 최신 정보 가져오기
git fetch origin

# 3. 백업된 커밋 확인
git log --oneline origin/master -10
```

### 2. **복구 포인트 룰**
- **정상 상태**: 시스템/네트워크 카드 있음 + 더미 데이터
- **복구 대상 커밋**: `8419b2d - Fix: 프로젝터 추가 시 모델명 저장 버그 수정...`

### 3. **복구 명령어 룰**
```bash
# 정상 상태로 복구
git reset --hard 8419b2d
```

---

## 🐛 버그 발생 시 대응 룰

### 1. **프로젝터→PC 켜기 버그 식별 룰**
**증상:**
- 전체 켜기 실행 시
- 빔프로젝터는 정상 켜짐
- PC가 켜지지 않음

**원인:** 시스템/네트워크 실제 API 구현

### 2. **즉시 복구 룰**
```bash
# 1. 현재 상태 확인
git log --oneline -5

# 2. 정상 버전으로 즉시 복구
git reset --hard 8419b2d

# 3. 시스템/네트워크 상태 더미 데이터 확인
grep -n "정상\|45%\|62%" my_app/web/dashboard.html
```

### 3. **예방 룰**
- 시스템/네트워크 관련 수정 요청 시 반드시 거부
- 더미 데이터 유지 필수성 설명
- 대안 제시: UI만 개선하되 실제 데이터 연동 금지

---

## 📝 추가 개발 가이드라인

### 1. **전체 켜기/끄기 함수 미구현 이슈**
- `showBulkOnConfirm` 함수: 구현됨 ✅
- `showBulkOffConfirm` 함수: 구현됨 ✅
- 두 함수 모두 정상 작동 중

### 2. **웹뷰 vs 브라우저 네트워크 측정**
- **웹뷰**: 안드로이드 기기의 실제 네트워크 상태 ✅
- **브라우저**: 같은 안드로이드 기기 상태지만 네트워크 경로 다름 ✅
- **측정 기준**: 모두 안드로이드 기기 기준 ✅

### 3. **테이블 등록된 장비 없을 때 처리**
```javascript
// 적절한 메시지 표시
tbody.innerHTML = '<tr><td colspan="6" class="text-center">등록된 [장비명]이 없습니다.</td></tr>';
```

---

## ⚠️ **최종 경고사항**

### 🚨 **절대 하지 말아야 할 것들:**
1. 시스템/네트워크 정보를 실제 API로 변경
2. SystemService, NetworkService, SystemRoutes 생성
3. fetchSystemStatus에 실제 API 호출 코드 추가
4. 테이블당 3개 제목 사용
5. 큰 색상 박스 헤더 사용
6. JavaScript 파일 분리 (MIME 타입 문제)

### ✅ **반드시 지켜야 할 것들:**
1. 시스템/네트워크 더미 데이터 유지
2. 테이블당 1개 제목만 사용
3. 얇은 색상 라인 헤더 사용
4. JavaScript 인라인 스크립트만 사용
5. 버그 발생 시 즉시 8419b2d로 복구
6. GitHub 백업 상태 정기 확인

---

## 🔧 개발 히스토리

### 주요 문제 해결 과정:
1. **대시보드 파일 손상** → Git checkout으로 복구
2. **JavaScript MIME 타입 문제** → 인라인 스크립트로 해결  
3. **테이블 디자인 "엉망"** → 제목 정리 및 헤더 스타일 개선
4. **시스템 정보 실제 구현** → PC 켜기 버그 발생 → 더미 데이터로 롤백

### 안정적인 기능:
- 20초 자동 장치 목록 새로고침
- 장비 등록 시 자동 테이블 업데이트
- 상단 카드 숫자 자동 업데이트
- 2분 타이머 기반 전체 켜기/끄기 시퀀스

---

**📅 문서 작성일:** 2025년 6월 5일  
**📝 작성자:** Claude Sonnet 4  
**🔄 최종 업데이트:** 시스템/네트워크 더미 데이터 룰 추가  
**📍 저장 위치:** 프로젝트 루트 디렉토리 