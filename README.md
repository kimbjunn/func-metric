# 함수명 평가 설문 사이트 — 배포 가이드 (GitHub Pages + Supabase)

정적 프런트엔드(GitHub Pages) + 호스팅 Postgres(Supabase) 조합. 서버 코드 없이 브라우저에서 직접 DB에 기록한다. 개인정보 보호를 위해 **RLS는 INSERT 전용**(공개 anon 키로 제출만 가능, 읽기 불가).

## 파일
```
survey-site/
├─ index.html     설문 앱 (동의·개인정보 → 블록 평정 → 제출)
├─ data.js        설문 데이터 (블라인드: masked_model·pred·gt만, 정체 미노출)
├─ config.js      Supabase URL·anon 키 (여기를 채운다)
├─ schema.sql     Supabase 테이블 + RLS (한 번 실행)
└─ README.md      이 문서
```

## 1단계 — Supabase (약 5분)
1. supabase.com 가입 → New project 생성(무료 플랜).
2. 좌측 **SQL Editor** → `schema.sql` 내용 붙여넣기 → **Run**.
3. **Project Settings → API** 에서 두 값 복사:
   - `Project URL` → `config.js`의 `SUPABASE_URL`
   - `anon public` 키 → `config.js`의 `SUPABASE_ANON_KEY`
4. 저장. (anon 키 공개는 정상 — RLS가 읽기를 막는다. `service_role` 키는 절대 커밋 금지.)

## 2단계 — GitHub Pages (약 5분)
1. 새 public 저장소 생성(예: `funcname-eval`).
2. `survey-site/`의 **내용물**(index.html, data.js, config.js)을 저장소 루트에 push.
3. **Settings → Pages** → Source: `Deploy from a branch` → `main` / `/(root)` → Save.
4. 1~2분 후 `https://<USER>.github.io/funcname-eval/` 공개. 이 URL을 평가자에게 배포.

## 3단계 — 운영
- 평가자에게 URL + 배정 그룹(1 또는 2) 안내. 동의·개인정보 입력 후 평정.
- 코어 블록은 전원 공통, 그룹 블록은 절반씩(자동 분기). 진행은 기기 localStorage에 자동 저장→이어하기.
- 제출 시 (제출시각·개인정보·전체 평정)이 한 번에 기록. DB 실패 시 자동으로 **CSV 백업 내려받기** 안내.

## 데이터 회수 & 비식별 조인
- Supabase **Table editor**에서 `survey_responses` 확인, 또는 SQL Editor에서 `select * from survey_responses;` → CSV export.
- 모델 정체는 클라이언트에 노출하지 않았으므로, 분석 시 `(block, masked_model)`로 `pipeline/checkpoints/10_human_eval_sample.csv`와 조인해 `true_model·phenomenon·anchor·stratum`을 복원:
  ```python
  import pandas as pd
  resp = pd.read_csv("survey_responses.csv")          # Supabase export
  samp = pd.read_csv("10_human_eval_sample.csv")       # 마스킹·정체 매핑 보유
  df = resp.merge(samp[["block","masked_model","true_model","phenomenon","anchor","stratum"]],
                  on=["block","masked_model"], how="left")
  ```
- 루브릭 순환 점검: `rubric_variant`(A/B)별 결론 비교.
- 품질 필터: 앵커(조인으로 식별)·직선응답 평가자 제외 후 IRR.

## 개인정보·보안 메모
- anon 키는 INSERT만 가능 → 외부에서 응답 열람 불가. 읽기는 대시보드/`service_role`로만.
- 폐쇄 모집(소수 평가자)이라 스팸 위험 낮음. 더 막고 싶으면 Cloudflare Turnstile 또는 제출 시 공유 비밀코드 필드 + Edge Function 검증 추가 가능.
- 이메일 등은 보상·연락 목적의 선택 입력이며 동의 후 수집. IRB/동의서 절차와 함께 운영.

## DB 없이 시험하려면
`config.js`의 `SURVEY_DB_ENABLED=false` → 모든 응답을 CSV로만 받는 모드(파일럿·로컬 테스트용).
