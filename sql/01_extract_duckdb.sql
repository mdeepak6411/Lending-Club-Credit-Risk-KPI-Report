-- 01_extract_duckdb.sql
-- run this one in DuckDB, not Postgres.
-- the Kaggle csv has a few broken rows (bad quotes, summary lines at the end)
-- that Postgres COPY fails on, duckdb can skip them with ignore_errors.
-- open cmd in the project folder, run duckdb, paste the query.

-- 2015-2018 only and just the columns I need.
-- everything stays text, cleaning happens in 03
COPY (
  SELECT id, loan_amnt, funded_amnt, term, int_rate, installment,
         grade, sub_grade, emp_length, home_ownership, annual_inc,
         verification_status, issue_d, loan_status, purpose, addr_state,
         dti, fico_range_low, fico_range_high, application_type,
         out_prncp, total_pymnt, total_rec_prncp, total_rec_int,
         total_rec_late_fee, recoveries, collection_recovery_fee,
         last_pymnt_d, last_pymnt_amnt
  FROM read_csv('data/accepted_2007_to_2018Q4.csv',
                all_varchar = true, header = true, ignore_errors = true)
  WHERE right(issue_d, 4) IN ('2015', '2016', '2017', '2018')
) TO 'data/lc_loans_2015_2018.csv' (HEADER, DELIMITER ',');

-- should be 1794323
SELECT COUNT(*) FROM 'data/lc_loans_2015_2018.csv';
