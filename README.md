# 함수명 평가 설문 사이트 — 배포 가이드 (GitHub Pages + Supabase)

정적 프런트엔드(GitHub Pages) + Supabase Postgres. **회원가입(아이디·비밀번호 직접 설정) → 자동 체크포인트 → 다른 기기에서 이어하기 → 분실 시 이메일로 복구**. 데이터는 비밀번호 검증 RPC로만 접근(테이블 RLS 잠금, 비밀번호 bcrypt 해시).

## 파일
```
survey-site/
├─ index.html   설문 앱 (로그인 / 회원가입 / 찾기 → 블록 평정 → 제출)
├─ data.js      설문 데이터 (170블록·433쌍, 블라인드: 예측명만)
├─ config.js    Supabase URL·anon 키 (입력 완료)
├─ schema.sql   raters 테이블 + 가입/로그인/저장/복구 RPC (한 번 실행)
└─ README.md
```

## 1단계 — Supabase (한 번)
1. 대시보드 **SQL Editor** → `schema.sql` 전체 붙여넣기 → **Run**. (pgcrypto 확장·`raters` 테이블·RPC 5종 생성. 평가자 시드 불필요 — 사용자가 직접 가입.)
2. `config.js`는 이미 입력됨(URL·anon public 키). anon 키 공개 정상 — 접근은 비밀번호 검증 RPC로만, 비밀번호는 bcrypt 해시 저장.
3. (선택) **스팸 차단용 공용 초대 코드**: 누구나 가입 가능한 게 부담되면, 한 줄로 게이트를 켭니다.
   ```sql
   insert into survey_config(key,value) values ('invite_code','STUDY-2026');
   ```
   이러면 가입 시 이 코드를 입력해야 합니다(연구자가 평가자에게 1개 코드만 공유). 안 넣으면 공개 가입.

## 2단계 — GitHub Pages
1. `kimbjunn.github.io` 루트에 `survey-site/` **내용물**(index.html, data.js, config.js, schema.sql) push.
2. Settings → Pages → main /(root) → 저장 → `https://kimbjunn.github.io/`.

## 3단계 — 운영
- 평가자는 사이트에서 **회원가입**(아이디·비밀번호·이메일·기본정보·동의). 그룹은 자동 균형 배정, 루브릭 변형(A/B)도 자동.
- 평정 중 자동 저장 + 탭 닫힘 시 flush + 같은 계정으로 **어느 기기서나 이어하기**.
- **분실 복구**: 로그인 화면 → "아이디·비밀번호 찾기" → 이메일로 아이디 조회 / (아이디+이메일)로 비밀번호 재설정.

## 데이터 회수 & 비식별 조인
- 대시보드 SQL: `select rater_id, email, group_id, rubric_variant, personal, ratings, submitted, updated_at from raters;` → CSV export.
- 평탄화 + 모델 정체 복원:
  ```python
  import pandas as pd, json
  rt = pd.read_csv("raters.csv")
  rows=[]
  for _,r in rt.iterrows():
      for k,v in json.loads(r["ratings"]).items():
          rows.append({"rater_id":r["rater_id"],"group_id":r["group_id"],"rubric_variant":r["rubric_variant"],
                       "block":v["b"],"gt":v["gt"],"pred":v["pred"],"score":v["s"],"ts":v["t"]})
  long=pd.DataFrame(rows)
  samp=pd.read_csv("pipeline/checkpoints/10_human_eval_sample.csv")
  df=long.merge(samp[["block","pred","true_model","phenomenon","anchor","stratum"]].drop_duplicates(),
                on=["block","pred"], how="left")
  ```
- 품질 필터: 앵커·직선응답 평가자 제외 후 IRR. 루브릭 순환점검: `rubric_variant` A/B 비교. 인구통계는 `personal` jsonb + `email`.

## 보안 메모
- 비밀번호 **bcrypt 해시**(pgcrypto). `raters` 테이블 RLS 잠금 — 접근은 `survey_signup/login/save/find_id/reset_pw` RPC(SECURITY DEFINER)로만.
- 공개 가입이므로 무작위 제출 가능 → 위 **초대 코드** 또는 Cloudflare Turnstile 권장(연구 데이터 품질). 앵커·주의력 점검으로도 불량 응답 사후 제거.
- 복구는 이메일 기반(아이디 조회 / 아이디+이메일로 재설정) — 저보안 연구용. 더 강화하려면 이메일 인증 링크(Supabase Auth/Edge Function) 도입.
- `service_role`/`sb_secret_…` 키 커밋 금지(현재 publishable 키만 — 올바름).

## 주의
- **schema.sql과 index.html이 바뀌었습니다(v3).** Supabase에 schema.sql을 다시 Run 하고, index.html을 다시 push 하세요.
- 데이터 품질: 블록당 후보 1~4개(모델 기권/동일예측 시 자연 발생, 정상), 동일 예측은 블록 내 중복 제거(433 고유쌍), 점수는 (GT,pred) 단위 1회 평정.
