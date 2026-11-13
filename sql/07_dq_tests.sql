-- 07_dq_tests.sql
-- data checks, all rows should say PASS

WITH t AS (
  SELECT 'raw and staging row counts match' AS test,
         (SELECT COUNT(*) FROM raw.lc_loans WHERE id ~ '^[0-9]+$')
       = (SELECT COUNT(*) FROM stg.loans) AS passed
  UNION ALL
  SELECT 'staging and fact row counts match',
         (SELECT COUNT(*) FROM stg.loans) = (SELECT COUNT(*) FROM dw.fact_loan)
  UNION ALL
  SELECT 'no unmapped loan statuses',
         NOT EXISTS (SELECT 1 FROM stg.loans WHERE loan_status = 'Other')
  UNION ALL
  SELECT 'every state code in dim_state',
         NOT EXISTS (SELECT 1 FROM dw.fact_loan f
                     LEFT JOIN dw.dim_state s USING (state_code)
                     WHERE s.state_code IS NULL)
  UNION ALL
  SELECT 'funded amount always positive',
         NOT EXISTS (SELECT 1 FROM dw.fact_loan WHERE funded_amount IS NULL OR funded_amount <= 0)
  UNION ALL
  SELECT 'interest rate between 5 and 31',
         NOT EXISTS (SELECT 1 FROM dw.fact_loan WHERE interest_rate_pct NOT BETWEEN 5 AND 31)
  UNION ALL
  SELECT 'issue month within 2015-2018',
         NOT EXISTS (SELECT 1 FROM dw.fact_loan
                     WHERE issue_month NOT BETWEEN '2015-01-01' AND '2018-12-01')
  UNION ALL
  SELECT 'charged-off loans have a charge-off month',
         NOT EXISTS (SELECT 1 FROM dw.fact_loan
                     WHERE is_charged_off = 1 AND charge_off_month IS NULL)
  UNION ALL
  SELECT 'mart funded total reconciles to fact',
         (SELECT SUM(funded_amount) FROM mart.loan_monthly)
       = (SELECT SUM(funded_amount) FROM dw.fact_loan)
  UNION ALL
  SELECT 'PD rises from grade A to G',
         (SELECT bool_and(pd >= prev_pd)
          FROM (SELECT pd, LAG(pd) OVER (ORDER BY grade) AS prev_pd
                FROM mart.grade_risk) x
          WHERE prev_pd IS NOT NULL)
  UNION ALL
  SELECT 'key findings has 3 rows',
         (SELECT COUNT(*) FROM mart.key_findings) = 3
)
SELECT test, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM t;
