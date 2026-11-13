-- 05_fact_loan.sql
-- one row per loan + flags and loss amounts.
-- there's no charge-off date in the data so I'm using last payment + 5 months
-- (LC charges off at roughly 150 days past due)

DROP TABLE IF EXISTS dw.fact_loan CASCADE;
CREATE TABLE dw.fact_loan AS
WITH base AS (
  SELECT l.*,
         CASE WHEN l.loan_status = 'Charged Off'
              THEN (COALESCE(l.last_payment_month, l.issue_month) + interval '5 months')::date
         END AS charge_off_month
  FROM stg.loans l
)
SELECT
  loan_id, issue_month, sub_grade, purpose, state_code, term_months,
  loan_status, home_ownership, verification_status, emp_length_years,
  funded_amount, interest_rate_pct, installment, annual_income, dti, fico_score,
  outstanding_principal, principal_received, interest_received,
  late_fees_received, recoveries, collection_fee, last_payment_month,
  charge_off_month,
  CASE WHEN charge_off_month IS NOT NULL THEN
       (EXTRACT(year FROM charge_off_month) - EXTRACT(year FROM issue_month)) * 12
     + (EXTRACT(month FROM charge_off_month) - EXTRACT(month FROM issue_month))
  END::int                                                        AS mob_at_charge_off,
  (loan_status IN ('Fully Paid', 'Charged Off'))::int             AS is_resolved,
  (loan_status = 'Charged Off')::int                              AS is_charged_off,
  (loan_status IN ('Current', 'In Grace Period',
                   'Late 16-30 days', 'Late 31-120 days'))::int   AS is_active,
  (loan_status IN ('Late 16-30 days', 'Late 31-120 days'))::int   AS is_late,
  CASE WHEN loan_status = 'Charged Off'
       THEN GREATEST(funded_amount - principal_received, 0) ELSE 0 END AS charged_off_principal,
  CASE WHEN loan_status = 'Charged Off'
       THEN GREATEST(funded_amount - principal_received, 0)
            - (COALESCE(recoveries, 0) - COALESCE(collection_fee, 0))
       ELSE 0 END                                                AS net_loss
FROM base;

ALTER TABLE dw.fact_loan ADD PRIMARY KEY (loan_id);
ALTER TABLE dw.fact_loan ADD FOREIGN KEY (issue_month) REFERENCES dw.dim_month (month_start);
ALTER TABLE dw.fact_loan ADD FOREIGN KEY (sub_grade)   REFERENCES dw.dim_grade (sub_grade);
ALTER TABLE dw.fact_loan ADD FOREIGN KEY (purpose)     REFERENCES dw.dim_purpose (purpose);
CREATE INDEX ix_fact_issue_month ON dw.fact_loan (issue_month);
CREATE INDEX ix_fact_sub_grade   ON dw.fact_loan (sub_grade);
ANALYZE dw.fact_loan;

-- state FK last, this should return nothing first
-- (if it does, add those codes to dim_state)
SELECT DISTINCT state_code FROM dw.fact_loan
EXCEPT SELECT state_code FROM dw.dim_state;

ALTER TABLE dw.fact_loan ADD FOREIGN KEY (state_code) REFERENCES dw.dim_state (state_code);

-- row count should match staging
SELECT (SELECT COUNT(*) FROM stg.loans) AS stg_rows,
       (SELECT COUNT(*) FROM dw.fact_loan) AS fact_rows;
