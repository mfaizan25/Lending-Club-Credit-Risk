-- ============================================================================
-- Exploratory Data Analysis (EDA)
-- Run before building business-question queries, to understand data quality,
-- date coverage, and distributions ahead of the actual analysis.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Null check on key columns used across the business questions
-- Confirms whether any column relied on later has hidden missing data
-- beyond the one known excluded row (loan_id 96387212, missing zip_code).
-- ----------------------------------------------------------------------------
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN g.grade IS NULL THEN 1 ELSE 0 END)              AS null_grade,
    SUM(CASE WHEN f.int_rate IS NULL THEN 1 ELSE 0 END)            AS null_int_rate,
    SUM(CASE WHEN b.annual_inc IS NULL THEN 1 ELSE 0 END)          AS null_income,
    SUM(CASE WHEN b.dti IS NULL THEN 1 ELSE 0 END)                 AS null_dti,
    SUM(CASE WHEN b.fico_range_low IS NULL THEN 1 ELSE 0 END)      AS null_fico,
    SUM(CASE WHEN geo.addr_state IS NULL THEN 1 ELSE 0 END)        AS null_state
FROM lc.fact_loan f
JOIN lc.dim_borrower b   ON f.borrower_key = b.borrower_key
JOIN lc.dim_grade g      ON f.grade_key = g.grade_key
JOIN lc.dim_geography geo ON f.geo_key = geo.geo_key;

-- ----------------------------------------------------------------------------
-- 2. Distinct loan_status values and their frequency
-- Needed to correctly define what counts as "default" vs "ongoing" vs
-- "paid off" across every business question in this project.
-- ----------------------------------------------------------------------------
SELECT
    loan_status,
    COUNT(*) AS cnt
FROM lc.fact_loan
GROUP BY loan_status
ORDER BY cnt DESC;

-- ----------------------------------------------------------------------------
-- 3. Date range covered by the dataset
-- Confirms the span of origination dates available for vintage/cohort
-- analysis (Business Question 2).
-- ----------------------------------------------------------------------------
SELECT
    MIN(issue_date) AS earliest_loan,
    MAX(issue_date) AS latest_loan
FROM lc.fact_loan;

-- ----------------------------------------------------------------------------
-- 4. Loan volume by grade
-- Sanity check against Business Question 1's output — confirms grade
-- distribution before analyzing pricing/default patterns.
-- ----------------------------------------------------------------------------
SELECT
    g.grade,
    COUNT(*) AS loan_count
FROM lc.fact_loan f
JOIN lc.dim_grade g ON f.grade_key = g.grade_key
GROUP BY g.grade
ORDER BY g.grade;

-- ----------------------------------------------------------------------------
-- 5. Distribution stats on key continuous variables
-- Checks for outliers or data entry errors in income, DTI, and interest
-- rate before using them in downstream analysis.
-- ----------------------------------------------------------------------------
SELECT
    MIN(b.annual_inc) AS min_income, MAX(b.annual_inc) AS max_income, AVG(b.annual_inc) AS avg_income,
    MIN(b.dti) AS min_dti,           MAX(b.dti) AS max_dti,           AVG(b.dti) AS avg_dti,
    MIN(f.int_rate) AS min_rate,     MAX(f.int_rate) AS max_rate,     AVG(f.int_rate) AS avg_rate
FROM lc.fact_loan f
JOIN lc.dim_borrower b ON f.borrower_key = b.borrower_key;
