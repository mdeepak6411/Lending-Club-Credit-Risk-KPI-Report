-- 06_marts.sql
-- views for tableau.
-- run in this order, expected_loss uses grade_risk and key_findings uses the others

DROP VIEW IF EXISTS mart.key_findings, mart.risk_adjusted_yield,
                    mart.expected_loss, mart.grade_risk, mart.vintage_curve,
                    mart.kpi_monthly, mart.loan_monthly CASCADE;

-- loan_monthly
-- month x grade x purpose x region x term. only sums here,
-- rates get rebuilt in tableau as sum(rate x amount) / sum(amount)
CREATE OR REPLACE VIEW mart.loan_monthly AS
SELECT f.issue_month,
       g.grade, g.risk_band, p.purpose_label, s.region, f.term_months,
       COUNT(*)                                       AS loans,
       SUM(f.funded_amount)                           AS funded_amount,
       SUM(f.funded_amount * f.interest_rate_pct)     AS rate_x_amount,
       SUM(f.fico_score)                              AS fico_sum,
       COUNT(f.fico_score)                            AS fico_count,
       SUM(f.is_resolved)                             AS resolved_loans,
       SUM(f.is_charged_off)                          AS charged_off_loans,
       SUM(f.is_active)                               AS active_loans,
       SUM(f.is_late)                                 AS late_loans,
       SUM(f.charged_off_principal)                   AS charged_off_principal,
       SUM(f.net_loss)                                AS net_loss,
       SUM(COALESCE(f.recoveries, 0) - COALESCE(f.collection_fee, 0)) AS net_recoveries,
       SUM(f.outstanding_principal)                   AS outstanding_principal,
       SUM(f.interest_received)                       AS interest_received
FROM dw.fact_loan f
JOIN dw.dim_grade   g USING (sub_grade)
JOIN dw.dim_purpose p USING (purpose)
LEFT JOIN dw.dim_state s USING (state_code)
GROUP BY 1, 2, 3, 4, 5, 6;

-- kpi_monthly: MoM, YoY, YTD, 3 month avg
CREATE OR REPLACE VIEW mart.kpi_monthly AS
WITH m AS (
  SELECT f.issue_month,
         COUNT(*)                                               AS loans,
         SUM(f.funded_amount)                                   AS funded,
         SUM(f.funded_amount * f.interest_rate_pct)
           / SUM(f.funded_amount)                               AS w_avg_rate,
         AVG(f.fico_score)                                      AS avg_fico,
         SUM(f.funded_amount) FILTER (WHERE g.risk_band = 'Subprime')
           / SUM(f.funded_amount)                               AS subprime_share
  FROM dw.fact_loan f
  JOIN dw.dim_grade g USING (sub_grade)
  GROUP BY f.issue_month
)
SELECT m.*,
       funded / NULLIF(LAG(funded) OVER w, 0) - 1                 AS funded_mom,
       funded / NULLIF(LAG(funded, 12) OVER w, 0) - 1             AS funded_yoy,
       SUM(funded) OVER (PARTITION BY date_trunc('year', issue_month)
                         ORDER BY issue_month)                    AS funded_ytd,
       AVG(funded) OVER (w ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS funded_3m_avg,
       RANK() OVER (PARTITION BY date_trunc('year', issue_month)
                    ORDER BY funded DESC)                         AS rank_in_year
FROM m
WINDOW w AS (ORDER BY issue_month);

-- vintage_curve: cumulative charge-off % by months on book.
-- generate_series fills months with no charge-offs so the lines don't have gaps
CREATE OR REPLACE VIEW mart.vintage_curve AS
WITH snap AS (
  SELECT MAX(last_payment_month) AS snapshot_month FROM dw.fact_loan
),
cohort AS (
  SELECT date_trunc('quarter', issue_month)::date AS vintage, term_months,
         SUM(funded_amount) AS funded
  FROM dw.fact_loan
  GROUP BY 1, 2
),
co AS (
  SELECT date_trunc('quarter', issue_month)::date AS vintage, term_months,
         mob_at_charge_off AS mob, SUM(charged_off_principal) AS co_principal
  FROM dw.fact_loan
  WHERE is_charged_off = 1
  GROUP BY 1, 2, 3
),
grid AS (
  SELECT c.vintage, c.term_months, c.funded, gs.mob
  FROM cohort c
  CROSS JOIN snap
  CROSS JOIN LATERAL generate_series(
      0,
      ((EXTRACT(year FROM snap.snapshot_month) - EXTRACT(year FROM c.vintage)) * 12
       + (EXTRACT(month FROM snap.snapshot_month) - EXTRACT(month FROM c.vintage)))::int
  ) AS gs(mob)
)
SELECT g.vintage,
       to_char(g.vintage, 'YYYY "Q"Q') AS vintage_label,
       g.term_months,
       g.mob AS months_on_book,
       SUM(COALESCE(co.co_principal, 0))
         OVER (PARTITION BY g.vintage, g.term_months ORDER BY g.mob) / g.funded
         AS cum_charge_off_rate
FROM grid g
LEFT JOIN co ON co.vintage = g.vintage
            AND co.term_months = g.term_months
            AND co.mob = g.mob;

-- grade_risk: PD and LGD by grade.
-- only 2015 36m loans, that's the only cohort that has fully run off
CREATE OR REPLACE VIEW mart.grade_risk AS
SELECT g.grade, g.risk_band,
       COUNT(*)                                                     AS loans,
       SUM(f.is_resolved)                                           AS resolved_loans,
       -- lifetime PD
       SUM(f.is_charged_off)::numeric / NULLIF(SUM(f.is_resolved), 0) AS pd,
       -- 12 month PD
       COUNT(*) FILTER (WHERE f.mob_at_charge_off <= 12)::numeric
         / COUNT(*)                                                 AS pd_12m,
       1 - SUM(COALESCE(f.recoveries, 0) - COALESCE(f.collection_fee, 0))
             / NULLIF(SUM(f.charged_off_principal), 0)              AS lgd,
       SUM(f.funded_amount * f.interest_rate_pct) / SUM(f.funded_amount) AS w_avg_rate
FROM dw.fact_loan f
JOIN dw.dim_grade g USING (sub_grade)
WHERE f.term_months = 36
  AND f.issue_month < '2016-01-01'
GROUP BY g.grade, g.risk_band;

-- expected_loss = EAD x PD x LGD on active loans.
-- using 12m PD for the headline, lifetime version is more of an upper bound
CREATE OR REPLACE VIEW mart.expected_loss AS
SELECT g.grade, s.region,
       SUM(f.outstanding_principal)                          AS ead,
       r.pd_12m, r.pd AS pd_lifetime, r.lgd,
       SUM(f.outstanding_principal) * r.pd_12m * r.lgd       AS expected_loss,
       SUM(f.outstanding_principal) * r.pd * r.lgd           AS expected_loss_lifetime
FROM dw.fact_loan f
JOIN dw.dim_grade  g USING (sub_grade)
LEFT JOIN dw.dim_state s USING (state_code)
JOIN mart.grade_risk r ON r.grade = g.grade
WHERE f.is_active = 1
  AND f.outstanding_principal > 0
GROUP BY g.grade, s.region, r.pd_12m, r.pd, r.lgd;

-- risk_adjusted_yield: interest earned vs losses by grade
-- (same 2015 36m cohort, as % of amount funded)
CREATE OR REPLACE VIEW mart.risk_adjusted_yield AS
SELECT g.grade, g.risk_band,
       COUNT(*)                                                    AS loans,
       SUM(f.funded_amount)                                        AS funded,
       SUM(f.funded_amount * f.interest_rate_pct)
         / SUM(f.funded_amount) / 100                              AS w_avg_rate,
       SUM(COALESCE(f.interest_received, 0) + COALESCE(f.late_fees_received, 0))
         / SUM(f.funded_amount)                                    AS income_pct,
       SUM(f.net_loss) / SUM(f.funded_amount)                      AS loss_pct,
       (SUM(COALESCE(f.interest_received, 0) + COALESCE(f.late_fees_received, 0))
         - SUM(f.net_loss)) / SUM(f.funded_amount)                 AS net_return_pct
FROM dw.fact_loan f
JOIN dw.dim_grade g USING (sub_grade)
WHERE f.term_months = 36
  AND f.issue_month < '2016-01-01'
  AND f.is_resolved = 1
GROUP BY g.grade, g.risk_band;

-- key_findings: 3 lines of text for the dashboard, built from the views above
CREATE OR REPLACE VIEW mart.key_findings AS
WITH ry AS (
  SELECT grade, net_return_pct, loss_pct,
         ROW_NUMBER() OVER (ORDER BY net_return_pct DESC) AS best_rn,
         ROW_NUMBER() OVER (ORDER BY net_return_pct ASC)  AS worst_rn
  FROM mart.risk_adjusted_yield
),
v24 AS (
  SELECT vintage_label, cum_charge_off_rate,
         ROW_NUMBER() OVER (ORDER BY cum_charge_off_rate DESC) AS worst_rn,
         ROW_NUMBER() OVER (ORDER BY cum_charge_off_rate ASC)  AS best_rn
  FROM mart.vintage_curve
  WHERE term_months = 36 AND months_on_book = 24
),
mix AS (
  SELECT MAX(subprime_share) FILTER (WHERE issue_month = '2018-12-01') AS s_now,
         MAX(subprime_share) FILTER (WHERE issue_month = '2017-12-01') AS s_prev
  FROM mart.kpi_monthly
)
SELECT 1 AS finding_no, 'Return' AS topic,
       format('Grade %s earned the best net return (%s%% of the amount lent). Grade %s earned the least (%s%%) after losing %s%%.',
              b.grade, to_char(b.net_return_pct * 100, 'FM990.0'),
              w.grade, to_char(w.net_return_pct * 100, 'FM990.0'),
              to_char(w.loss_pct * 100, 'FM990.0')) AS finding_text
FROM ry b CROSS JOIN ry w
WHERE b.best_rn = 1 AND w.worst_rn = 1
UNION ALL
SELECT 2, 'Vintage',
       format('After 24 months on book, the %s vintage had lost %s%% of the amount lent, against %s%% for %s.',
              w.vintage_label, to_char(w.cum_charge_off_rate * 100, 'FM990.0'),
              to_char(b.cum_charge_off_rate * 100, 'FM990.0'), b.vintage_label)
FROM v24 w CROSS JOIN v24 b
WHERE w.worst_rn = 1 AND b.best_rn = 1
UNION ALL
SELECT 3, 'Mix',
       format('Subprime (grades E-G) share of funding went from %s%% in Dec 2017 to %s%% in Dec 2018.',
              to_char(s_prev * 100, 'FM990.0'), to_char(s_now * 100, 'FM990.0'))
FROM mix
ORDER BY finding_no;

-- quick checks
SELECT * FROM mart.grade_risk ORDER BY grade;            -- PD should go up A to G
SELECT * FROM mart.risk_adjusted_yield ORDER BY grade;   -- rate around 0.07 - 0.29
SELECT * FROM mart.key_findings;
