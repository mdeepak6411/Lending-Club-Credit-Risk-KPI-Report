-- 03_stg_loans.sql
-- raw text -> typed and cleaned columns

DROP TABLE IF EXISTS stg.loans CASCADE;
CREATE TABLE stg.loans AS
SELECT
  id::bigint                                               AS loan_id,
  NULLIF(trim(loan_amnt), '')::numeric(12,2)               AS loan_amount,
  NULLIF(trim(funded_amnt), '')::numeric(12,2)             AS funded_amount,
  -- ' 36 months' -> 36
  regexp_replace(term, '[^0-9]', '', 'g')::int             AS term_months,
  -- strip % in case it's there
  NULLIF(replace(trim(int_rate), '%', ''), '')::numeric(6,2) AS interest_rate_pct,
  NULLIF(trim(installment), '')::numeric(12,2)             AS installment,
  grade,
  sub_grade,
  -- '< 1 year' = 0, '10+ years' = 10, n/a = null
  CASE
    WHEN emp_length IS NULL OR trim(emp_length) IN ('', 'n/a') THEN NULL
    WHEN emp_length LIKE '<%' THEN 0
    ELSE regexp_replace(emp_length, '[^0-9]', '', 'g')::int
  END                                                      AS emp_length_years,
  upper(home_ownership)                                    AS home_ownership,
  NULLIF(trim(annual_inc), '')::numeric(14,2)              AS annual_income,
  verification_status,
  -- 'Dec-2015' -> 2015-12-01
  to_date(issue_d, 'Mon-YYYY')                             AS issue_month,
  loan_status                                              AS loan_status_raw,
  CASE
    WHEN loan_status = 'Fully Paid'                         THEN 'Fully Paid'
    WHEN loan_status IN ('Charged Off', 'Default')          THEN 'Charged Off'
    WHEN loan_status = 'Current'                            THEN 'Current'
    WHEN loan_status = 'In Grace Period'                    THEN 'In Grace Period'
    WHEN loan_status LIKE 'Late (16-30%'                    THEN 'Late 16-30 days'
    WHEN loan_status LIKE 'Late (31-120%'                   THEN 'Late 31-120 days'
    WHEN loan_status LIKE '%Status:Fully Paid'              THEN 'Fully Paid'
    WHEN loan_status LIKE '%Status:Charged Off'             THEN 'Charged Off'
    ELSE 'Other'
  END                                                      AS loan_status,
  purpose,
  addr_state                                               AS state_code,
  NULLIF(trim(dti), '')::numeric(8,2)                      AS dti,
  ((NULLIF(fico_range_low, '')::numeric
    + NULLIF(fico_range_high, '')::numeric) / 2)::int     AS fico_score,
  application_type,
  NULLIF(trim(out_prncp), '')::numeric(12,2)               AS outstanding_principal,
  NULLIF(trim(total_pymnt), '')::numeric(14,2)             AS total_paid,
  NULLIF(trim(total_rec_prncp), '')::numeric(12,2)         AS principal_received,
  NULLIF(trim(total_rec_int), '')::numeric(12,2)           AS interest_received,
  NULLIF(trim(total_rec_late_fee), '')::numeric(12,2)      AS late_fees_received,
  NULLIF(trim(recoveries), '')::numeric(12,2)              AS recoveries,
  NULLIF(trim(collection_recovery_fee), '')::numeric(12,2) AS collection_fee,
  to_date(NULLIF(trim(last_pymnt_d), ''), 'Mon-YYYY')      AS last_payment_month,
  NULLIF(trim(last_pymnt_amnt), '')::numeric(12,2)         AS last_payment_amount
FROM raw.lc_loans
WHERE id ~ '^[0-9]+$';     -- skip anything that isn't a loan row

ALTER TABLE stg.loans ADD PRIMARY KEY (loan_id);

-- checks
-- nothing should land in 'Other'
SELECT loan_status, loan_status_raw, COUNT(*)
FROM stg.loans GROUP BY 1, 2 ORDER BY 1, 3 DESC;

-- ranges look ok?
SELECT MIN(issue_month), MAX(issue_month),
       MIN(interest_rate_pct), MAX(interest_rate_pct),
       MIN(fico_score), MAX(fico_score),
       COUNT(*) FILTER (WHERE annual_income IS NULL) AS missing_income
FROM stg.loans;
