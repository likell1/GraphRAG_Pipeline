# 논문 데이터 파이프라인 설계

# GraphRAG 논문 추출 파이프라인 브론즈-실버-골드 리팩토링 설계 계획서

## 1. 문서 목적

본 문서는 기존 논문 추출 파이프라인을 **Bronze-Silver-Gold 레이어 구조**로 재설계하기 위한 기준 문서이다.

현재 파이프라인은 기능적으로 다음과 같이 나뉘어 있다.

- 논문 메타데이터 수집
- 논문 abstract chunk 생성
- chunk 기반 claim 추출 및 정규화

기존 구조는 단계별 로직이 분리되어 있다는 장점이 있으나, 각 단계의 산출물이 명확한 데이터 레이어로 관리되지 않아 다음과 같은 한계가 있다.

- 재실행 범위 제어가 어렵다
- 특정 배치의 결과를 추적하기 어렵다
- 중간 산출물 검수 및 비교가 어렵다
- 그래프 적재와 claim 생성이 강하게 결합될 위험이 있다
- 향후 S3/Airflow/Lambda 기반 자동화 확장 시 운영 경계가 모호해질 수 있다

따라서 본 리팩토링의 목표는 기존 기능을 유지하면서도, 파이프라인을 **원천 보존 → 정제 → 활용 데이터셋**구조로 재편하여 재현성, 검수성, 운영성을 높이는 것이다.

---

## 2. 리팩토링 목표

이번 리팩토링의 핵심 목표는 다음과 같다.

### 2.1 데이터 레이어 명확화

논문 수집부터 claim 생성까지의 흐름을 Bronze, Silver, Gold 계층으로 명확히 구분한다.

### 2.2 산출물 중심 구조로 전환

각 단계 결과를 독립적인 파일 산출물로 남겨, 재처리 및 검수를 쉽게 한다.

### 2.3 배치 추적 가능성 확보

각 실행 결과에 `batch_id`, 생성 시각, 코드 버전 등을 부여하여 lineage를 확보한다.

### 2.4 그래프 적재와 분리

Gold는 그래프 적재 직전의 정규화 claim 데이터셋까지 담당하고, 실제 Neo4j 적재는 별도 단계로 분리한다.

### 2.5 향후 운영 자동화 대비

Docker, Airflow, S3, Lambda 기반 자동화와 자연스럽게 연결될 수 있도록 실행 단위를 계층별로 분리한다.

---

## 3. 현재 파이프라인 구조와 한계

현재 파이프라인은 개념적으로 다음 3단계로 구성되어 있다.

### 3.1 Metadata 단계

PubMed에서 논문을 검색하고 XML 응답을 파싱하여 논문 메타데이터를 저장한다.

### 3.2 Chunk 단계

논문 abstract를 불러와 chunk 단위로 분리하고 저장한다.

### 3.3 Claim 단계

chunk를 입력으로 하여 sentence 분리, ingredient candidate 탐지, LLM 기반 claim 추출, validation, taxonomy mapping을 수행한 뒤 결과를 저장한다.

이 구조는 처리 흐름 자체는 합리적이지만, 다음과 같은 한계가 있다.

### 3.4 현재 구조의 문제점

### 1) 처리 단계와 저장 계층이 섞여 있다

각 단계가 끝난 뒤 운영용 DB 테이블에 바로 적재되는 구조이기 때문에, 레이어 산출물이 독립적으로 남지 않는다.

### 2) 원천 데이터 보존이 약하다

검색 쿼리, alias, PubMed raw XML, 수집 시점 정보 같은 원천 컨텍스트가 충분히 남지 않으면 재처리가 어렵다.

### 3) 중간 결과 검수가 어렵다

abstract가 어떻게 chunk로 바뀌었는지, chunk에서 어떤 claim이 추출됐는지 배치별로 쉽게 비교·검토하기 어렵다.

### 4) 그래프 적재와의 결합 가능성이 높다

claim 추출 결과가 곧바로 그래프 적재 구조로 이어지면 graph schema 변경 시 추출 파이프라인까지 흔들릴 수 있다.

---

## 4. 리팩토링 기본 원칙

이번 설계는 아래 원칙을 따른다.

### 4.1 기존 로직은 최대한 유지한다

기존의 metadata, chunk, claim 단계별 처리 로직은 최대한 재사용한다.

이번 작업의 핵심은 알고리즘 전체 재작성보다는 **산출물 구조와 실행 경계 재정의**이다.

### 4.2 레이어 산출물은 파일 기반으로 남긴다

각 레이어의 결과는 parquet/csv/json 파일로 저장한다.

운영 DB는 필요 시 후속 load 단계에서 사용한다.

### 4.3 모든 레이어는 batch 단위로 관리한다

각 실행은 고유한 `batch_id`를 가진다.

후속 레이어는 상위 레이어 배치를 입력으로 받아 처리한다.

### 4.4 provenance를 유지한다

Gold의 모든 claim은 어느 paper, 어느 chunk, 어느 sentence에서 왔는지 추적 가능해야 한다.

### 4.5 graph load는 Gold 이후 별도 단계로 둔다

Gold는 정규화 claim 데이터셋까지 담당한다.

Neo4j 적재는 `serving` 혹은 `load` 단계에서 분리 수행한다.

---

## 5. 제안 레이어 구조

## 5.1 Bronze 레이어

### 정의

PubMed로부터 수집한 **원천 논문 데이터**를 저장하는 계층.

### 포함 범위

- 검색 쿼리 정보
- 성분별 검색 컨텍스트
- PMID 검색 결과
- PubMed raw XML 또는 raw response
- 논문 메타데이터
- abstract 원문

### Bronze를 단순 메타데이터 계층으로 보지 않는 이유

Bronze는 단지 title, abstract 같은 일부 컬럼만 저장하는 계층이 아니라,

**나중에 다시 파싱하거나 정제 규칙을 바꿔도 재처리 가능한 원천 데이터 계층**이어야 한다.

즉, Bronze는 “논문 메타데이터”가 아니라 **논문 원천 수집 결과 전체**로 정의한다.

### 주요 산출물

- `search_log.parquet`
- `paper_raw.parquet`
- `pubmed_raw.xml`
- `metadata.json`

---

## 5.2 Silver 레이어

### 정의

Bronze의 원천 논문 데이터를 **LLM/규칙 기반 분석에 적합한 텍스트 단위로 정제한 계층**

### 포함 범위

- 정제된 논문 텍스트
- abstract chunk
- 문장 위치 정보
- chunk 인덱스
- section_type
- offset

### Silver를 독립 계층으로 두는 이유

claim 추출 품질은 입력 chunk 품질에 크게 의존한다.

따라서 chunk 생성은 단순 중간 과정이 아니라, Gold 품질을 결정하는 핵심 정제 단계이다.

또한 chunk 정책은 향후 자주 바뀔 수 있다.

예:

- sentence window 조정
- section 포함 범위 변경
- title/conclusion 포함 여부 변경
- token 길이 기준 변경

이런 변경이 자주 일어날 수 있으므로 Silver는 독립된 계층으로 운영하는 것이 적절하다.

### 주요 산출물

- `paper_text.parquet` (선택)
- `paper_chunk.parquet`
- `metadata.json`

---

## 5.3 Gold 레이어

### 정의

Silver chunk로부터 추출한 claim을 **그래프 적재 가능한 형태로 정규화한 최종 활용 데이터셋 계층**

### 포함 범위

- ingredient canonicalization
- relation normalization
- target normalization
- normalized summary
- effect taxonomy mapping
- concern taxonomy mapping
- confidence / provenance

### Gold를 graph load와 분리하는 이유

Gold는 데이터 제품 계층이고, Graph Load는 적재 계층이다.

이 둘을 분리해야 다음과 같은 이점이 있다.

- graph schema 변경 시 claim 추출 파이프라인을 다시 흔들지 않아도 된다
- Gold 데이터셋을 PostgreSQL 검수, 검색 시스템, API 테스트 등 다른 용도로도 재사용할 수 있다
- 품질 검수와 적재 로직을 독립적으로 운영할 수 있다

### 주요 산출물

- `graph_claim.parquet`
- `claim_effect_map.parquet`
- `claim_concern_map.parquet`
- `metadata.json`

---

## 6. 최종 파이프라인 흐름

전체 흐름은 아래와 같이 정의한다.

```
Bronze (PubMed Raw)
→ Silver (Paper Chunk)
→ Gold (Normalized Claim Dataset)
→ Graph Load (Neo4j Ingest)
```

각 계층은 독립 실행 가능해야 하며, 특정 상위 레이어 배치를 입력으로 받는다.

---

## 7. 디렉토리 구조 설계

권장 디렉토리 구조는 다음과 같다.

```
project/
├── bronze/
│   └── pubmed/
│       └── batch=YYYY-MM-DDTHH-MM-SS/
│           ├── search_log.parquet
│           ├── paper_raw.parquet
│           ├── pubmed_raw.xml
│           └── metadata.json
│
├── silver/
│   └── paper/
│       └── batch=YYYY-MM-DDTHH-MM-SS/
│           ├── paper_text.parquet
│           ├── paper_chunk.parquet
│           └── metadata.json
│
├── gold/
│   └── claim/
│       └── batch=YYYY-MM-DDTHH-MM-SS/
│           ├── graph_claim.parquet
│           ├── claim_effect_map.parquet
│           ├── claim_concern_map.parquet
│           └── metadata.json
│
├── pipeline/
│   ├── bronze/
│   │   └── pubmed/
│   ├── silver/
│   │   └── paper/
│   ├── gold/
│   │   └── claim/
│   ├── common/
│   └── serving/
│       └── neo4j/
│
└── data/
    └── target_ingredients.csv
```

---

## 8. 레이어별 상세 산출물 설계

## 8.1 Bronze 산출물 설계

### 8.1.1 `search_log.parquet`

성분별 검색 기록과 query context를 저장한다.

권장 컬럼:

- `batch_id`
- `source`
- `ingredient_code`
- `canonical_name`
- `query_name`
- `alias_list`
- `concern_keywords`
- `final_query`
- `retmax`
- `pmid_count`
- `collected_at`

### 필요 이유

이 파일은 “왜 이 논문이 수집되었는가”를 설명해주는 핵심 근거다.

query builder를 바꾸었을 때 recall 비교에도 사용된다.

---

### 8.1.2 `paper_raw.parquet`

PubMed raw XML에서 파싱한 논문 원천 데이터를 저장한다.

권장 컬럼:

- `batch_id`
- `source`
- `pmid`
- `pmcid`
- `doi`
- `title`
- `abstract_text`
- `journal`
- `publication_year`
- `authors`
- `language_code`
- `searched_ingredient`
- `query_name`
- `final_query`
- `collected_at`

### 필요 이유

이 파일이 있어야 Silver를 DB 의존 없이 다시 만들 수 있다.

---

### 8.1.3 `pubmed_raw.xml`

원천 XML 응답을 저장한다.

### 필요 이유

파서 로직이 잘못되었는지, PubMed 응답 자체가 비정상인지 구분할 수 있게 해준다.

디버깅과 재현성 측면에서 유용하다.

---

### 8.1.4 `metadata.json`

해당 Bronze 배치의 요약 정보를 담는다.

권장 예시:

```
{
  "layer":"bronze",
  "domain":"pubmed",
  "batch_id":"2026-04-01T10-30-00",
  "row_count":120,
  "unique_pmids":110,
  "target_count":8,
  "created_at":"2026-04-01T10:35:20+09:00",
  "code_version":"git-sha"
}
```

---

## 8.2 Silver 산출물 설계

## 8.2.1 `paper_text.parquet`

정제된 논문 텍스트를 저장한다.

필수는 아니지만, 추후 text cleaning 로직을 따로 관리할 계획이 있다면 두는 것이 좋다.

권장 컬럼:

- `batch_id`
- `paper_key`
- `section_type`
- `raw_text`
- `normalized_text`
- `char_count`

---

## 8.2.2 `paper_chunk.parquet`

Silver의 핵심 산출물이다.

권장 컬럼:

- `batch_id`
- `paper_key`
- `pmid`
- `section_type`
- `chunk_index`
- `chunk_text`
- `char_count`
- `token_count`
- `source_start_offset`
- `source_end_offset`
- `chunk_version`

### 필요 이유

Gold claim 추출은 이 chunk를 입력으로 수행된다.

Chunk 정책이 바뀌어도 Bronze를 다시 수집하지 않고 Silver부터 재생성할 수 있어야 한다.

---

## 8.2.3 `metadata.json`

권장 예시:

```
{
  "layer":"silver",
  "domain":"paper",
  "batch_id":"2026-04-01T10-30-00",
  "input_layer":"bronze/pubmed/batch=2026-04-01T10-30-00",
  "paper_count":110,
  "chunk_count":540,
  "chunk_policy":"abstract_sentence_window_v1",
  "created_at":"2026-04-01T10:40:10+09:00"
}
```

---

## 8.3 Gold 산출물 설계

## 8.3.1 `graph_claim.parquet`

Gold의 핵심 claim 데이터셋이다.

권장 컬럼:

- `batch_id`
- `claim_key`
- `paper_key`
- `pmid`
- `chunk_index`
- `source_sentence`
- `ingredient_id`
- `ingredient_name`
- `relation`
- `target`
- `normalized_summary`
- `claim_type`
- `evidence_direction`
- `confidence_score`
- `extraction_method`
- `extractor_version`
- `validator_version`

### 필요 이유

이 파일은 그래프 적재뿐 아니라, 품질 검수와 통계 분석, 검색 실험에서도 재사용 가능한 최종 데이터셋이어야 한다.

---

## 8.3.2 `claim_effect_map.parquet`

claim과 effect taxonomy의 연결 정보를 저장한다.

권장 컬럼:

- `claim_key`
- `effect_id`
- `effect_code`
- `confidence_score`

---

## 8.3.3 `claim_concern_map.parquet`

claim과 concern taxonomy의 연결 정보를 저장한다.

권장 컬럼:

- `claim_key`
- `concern_id`
- `concern_code`
- `confidence_score`

---

## 8.3.4 `metadata.json`

권장 예시:

```
{
  "layer":"gold",
  "domain":"claim",
  "batch_id":"2026-04-01T10-30-00",
  "input_layer":"silver/paper/batch=2026-04-01T10-30-00",
  "chunk_count":540,
  "claim_count":82,
  "extractor_version":"llm_claim_extractor_v3",
  "validator_version":"claim_validator_v2",
  "created_at":"2026-04-01T10:55:00+09:00"
}
```

---

## 9. 실행 모듈 구조 설계

실행 단위는 레이어별로 분리한다.

권장 구조:

```
pipeline/
├── bronze/pubmed/run_bronze.py
├── silver/paper/run_silver.py
├── gold/claim/run_gold.py
└── serving/neo4j/load_graph.py
```

---

## 9.1 `run_bronze.py`

### 역할

- 타겟 성분 로드
- PubMed query 생성
- PMID search
- XML fetch
- raw/parsed 데이터 저장

### 입력

- `target_ingredients.csv`
- 환경변수
- batch_id

### 출력

- `bronze/pubmed/batch=.../`

### 분리 이유

수집 단계는 downstream과 독립적으로 반복 수행될 수 있어야 한다.

검색 쿼리만 바꿔도 Bronze를 다시 만들 수 있어야 한다.

---

## 9.2 `run_silver.py`

### 역할

- Bronze 논문 데이터 로드
- abstract 정제
- chunk 생성
- Silver 저장

### 입력

- Bronze batch 경로

### 출력

- `silver/paper/batch=.../`

### 분리 이유

chunking 정책 변경 시 Bronze는 그대로 두고 Silver만 재생성할 수 있어야 한다.

---

## 9.3 `run_gold.py`

### 역할

- Silver chunk 로드
- sentence split
- ingredient matching
- candidate filtering
- LLM claim extraction
- validation
- taxonomy mapping
- Gold 저장

### 입력

- Silver batch 경로

### 출력

- `gold/claim/batch=.../`

### 분리 이유

claim 추출 품질 실험은 빈번하게 일어날 가능성이 높다.

따라서 Gold는 Bronze/Silver와 분리된 독립 실험 단위여야 한다.

---

## 9.4 `load_graph.py`

### 역할

- Gold claim 데이터 로드
- Neo4j node/edge upsert
- 적재 결과 로그 저장

### 입력

- Gold batch 경로

### 출력

- Neo4j graph

### 분리 이유

graph schema는 변할 수 있으므로, Gold 생성과 graph load를 분리해야 한다.

---

## 10. DB 사용 전략

## 10.1 권장 원칙

레이어 저장소는 파일 기반으로 두고, DB는 운영/staging/load 용도로 사용한다.

즉:

- Bronze/Silver/Gold = 파일 기반 레이어 산출물
- PostgreSQL = 검수, staging, reference master, 서빙 보조
- Neo4j = graph serving 저장소

---

## 10.2 PostgreSQL의 역할

PostgreSQL은 다음 역할에 적합하다.

- ingredient master 조회
- taxonomy master 조회
- Gold 검수 테이블 적재
- graph ingest 전 staging
- 통계용 mart

### 이렇게 두는 이유

레이어 자체를 DB로만 운영하면 실험 결과와 운영 데이터가 섞이기 쉽다.

반면 파일 기반 레이어는 배치별 보존과 비교가 쉽다.

---

## 11. 배치 관리 전략

## 11.1 batch_id 규칙

배치는 날짜만이 아니라 시각까지 포함한 값으로 관리한다.

예:

```
2026-04-01T10-30-00
```

### 이유

같은 날 여러 번 실행될 수 있기 때문이다.

---

## 11.2 lineage 관리

각 레이어는 자신이 어떤 상위 배치를 입력으로 사용했는지 반드시 기록한다.

예:

- Bronze batch: `2026-04-01T10-30-00`
- Silver metadata에 Bronze batch 경로 기록
- Gold metadata에 Silver batch 경로 기록

### 이유

문제가 생겼을 때 upstream을 추적하기 위함이다.

---

## 12. provenance 설계 원칙

Gold의 claim은 반드시 아래를 추적할 수 있어야 한다.

- 어떤 논문에서 나왔는가
- 어떤 chunk에서 추출되었는가
- 어떤 source sentence에서 나왔는가
- 어떤 extractor version을 사용했는가
- 어떤 validator version을 사용했는가

### 이유

GraphRAG 기반 시스템에서는 추천 결과의 근거 설명 가능성이 중요하다.

따라서 claim provenance는 단순 디버깅 용도가 아니라 시스템 신뢰성의 핵심 요소다.

---

## 13. 리팩토링 적용 순서

전체를 한 번에 갈아엎기보다 아래 순서로 진행하는 것을 권장한다.

### 1단계: Bronze 파일 산출물 생성

현재 metadata 단계 로직을 유지하면서, DB 적재 전에 `search_log`, `paper_raw`, `raw_xml` 파일 저장 기능을 추가한다.

### 2단계: Silver를 DB 의존에서 분리

현재 chunk 단계가 `paper_metadata` 테이블이 아닌 Bronze 파일을 입력으로 읽도록 수정한다.

### 3단계: Gold를 독립 데이터셋으로 분리

현재 claim 단계가 `paper_chunk` 테이블 대신 Silver 파일을 읽어 `graph_claim` 파일을 생성하도록 수정한다.

### 4단계: DB load / graph load 분리

필요 시 Gold 파일을 PostgreSQL staging에 적재하거나 Neo4j에 적재하는 별도 스크립트를 추가한다.

### 5단계: Airflow/S3 연동

각 단계가 안정화되면 레이어 산출물을 S3에 적재하고 DAG로 orchestration 한다.

---

## 14. 기대 효과

이번 리팩토링을 통해 다음 효과를 기대할 수 있다.

### 14.1 재현성 향상

원천 수집 결과부터 claim 데이터셋까지 단계별로 보존되므로 재현 가능성이 높아진다.

### 14.2 검수 용이성 향상

각 단계 결과를 파일로 직접 열어 확인할 수 있어 품질 점검이 쉬워진다.

### 14.3 부분 재처리 가능

chunk 정책이나 claim extractor가 바뀌더라도 전체 수집을 다시 하지 않아도 된다.

### 14.4 운영 확장성 향상

S3, Airflow, Lambda, Docker 기반 자동화 구조와 잘 맞는다.

### 14.5 graph schema 변경 대응력 향상

Gold와 graph load를 분리함으로써 그래프 구조 변경 시 파이프라인 영향 범위를 줄일 수 있다.

---

## 15. 최종 설계 결론

본 프로젝트의 논문 추출 파이프라인은 다음과 같이 리팩토링하는 것이 적절하다.

### Bronze

PubMed 원천 수집 데이터 계층

메타데이터뿐 아니라 검색 컨텍스트, abstract 원문, raw XML까지 포함한다.

### Silver

논문 정제 텍스트 및 chunk 계층

LLM claim 추출의 직접 입력이 되는 텍스트 단위를 관리한다.

### Gold

그래프 적재 전 최종 claim 데이터셋 계층

ingredient / relation / target / taxonomy mapping / provenance를 포함한 정규화 결과를 저장한다.

### 별도 단계

Gold 이후 Neo4j 적재는 별도의 serving/load 단계로 분리한다.

---

## 16. 핵심 의사결정 요약

이번 설계에서 가장 중요한 결정은 두 가지다.

### 결정 1

Bronze를 단순 논문 메타데이터 계층이 아니라 **논문 원천 수집 데이터 계층**으로 정의한다.

### 결정 2

Gold는 **그래프용 정규화 claim 데이터셋**까지만 담당하고, 실제 graph load는 분리한다.

이 두 원칙을 지키면, 앞으로 시스템이 커져도 구조가 흔들리지 않는다.
