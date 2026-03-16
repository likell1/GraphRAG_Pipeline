#1. 데이터가 정상적으로 들어갔는지 확인
SELECT COUNT(*) 
FROM extracted_claim;


#2. claim 전체 보기
SELECT claim_id, normalized_summary
FROM extracted_claim
ORDER BY claim_id;


#3. 성분 분포 확인
SELECT
  CASE
    WHEN normalized_summary ILIKE 'Tranexamic acid %' THEN 'Tranexamic acid'
    WHEN normalized_summary ILIKE 'Niacinamide %' THEN 'Niacinamide'
    WHEN normalized_summary ILIKE 'Panthenol %' THEN 'Panthenol'
    WHEN normalized_summary ILIKE 'Ceramide %' THEN 'Ceramide'
    WHEN normalized_summary ILIKE 'Salicylic acid %' THEN 'Salicylic acid'
    ELSE 'OTHER'
  END AS ingredient,
  COUNT(*) AS cnt
FROM extracted_claim
GROUP BY 1
ORDER BY cnt DESC;


#4. Relation 분포 확인
SELECT
  CASE
    WHEN normalized_summary ILIKE '% is_well_tolerated_for %' THEN 'is_well_tolerated_for'
    WHEN normalized_summary ILIKE '% is_safe_for %' THEN 'is_safe_for'
    WHEN normalized_summary ILIKE '% improves %' THEN 'improves'
    WHEN normalized_summary ILIKE '% reduces %' THEN 'reduces'
    WHEN normalized_summary ILIKE '% prevents %' THEN 'prevents'
    WHEN normalized_summary ILIKE '% increases %' THEN 'increases'
    ELSE 'other'
  END AS relation,
  COUNT(*) AS cnt
FROM extracted_claim
GROUP BY 1
ORDER BY cnt DESC;


#5. 중복 Claim 확인
SELECT normalized_summary, COUNT(*) AS cnt
FROM extracted_claim
GROUP BY normalized_summary
HAVING COUNT(*) > 1
ORDER BY cnt DESC;


#6. Ingredient 파싱 문제 확인
SELECT
  split_part(normalized_summary, ' ', 1) AS ingredient_guess,
  COUNT(*) AS cnt
FROM extracted_claim
GROUP BY 1
ORDER BY cnt DESC;


#7. 이상 target 탐지
SELECT claim_id, normalized_summary
FROM extracted_claim
WHERE normalized_summary ~* 
'(cancer|carcinoma|tumor|blood loss|perioperative|surgery|microemulsion|drug delivery|gene expression)'
ORDER BY claim_id;


#8. Cosmetic target 분포
SELECT
  CASE
    WHEN normalized_summary ILIKE '%melasma%' THEN 'melasma'
    WHEN normalized_summary ILIKE '%hyperpigmentation%' THEN 'hyperpigmentation'
    WHEN normalized_summary ILIKE '%photoaging%' THEN 'photoaging'
    WHEN normalized_summary ILIKE '%erythema%' THEN 'erythema'
    WHEN normalized_summary ILIKE '%acne%' THEN 'acne'
    WHEN normalized_summary ILIKE '%tolerability%' THEN 'tolerability'
    ELSE 'other'
  END AS concern,
  COUNT(*) AS cnt
FROM extracted_claim
GROUP BY 1
ORDER BY cnt DESC;


#9 최종 GraphRAG 검증
SELECT
  ingredient,
  relation,
  target,
  COUNT(*) AS evidence_count
FROM (
  SELECT
    split_part(normalized_summary,' ',1) AS ingredient,
    split_part(normalized_summary,' ',2) AS relation,
    substring(normalized_summary from position(' ' in normalized_summary)+1) AS rest,
    normalized_summary
  FROM extracted_claim
) t,
LATERAL (
  SELECT substring(rest from position(' ' in rest)+1) AS target
) x
GROUP BY ingredient, relation, target
ORDER BY evidence_count DESC;