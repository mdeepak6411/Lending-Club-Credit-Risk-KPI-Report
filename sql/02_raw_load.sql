-- 02_raw_load.sql
-- schemas + raw table. raw is loaded as-is (all text) and never edited.

CREATE SCHEMA IF NOT EXISTS raw;    -- source data as text
CREATE SCHEMA IF NOT EXISTS stg;    -- cleaned
CREATE SCHEMA IF NOT EXISTS dw;     -- star schema
CREATE SCHEMA IF NOT EXISTS mart;   -- views for tableau

DROP TABLE IF EXISTS raw.lc_loans;
CREATE TABLE raw.lc_loans (
  id text, loan_amnt text, funded_amnt text, term text, int_rate text,
  installment text, grade text, sub_grade text, emp_length text,
  home_ownership text, annual_inc text, verification_status text,
  issue_d text, loan_status text, purpose text, addr_state text,
  dti text, fico_range_low text, fico_range_high text,
  application_type text, out_prncp text, total_pymnt text,
  total_rec_prncp text, total_rec_int text, total_rec_late_fee text,
  recoveries text, collection_recovery_fee text,
  last_pymnt_d text, last_pymnt_amnt text
);

-- loaded data/lc_loans_2015_2018.csv with pgAdmin Import/Export (csv, header on)
-- or from psql:
-- \copy raw.lc_loans FROM 'data/lc_loans_2015_2018.csv' WITH (FORMAT csv, HEADER true)

-- checks
-- 1794323 in total
SELECT right(issue_d, 4) AS issue_year, COUNT(*) AS loans
FROM raw.lc_loans GROUP BY 1 ORDER BY 1;

-- issue_d looks like Dec-2015, term has a leading space
SELECT * FROM raw.lc_loans LIMIT 5;
SELECT DISTINCT term FROM raw.lc_loans;

-- statuses to map in 03
SELECT loan_status, COUNT(*) FROM raw.lc_loans GROUP BY 1 ORDER BY 2 DESC;

-- rate is stored as 13.56 not 0.1356 (5.31 to 30.99)
SELECT MIN(int_rate::numeric), MAX(int_rate::numeric) FROM raw.lc_loans;
