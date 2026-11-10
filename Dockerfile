# ------------------------------------------------------------
# 베이스: 공식 nginx:alpine 이미지 (기존 이미지 기반 커스텀 - 방식 A)
# ------------------------------------------------------------
FROM nginx:alpine

# [커스텀 1] 메타데이터: 이미지 이름/작성자 식별 (docker image inspect 로 확인 가능)
LABEL org.opencontainers.image.title="my-custom-nginx" \
      maintainer="b1nnas2"

# [커스텀 2] 환경변수: 실행 모드를 이미지에 기록 (코드와 설정 분리 연습)
ENV APP_ENV=production

# [커스텀 3] 정적 콘텐츠 교체: nginx 기본 페이지 -> 내 site/ 폴더
#   - site/ 는 "빌드 컨텍스트(.) 기준 상대 경로", 목적지는 "컨테이너 절대 경로"
COPY site/ /usr/share/nginx/html/

# [커스텀 4] 헬스체크: 컨테이너가 실제로 응답하는지 Docker가 주기적으로 검사
HEALTHCHECK --interval=5s --timeout=3s --start-period=3s --retries=3 \
  CMD wget -q -O /dev/null http://localhost/ || exit 1

# 컨테이너 내부에서 nginx가 듣는 포트 (문서화 목적, 실제 공개는 docker run -p 로 함)
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
