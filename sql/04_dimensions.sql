-- 04_dimensions.sql
-- dimension tables: month, grade, purpose, state

-- months
DROP TABLE IF EXISTS dw.dim_month CASCADE;
CREATE TABLE dw.dim_month AS
SELECT d::date                         AS month_start,
       EXTRACT(year FROM d)::int       AS year,
       EXTRACT(quarter FROM d)::int    AS quarter,
       EXTRACT(month FROM d)::int      AS month_num,
       to_char(d, 'Mon YYYY')          AS month_label,
       to_char(d, 'YYYY "Q"Q')         AS year_quarter
FROM generate_series('2015-01-01'::date, '2019-03-01'::date, interval '1 month') AS d;
ALTER TABLE dw.dim_month ADD PRIMARY KEY (month_start);

-- grades, A-B prime, C-D near-prime, E-G subprime
DROP TABLE IF EXISTS dw.dim_grade CASCADE;
CREATE TABLE dw.dim_grade AS
SELECT DISTINCT sub_grade,
       grade,
       ascii(grade) - 64 AS grade_rank,          -- A=1 ... G=7
       CASE WHEN grade IN ('A', 'B') THEN 'Prime'
            WHEN grade IN ('C', 'D') THEN 'Near-prime'
            ELSE 'Subprime' END AS risk_band
FROM stg.loans;
ALTER TABLE dw.dim_grade ADD PRIMARY KEY (sub_grade);

-- purposes, debt_consolidation -> Debt Consolidation for labels
DROP TABLE IF EXISTS dw.dim_purpose CASCADE;
CREATE TABLE dw.dim_purpose AS
SELECT DISTINCT purpose,
       initcap(replace(purpose, '_', ' ')) AS purpose_label
FROM stg.loans;
ALTER TABLE dw.dim_purpose ADD PRIMARY KEY (purpose);

-- states mapped to census regions
DROP TABLE IF EXISTS dw.dim_state CASCADE;
CREATE TABLE dw.dim_state (state_code text PRIMARY KEY, region text NOT NULL);
INSERT INTO dw.dim_state (state_code, region)
SELECT s, 'Northeast' FROM unnest(ARRAY['CT','ME','MA','NH','RI','VT','NJ','NY','PA']) s
UNION ALL SELECT s, 'Midwest' FROM unnest(ARRAY['IL','IN','MI','OH','WI','IA','KS','MN','MO','NE','ND','SD']) s
UNION ALL SELECT s, 'South' FROM unnest(ARRAY['DE','FL','GA','MD','NC','SC','VA','DC','WV','AL','KY','MS','TN','AR','LA','OK','TX']) s
UNION ALL SELECT s, 'West' FROM unnest(ARRAY['AZ','CO','ID','MT','NV','NM','UT','WY','AK','CA','HI','OR','WA']) s;

-- checks
SELECT COUNT(*) FROM dw.dim_month;     -- 51
SELECT * FROM dw.dim_grade ORDER BY sub_grade;
SELECT * FROM dw.dim_purpose ORDER BY purpose;
SELECT region, COUNT(*) FROM dw.dim_state GROUP BY 1;   -- 51 incl DC
