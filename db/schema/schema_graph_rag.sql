-- =========================================================
-- Graph RAG for Cosmetic Ingredient Recommendation
-- PostgreSQL DDL v1
-- =========================================================

-- 선택: updated_at 자동 갱신용 함수
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- =========================================================
-- 1. Ingredient Master
-- =========================================================
CREATE TABLE IF NOT EXISTS ingredient_master (
    ingredient_id        BIGSERIAL PRIMARY KEY,
    canonical_name       TEXT NOT NULL,
    kcia_name_ko         TEXT,
    kcia_name_en         TEXT,
    cosing_name          TEXT,
    inci_name            TEXT,
    ingredient_type      TEXT,
    source_system        TEXT,
    is_active            BOOLEAN NOT NULL DEFAULT TRUE,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_ingredient_master_canonical_name UNIQUE (canonical_name)
);

CREATE INDEX IF NOT EXISTS idx_ingredient_master_canonical_name
    ON ingredient_master (canonical_name);

CREATE INDEX IF NOT EXISTS idx_ingredient_master_kcia_name_en
    ON ingredient_master (kcia_name_en);

CREATE INDEX IF NOT EXISTS idx_ingredient_master_cosing_name
    ON ingredient_master (cosing_name);

CREATE TRIGGER trg_ingredient_master_updated_at
BEFORE UPDATE ON ingredient_master
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();


-- =========================================================
-- 2. Ingredient Alias
-- =========================================================
CREATE TABLE IF NOT EXISTS ingredient_alias (
    alias_id             BIGSERIAL PRIMARY KEY,
    ingredient_id        BIGINT NOT NULL,
    alias_name           TEXT NOT NULL,
    alias_type           TEXT,         -- synonym / abbreviation / old_name / typo_variant
    language_code        TEXT DEFAULT 'en',
    normalized_key       TEXT,
    source               TEXT,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_ingredient_alias_ingredient
        FOREIGN KEY (ingredient_id)
        REFERENCES ingredient_master (ingredient_id)
        ON DELETE CASCADE,

    CONSTRAINT uq_ingredient_alias UNIQUE (ingredient_id, alias_name)
);

CREATE INDEX IF NOT EXISTS idx_ingredient_alias_alias_name
    ON ingredient_alias (alias_name);

CREATE INDEX IF NOT EXISTS idx_ingredient_alias_normalized_key
    ON ingredient_alias (normalized_key);

CREATE INDEX IF NOT EXISTS idx_ingredient_alias_ingredient_id
    ON ingredient_alias (ingredient_id);


-- =========================================================
-- 3. Effect Taxonomy
-- =========================================================
CREATE TABLE IF NOT EXISTS effect_taxonomy (
    effect_id            BIGSERIAL PRIMARY KEY,
    effect_code          TEXT NOT NULL,
    effect_name_en       TEXT NOT NULL,
    effect_name_ko       TEXT,
    effect_group         TEXT,
    description          TEXT,
    is_active            BOOLEAN NOT NULL DEFAULT TRUE,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_effect_taxonomy_code UNIQUE (effect_code),
    CONSTRAINT uq_effect_taxonomy_name_en UNIQUE (effect_name_en)
);

CREATE INDEX IF NOT EXISTS idx_effect_taxonomy_group
    ON effect_taxonomy (effect_group);

CREATE TRIGGER trg_effect_taxonomy_updated_at
BEFORE UPDATE ON effect_taxonomy
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();


-- =========================================================
-- 4. Concern Taxonomy
-- =========================================================
CREATE TABLE IF NOT EXISTS concern_taxonomy (
    concern_id           BIGSERIAL PRIMARY KEY,
    concern_code         TEXT NOT NULL,
    concern_name_en      TEXT NOT NULL,
    concern_name_ko      TEXT,
    concern_group        TEXT,
    description          TEXT,
    is_active            BOOLEAN NOT NULL DEFAULT TRUE,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_concern_taxonomy_code UNIQUE (concern_code),
    CONSTRAINT uq_concern_taxonomy_name_en UNIQUE (concern_name_en)
);

CREATE INDEX IF NOT EXISTS idx_concern_taxonomy_group
    ON concern_taxonomy (concern_group);

CREATE TRIGGER trg_concern_taxonomy_updated_at
BEFORE UPDATE ON concern_taxonomy
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();


-- =========================================================
-- 5. Concern-Effect Mapping
-- =========================================================
CREATE TABLE IF NOT EXISTS concern_effect_map (
    map_id               BIGSERIAL PRIMARY KEY,
    concern_id           BIGINT NOT NULL,
    effect_id            BIGINT NOT NULL,
    priority_score       NUMERIC(5,2),
    notes                TEXT,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_concern_effect_map_concern
        FOREIGN KEY (concern_id)
        REFERENCES concern_taxonomy (concern_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_concern_effect_map_effect
        FOREIGN KEY (effect_id)
        REFERENCES effect_taxonomy (effect_id)
        ON DELETE CASCADE,

    CONSTRAINT uq_concern_effect_map UNIQUE (concern_id, effect_id)
);

CREATE INDEX IF NOT EXISTS idx_concern_effect_map_concern_id
    ON concern_effect_map (concern_id);

CREATE INDEX IF NOT EXISTS idx_concern_effect_map_effect_id
    ON concern_effect_map (effect_id);



-- =========================================================
-- 6. Paper Metadata
-- =========================================================
CREATE TABLE IF NOT EXISTS paper_metadata (
    paper_id             BIGSERIAL PRIMARY KEY,
    title                TEXT NOT NULL,
    doi                  TEXT,
    pmid                 TEXT,
    pmcid                TEXT,
    journal              TEXT,
    publication_year     INT,
    authors              TEXT,
    abstract_text        TEXT,
    study_type           TEXT,   -- in_vitro / animal / clinical / review / systematic_review / meta_analysis
    evidence_level       TEXT,   -- low / medium / high or custom scale
    source_db            TEXT,   -- PubMed / PMC / Crossref / OpenAlex
    source_url           TEXT,
    language_code        TEXT DEFAULT 'en',
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 일반 unique index 사용
-- PostgreSQL에서는 UNIQUE 컬럼도 NULL 값은 여러 개 허용됨
CREATE UNIQUE INDEX IF NOT EXISTS uq_paper_metadata_doi
    ON paper_metadata (doi);

CREATE UNIQUE INDEX IF NOT EXISTS uq_paper_metadata_pmid
    ON paper_metadata (pmid);

CREATE UNIQUE INDEX IF NOT EXISTS uq_paper_metadata_pmcid
    ON paper_metadata (pmcid);

CREATE INDEX IF NOT EXISTS idx_paper_metadata_publication_year
    ON paper_metadata (publication_year);

CREATE INDEX IF NOT EXISTS idx_paper_metadata_study_type
    ON paper_metadata (study_type);

CREATE INDEX IF NOT EXISTS idx_paper_metadata_source_db
    ON paper_metadata (source_db);

CREATE TRIGGER trg_paper_metadata_updated_at
BEFORE UPDATE ON paper_metadata
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();


-- =========================================================
-- 7. Paper Chunk
-- =========================================================
CREATE TABLE IF NOT EXISTS paper_chunk (
    chunk_id             BIGSERIAL PRIMARY KEY,
    paper_id             BIGINT NOT NULL,
    section_type         TEXT,   -- title / abstract / introduction / methods / results / discussion / conclusion
    chunk_index          INT NOT NULL,
    chunk_text           TEXT NOT NULL,
    token_count          INT,
    char_count           INT,
    source_start_offset  INT,
    source_end_offset    INT,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_paper_chunk_paper
        FOREIGN KEY (paper_id)
        REFERENCES paper_metadata (paper_id)
        ON DELETE CASCADE,

    CONSTRAINT uq_paper_chunk UNIQUE (paper_id, section_type, chunk_index)
);

CREATE INDEX IF NOT EXISTS idx_paper_chunk_paper_id
    ON paper_chunk (paper_id);

CREATE INDEX IF NOT EXISTS idx_paper_chunk_section_type
    ON paper_chunk (section_type);


-- =========================================================
-- 8. Extracted Claim
-- =========================================================
CREATE TABLE IF NOT EXISTS extracted_claim (
    claim_id             BIGSERIAL PRIMARY KEY,
    paper_id             BIGINT NOT NULL,
    chunk_id             BIGINT,
    claim_text           TEXT NOT NULL,
    normalized_summary   TEXT,
    claim_type           TEXT,      -- efficacy / safety / mechanism / comparison
    evidence_direction   TEXT,      -- supports / contradicts / neutral
    confidence_score     NUMERIC(5,4),
    section_type         TEXT,
    extraction_method    TEXT,      -- llm / rule / manual
    source_sentence      TEXT,
    source_start_offset  INT,
    source_end_offset    INT,
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_extracted_claim_paper
        FOREIGN KEY (paper_id)
        REFERENCES paper_metadata (paper_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_extracted_claim_chunk
        FOREIGN KEY (chunk_id)
        REFERENCES paper_chunk (chunk_id)
        ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_extracted_claim_paper_id
    ON extracted_claim (paper_id);

CREATE INDEX IF NOT EXISTS idx_extracted_claim_chunk_id
    ON extracted_claim (chunk_id);

CREATE INDEX IF NOT EXISTS idx_extracted_claim_claim_type
    ON extracted_claim (claim_type);

CREATE INDEX IF NOT EXISTS idx_extracted_claim_evidence_direction
    ON extracted_claim (evidence_direction);


-- =========================================================
-- 9. Claim - Ingredient Map
-- =========================================================
CREATE TABLE IF NOT EXISTS claim_ingredient_map (
    id                   BIGSERIAL PRIMARY KEY,
    claim_id             BIGINT NOT NULL,
    ingredient_id        BIGINT NOT NULL,
    role_type            TEXT,       -- primary / comparator / combined_formula_component
    confidence_score     NUMERIC(5,4),
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_claim_ingredient_map_claim
        FOREIGN KEY (claim_id)
        REFERENCES extracted_claim (claim_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_claim_ingredient_map_ingredient
        FOREIGN KEY (ingredient_id)
        REFERENCES ingredient_master (ingredient_id)
        ON DELETE CASCADE,

    CONSTRAINT uq_claim_ingredient_map UNIQUE (claim_id, ingredient_id, role_type)
);

CREATE INDEX IF NOT EXISTS idx_claim_ingredient_map_claim_id
    ON claim_ingredient_map (claim_id);

CREATE INDEX IF NOT EXISTS idx_claim_ingredient_map_ingredient_id
    ON claim_ingredient_map (ingredient_id);


-- =========================================================
-- 10. Claim - Effect Map
-- =========================================================
CREATE TABLE IF NOT EXISTS claim_effect_map (
    id                   BIGSERIAL PRIMARY KEY,
    claim_id             BIGINT NOT NULL,
    effect_id            BIGINT NOT NULL,
    confidence_score     NUMERIC(5,4),
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_claim_effect_map_claim
        FOREIGN KEY (claim_id)
        REFERENCES extracted_claim (claim_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_claim_effect_map_effect
        FOREIGN KEY (effect_id)
        REFERENCES effect_taxonomy (effect_id)
        ON DELETE CASCADE,

    CONSTRAINT uq_claim_effect_map UNIQUE (claim_id, effect_id)
);

CREATE INDEX IF NOT EXISTS idx_claim_effect_map_claim_id
    ON claim_effect_map (claim_id);

CREATE INDEX IF NOT EXISTS idx_claim_effect_map_effect_id
    ON claim_effect_map (effect_id);


-- =========================================================
-- 11. Claim - Concern Map
-- =========================================================
CREATE TABLE IF NOT EXISTS claim_concern_map (
    id                   BIGSERIAL PRIMARY KEY,
    claim_id             BIGINT NOT NULL,
    concern_id           BIGINT NOT NULL,
    confidence_score     NUMERIC(5,4),
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_claim_concern_map_claim
        FOREIGN KEY (claim_id)
        REFERENCES extracted_claim (claim_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_claim_concern_map_concern
        FOREIGN KEY (concern_id)
        REFERENCES concern_taxonomy (concern_id)
        ON DELETE CASCADE,

    CONSTRAINT uq_claim_concern_map UNIQUE (claim_id, concern_id)
);

CREATE INDEX IF NOT EXISTS idx_claim_concern_map_claim_id
    ON claim_concern_map (claim_id);

CREATE INDEX IF NOT EXISTS idx_claim_concern_map_concern_id
    ON claim_concern_map (concern_id);