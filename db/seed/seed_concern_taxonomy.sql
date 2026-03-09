INSERT INTO concern_taxonomy (
    concern_code,
    concern_name_en,
    concern_name_ko,
    concern_group,
    description
)
VALUES
('ACNE','Acne','여드름','acne','Inflammatory or non-inflammatory acne'),
('COMEDONES','Comedones','면포','acne','Blackheads and whiteheads'),
('OILY_SKIN','Oily skin','지성 피부','oil','Excess sebum production'),
('SENSITIVE_SKIN','Sensitive skin','민감성 피부','sensitivity','Skin easily irritated'),
('REDNESS','Redness','붉은기','sensitivity','Inflammation related redness'),
('IRRITATED_SKIN','Irritated skin','자극 피부','sensitivity','Burning or stinging skin'),
('DRY_SKIN','Dry skin','건성 피부','dryness','Lack of moisture in skin'),
('DEHYDRATED_SKIN','Dehydrated skin','수분 부족 피부','dryness','Low water content in skin'),
('BARRIER_DAMAGE','Skin barrier damage','피부 장벽 손상','barrier','Damaged skin barrier function'),
('HYPERPIGMENTATION','Hyperpigmentation','색소침착','pigmentation','Melanin overproduction'),
('DULLNESS','Dullness','피부 톤 저하','pigmentation','Uneven skin tone'),
('AGING_SIGNS','Aging signs','노화 징후','aging','Wrinkles and loss of elasticity'),
('ATOPIC_PRONE','Atopic-prone skin','아토피 피부 경향','sensitivity','Skin prone to atopic dermatitis'),
('ROSACEA_PRONE','Rosacea-prone skin','주사 피부 경향','sensitivity','Skin prone to rosacea'),
('POST_ACNE_MARKS','Post-acne marks','여드름 자국','pigmentation','Marks left after acne');