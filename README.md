# 함수명 평가 설문 사이트 — 배포 가이드 (GitHub Pages + Supabase)

정적 프런트엔드(GitHub Pages) + Supabase Postgres. **로그인(ID+접속코드) → 자동 체크포인트 → 다른 기기에서도 이어하기**. 표/응답은 비밀번호 검증 RPC로만 접근(테이블은 RLS 잠금).

## 파일
```
survey-site/
├─ index.html   설문 앱 (로그인 → 동의·개인정보 1회 → 블록 평정 → 제출)
├─ data.js      설문 데이터 (170블록·433쌍, 블라인드: 예측명만; 모델 정체·중복 제거됨)
├─ config.js    Supabase URL·anon 키 (입력 완료)
├─ schema.sql   테이블 + 로그인/저장 RPC + 평가자 시드 (한 번 실행)
└─ README.md
```

## 1단계 — Supabase (404 해결 + 로그인/이어하기)
1. 대시보드 **SQL Editor** → `schema.sql` 전체 붙여넣기 → **Run**.
   - 이전 `survey_responses 404`는 테이블 미생성 때문이며, 이 스크립트 실행으로 해결됩니다.
2. `schema.sql`의 **(6) 시드 블록**에서 평가자 ID·접속코드·그룹을 실제 값으로 편집(약 10명). 예:
   ```sql
   insert into allowed_raters(rater_id,password,group_id) values
     ('rater01','k7x2-aa',1), ('rater02','m3p9-bb',2), ... ;
   ```
   추가/수정 후 그 INSERT만 다시 Run 해도 됩니다.
3. `config.js`는 이미 입력됨(Project URL·anon public 키). anon 키 공개는 정상 — 접근은 비밀번호 RPC로만.

## 2단계 — GitHub Pages
1. `kimbjunn.github.io` 저장소 루트에 `survey-site/`의 **내용물**(index.html, data.js, config.js, schema.sql 선택) push.
2. Settings → Pages → main /(root) → 저장. → `https://kimbjunn.github.io/` 공개.
   - 다른 콘텐츠를 살리려면 `survey/` 하위폴더에 두어 `https://kimbjunn.github.io/survey/`로 배포.

## 3단계 — 운영
- 평가자에게 **개인 ID + 접속코드** 전달(그룹은 코드에 묶여 자동). 첫 로그인에서 동의·기본정보 1회 입력.
- 평정 중 1.2초마다 자동 저장(체크포인트). 같은 ID로 **어느 기기에서나 이어하기**. 네트워크 끊겨도 로컬 보관 후 재시도, CSV 백업 버튼 제공.

## 데이터 회수 & 비식별 조인
- 대시보드 SQL: `select * from survey_progress;` → CSV export. 응답은 `ratings`(jsonb)에 `"<block>::<pred>": {b,gt,pred,s,t}` 형태.
- 평탄화 + 모델 정체 복원:
  ```python
  import pandas as pd, json
  prog = pd.read_csv("survey_progress.csv")           # Supabase export
  rows=[]
  for _,r in prog.iterrows():
      for k,v in json.loads(r["ratings"]).items():
          rows.append({"rater_id":r["rater_id"],"group_id":r.get("group_id"),
                       "rubric_variant":r["rubric_variant"],"block":v["b"],
                       "gt":v["gt"],"pred":v["pred"],"score":v["s"],"ts":v["t"]})
  long = pd.DataFrame(rows)
  samp = pd.read_csv("pipeline/checkpoints/10_human_eval_sample.csv")
  df = long.merge(samp[["block","pred","true_model","phenomenon","anchor","stratum"]].drop_duplicates(),
                  on=["block","pred"], how="left")   # 한 (block,pred)가 여러 모델이면 모두 매핑
  ```
- 품질 필터: 앵커(조인)·직선응답 평가자 제외 후 IRR. 루브릭 순환점검: `rubric_variant` A/B 비교.

## 보안 메모
- `allowed_raters`·`survey_progress` 테이블은 RLS 잠금(anon 직접 접근 불가). 접근은 `survey_login`/`survey_save`(SECURITY DEFINER, 비밀번호 검증) RPC로만 → 외부에서 응답 열람·임의 제출 불가.
- 접속코드는 *연구 접근 코드*(고보안 자격증명 아님). 평문 저장(잠긴 테이블). 더 강화하려면 pgcrypto 해시 또는 Turnstile 추가.
- `service_role`/`sb_secret_…` 키는 절대 커밋 금지(현재 publishable 키만 사용 — 올바름).

## 데이터 품질 참고
- 블록당 후보 1~4개로 다름: 모델이 기권(빈 예측)하거나 같은 이름을 내면 자연히 달라짐 — **정상**.
- 같은 예측을 낸 모델은 **블록 내 중복 제거**(433 고유쌍). 사람 점수는 (GT,pred)의 함수이므로 1회 평정→분석 시 해당 예측을 낸 모든 모델에 매핑(본 연구의 전제와 일치).
