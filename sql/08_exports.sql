-- 08_exports.sql
-- tableau public can't connect to postgres so the marts go out as csv.
-- in pgAdmin: run one line at a time, Save results to file, save in data\export

SELECT * FROM mart.loan_monthly;          -- save as loan_monthly.csv
SELECT * FROM mart.kpi_monthly;           -- save as kpi_monthly.csv
SELECT * FROM mart.vintage_curve;         -- save as vintage_curve.csv
SELECT * FROM mart.grade_risk;            -- save as grade_risk.csv
SELECT * FROM mart.expected_loss;         -- save as expected_loss.csv
SELECT * FROM mart.risk_adjusted_yield;   -- save as risk_adjusted_yield.csv
SELECT * FROM mart.key_findings;          -- save as key_findings.csv

-- or from psql:
-- \copy (SELECT * FROM mart.loan_monthly)        TO 'data/export/loan_monthly.csv'        WITH (FORMAT csv, HEADER true)
-- \copy (SELECT * FROM mart.kpi_monthly)         TO 'data/export/kpi_monthly.csv'         WITH (FORMAT csv, HEADER true)
-- \copy (SELECT * FROM mart.vintage_curve)       TO 'data/export/vintage_curve.csv'       WITH (FORMAT csv, HEADER true)
-- \copy (SELECT * FROM mart.grade_risk)          TO 'data/export/grade_risk.csv'          WITH (FORMAT csv, HEADER true)
-- \copy (SELECT * FROM mart.expected_loss)       TO 'data/export/expected_loss.csv'       WITH (FORMAT csv, HEADER true)
-- \copy (SELECT * FROM mart.risk_adjusted_yield) TO 'data/export/risk_adjusted_yield.csv' WITH (FORMAT csv, HEADER true)
-- \copy (SELECT * FROM mart.key_findings)        TO 'data/export/key_findings.csv'        WITH (FORMAT csv, HEADER true)
