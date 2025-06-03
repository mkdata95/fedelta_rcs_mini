# 접속 주소 : http://192.168.0.100:8080/pdu.html

# PDU 제어 프로토콜 가이드

## 최종 확인된 동작 방식

1. PDU 응답 특성
   - HTTP/1.0 프로토콜 사용
   - POST 메서드로 제어
   - Content-Type: application/x-www-form-urlencoded
   - 인증 정보는 body에 포함

2. 정확한 명령어 형식
   - 기본 URL: `/api/device/relay`
   - 전원 켜기: `usr=administrator&pwd=password&method=on`
   - 전원 끄기: `usr=administrator&pwd=password&method=off`
   - 상태 확인: `usr=administrator&pwd=password`

3. 통신 설정
   - 포트: 80
   - Connection: close 헤더 필수
   - Content-Length 헤더 필수
   - Host 헤더 필수

## 구현 시 주의사항

1. HTTP/1.0 프로토콜만 사용 (1.1 사용 시 오류)
2. 모든 헤더와 본문 사이에 빈 줄(\r\n\r\n) 필수
3. 응답을 반드시 기다려야 함
4. 각 요청마다 새로운 소켓 연결 필요

## 테스트 결과 요약

1. 작동하는 형식
   ```
   POST /api/device/relay HTTP/1.0
   Host: 192.168.0.222
   Content-Type: application/x-www-form-urlencoded
   Connection: close
   Content-Length: [length]

   usr=administrator&pwd=password&method=on
   ```

2. 작동하지 않는 형식
   - HTTP/1.1 사용 ❌
   - Content-Length 누락 ❌
   - Connection: close 누락 ❌
   - 인증 정보를 헤더로 전송 ❌

## 최적의 구현 방식

1. 소켓 직접 연결 (80 포트)
2. HTTP/1.0 프로토콜로 요청 구성
3. 필수 헤더 포함
   - Host
   - Content-Type
   - Connection: close
   - Content-Length
4. 본문에 인증 정보와 명령어 포함
5. 응답 수신 후 소켓 종료







----------------------------------------------------------------------------------------------------여기부터는 빔프로젝터

# PJLink 프로토콜 구현 가이드




## 최종 확인된 동작 방식

1. 프로젝터 응답 특성
   - 초기 연결 시 `PJLINK 0` 응답
   - Class 1 명령어만 정상 작동
   - 명령어 응답은 받지 않음 (비동기 동작)

2. 정확한 명령어 형식
   - 기본 형식: `%1` + command + `\r`
   - 예시: `%1POWR 1\r` (전원 켜기)
   - 예시: `%1POWR 0\r` (전원 끄기)
   - CR(`\r`) 문자 필수

3. 통신 설정
   - 포트: 4352
   - 소켓 연결 후 초기 응답 대기
   - 명령어 전송 후 flush 필수
   - 짧은 대기 시간 (500ms) 권장

## 구현 시 주의사항

1. 명령어 끝에 반드시 CR(`\r`) 추가
2. 응답을 기다리지 않음 (비동기 처리)
3. 각 명령마다 새로운 소켓 연결 필요
4. 상태 확인 명령은 지원되지 않음

## 테스트 결과 요약

1. 작동하는 형식
   - `%1POWR 1\r` (전원 켜기) ✅
   - `%1POWR 0\r` (전원 끄기) ✅

2. 작동하지 않는 형식
   - `POWR 1` (Class 0) ❌
   - `%1POWR 1` (CR 없음) ❌
   - `%1POWR 1\n` (LF 사용) ❌
   - `%1POWR 1\r\n` (CRLF 사용) ❌

## 최적의 구현 방식

1. 소켓 연결 및 초기 응답 확인
2. Class 1 형식으로 명령어 구성 (`%1` prefix)
3. CR 문자(`\r`) 추가
4. 명령어 전송 후 즉시 flush
5. 짧은 대기 후 소켓 종료
