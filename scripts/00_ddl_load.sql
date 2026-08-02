/* =====================================================================
   Loads the cleaned Lending Club CSV (output of scripts/00_trim_columns.py) into
   a staging table, then builds and populates a star schema:
   dim_grade, dim_borrower, dim_geography, fact_loan.

   PIPELINE STAGE: this runs AFTER the Python column-trim step
   (scripts/00_trim_columns.py) — input here is accepted_final.csv, already
   reduced to the 31 needed columns.

   NOTE: PLease Check the file path and adjust it according to your requirements

   ===================================================================== */

-- ---------------------------------------------------------------------
-- 0. Database and schema
-- ---------------------------------------------------------------------
IF DB_ID('lending_club') IS NULL
    CREATE DATABASE lending_club;
GO

USE lending_club;
GO

IF SCHEMA_ID('lc') IS NULL
    EXEC('CREATE SCHEMA lc');
GO

-- ---------------------------------------------------------------------
-- 1. Staging table — one column per field in accepted_final.csv.
--    Kept mostly as text/loosely typed since the source CSV has
--    text-formatted dates ('Dec-2015') and percentages ('13.5%') that
--    need parsing later, not at load time.
-- ---------------------------------------------------------------------
IF OBJECT_ID('lc.staging_loans', 'U') IS NOT NULL
    DROP TABLE lc.staging_loans;
GO

CREATE TABLE lc.staging_loans (
    loan_id                     BIGINT,
    loan_amnt                   DECIMAL(12,2),
    funded_amnt                 DECIMAL(12,2),
    term                        VARCHAR(20),
    int_rate                    VARCHAR(10),
    installment                 DECIMAL(12,2),
    grade                       VARCHAR(2),
    sub_grade                   VARCHAR(3),
    emp_length                  VARCHAR(20),
    home_ownership              VARCHAR(20),
    annual_inc                  DECIMAL(14,2),
    verification_status         VARCHAR(30),
    issue_d                     VARCHAR(10),
    loan_status                 VARCHAR(60),
    zip_code                    VARCHAR(10),
    addr_state                  VARCHAR(2),
    dti                         DECIMAL(8,2),
    delinq_2yrs                 INT,
    fico_range_low              INT,
    fico_range_high             INT,
    open_acc                    INT,
    pub_rec                     INT,
    revol_util                  VARCHAR(10),
    out_prncp                   DECIMAL(12,2),
    total_pymnt                 DECIMAL(12,2),
    total_rec_prncp             DECIMAL(12,2),
    total_rec_int               DECIMAL(12,2),
    recoveries                  DECIMAL(12,2),
    collection_recovery_fee     DECIMAL(12,2),
    last_pymnt_d                VARCHAR(10),
    last_pymnt_amnt             DECIMAL(12,2)
);
GO

-- ---------------------------------------------------------------------
-- 2. Bulk load the cleaned CSV.
--    Update FIELDTERMINATOR/ROWTERMINATOR if your export differs, and
--    point FROM at the actual path on the machine running this.
-- ---------------------------------------------------------------------
BULK INSERT lc.staging_loans
FROM 'C:\Users\Muhammad Faizan\accepted_2007_to_2018q4.csv\accepted_final.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    TABLOCK
);
GO

-- ---------------------------------------------------------------------
-- 3. dim_grade — one row per sub-grade (35 rows: 7 grades x 5 tiers).
-- ---------------------------------------------------------------------
IF OBJECT_ID('lc.dim_grade', 'U') IS NOT NULL
    DROP TABLE lc.dim_grade;
GO

CREATE TABLE lc.dim_grade (
    grade_key   INT IDENTITY(1,1) PRIMARY KEY,
    grade       VARCHAR(2)  NOT NULL,
    sub_grade   VARCHAR(3)  NOT NULL
);
GO

INSERT INTO lc.dim_grade (grade, sub_grade)
SELECT DISTINCT grade, sub_grade
FROM lc.staging_loans
WHERE grade IS NOT NULL AND sub_grade IS NOT NULL;
GO

-- ---------------------------------------------------------------------
-- 4. dim_geography — one row per distinct state/zip combination
--    (3,423 rows). One loan (id 96387212) has a NULL zip and is
--    deliberately excluded here rather than patched — documented,
--    not a bug.
-- ---------------------------------------------------------------------
IF OBJECT_ID('lc.dim_geography', 'U') IS NOT NULL
    DROP TABLE lc.dim_geography;
GO

CREATE TABLE lc.dim_geography (
    geo_key     INT IDENTITY(1,1) PRIMARY KEY,
    addr_state  VARCHAR(2)  NOT NULL,
    zip_code    VARCHAR(10) NOT NULL
);
GO

INSERT INTO lc.dim_geography (addr_state, zip_code)
SELECT DISTINCT addr_state, zip_code
FROM lc.staging_loans
WHERE addr_state IS NOT NULL AND zip_code IS NOT NULL;
GO

-- ---------------------------------------------------------------------
-- 5. dim_borrower — borrower-level attributes. NOT deduplicated: one
--    row per loan_id (2,260,668 rows), since this dataset has no
--    stable person-level identifier to dedupe borrowers against.
-- ---------------------------------------------------------------------
IF OBJECT_ID('lc.dim_borrower', 'U') IS NOT NULL
    DROP TABLE lc.dim_borrower;
GO

CREATE TABLE lc.dim_borrower (
    borrower_key            INT IDENTITY(1,1) PRIMARY KEY,
    loan_id                 BIGINT NOT NULL,
    annual_inc              DECIMAL(14,2),
    dti                     DECIMAL(8,2),
    emp_length              VARCHAR(20),
    home_ownership          VARCHAR(20),
    verification_status     VARCHAR(30),
    delinq_2yrs             INT,
    fico_range_low          INT,
    fico_range_high         INT,
    open_acc                INT,
    pub_rec                 INT,
    revol_util              VARCHAR(10)
);
GO

INSERT INTO lc.dim_borrower (
    loan_id, annual_inc, dti, emp_length, home_ownership,
    verification_status, delinq_2yrs, fico_range_low, fico_range_high,
    open_acc, pub_rec, revol_util
)
SELECT
    loan_id, annual_inc, dti, emp_length, home_ownership,
    verification_status, delinq_2yrs, fico_range_low, fico_range_high,
    open_acc, pub_rec, revol_util
FROM lc.staging_loans;
GO

-- ---------------------------------------------------------------------
-- 6. fact_loan — grain: one row per loan. Joins staging to all three
--    dims via their surrogate keys. The INNER JOIN to dim_geography
--    naturally drops the 1 NULL-zip loan (2,260,667 rows vs staging's
--    2,260,668) — documented exclusion, not accidental.
-- ---------------------------------------------------------------------
IF OBJECT_ID('lc.fact_loan', 'U') IS NOT NULL
    DROP TABLE lc.fact_loan;
GO

CREATE TABLE lc.fact_loan (
    loan_id                     BIGINT PRIMARY KEY,
    grade_key                   INT NOT NULL REFERENCES lc.dim_grade(grade_key),
    borrower_key                INT NOT NULL REFERENCES lc.dim_borrower(borrower_key),
    geo_key                     INT NOT NULL REFERENCES lc.dim_geography(geo_key),
    issue_date                  DATE,
    term                        VARCHAR(20),
    int_rate                    DECIMAL(6,3),
    loan_amnt                   DECIMAL(12,2),
    funded_amnt                 DECIMAL(12,2),
    installment                 DECIMAL(12,2),
    loan_status                 VARCHAR(60),
    out_prncp                   DECIMAL(12,2),
    total_pymnt                 DECIMAL(12,2),
    total_rec_prncp             DECIMAL(12,2),
    total_rec_int               DECIMAL(12,2),
    recoveries                  DECIMAL(12,2),
    collection_recovery_fee     DECIMAL(12,2),
    last_pymnt_d                VARCHAR(10),
    last_pymnt_amnt             DECIMAL(12,2)
);
GO

INSERT INTO lc.fact_loan (
    loan_id, grade_key, borrower_key, geo_key, issue_date, term,
    int_rate, loan_amnt, funded_amnt, installment, loan_status,
    out_prncp, total_pymnt, total_rec_prncp, total_rec_int,
    recoveries, collection_recovery_fee, last_pymnt_d, last_pymnt_amnt
)
SELECT
    s.loan_id,
    dg.grade_key,
    db.borrower_key,
    geo.geo_key,
    -- issue_d comes in as 'Dec-2015' text; parse to a real DATE,
    -- assuming the 1st of the month (day is never recorded in the
    -- source data).
    TRY_CONVERT(DATE, '01-' + s.issue_d, 106),
    s.term,
    -- int_rate arrives as text, sometimes with a trailing '%' —
    -- strip it before casting to numeric.
    TRY_CAST(REPLACE(s.int_rate, '%', '') AS DECIMAL(6,3)),
    s.loan_amnt,
    s.funded_amnt,
    s.installment,
    s.loan_status,
    s.out_prncp,
    s.total_pymnt,
    s.total_rec_prncp,
    s.total_rec_int,
    s.recoveries,
    s.collection_recovery_fee,
    s.last_pymnt_d,
    s.last_pymnt_amnt
FROM lc.staging_loans s
JOIN lc.dim_grade dg
    ON s.grade = dg.grade AND s.sub_grade = dg.sub_grade
JOIN lc.dim_borrower db
    ON s.loan_id = db.loan_id
JOIN lc.dim_geography geo
    ON s.addr_state = geo.addr_state AND s.zip_code = geo.zip_code;
GO

-- ---------------------------------------------------------------------
-- 7. Row-count sanity check — compare against documented counts
--    (staging: ~2,260,668 | dim_borrower: ~2,260,668 | dim_grade: 35 |
--    dim_geography: ~3,423 | fact_loan: ~2,260,667).
-- ---------------------------------------------------------------------
SELECT 'staging_loans' AS table_name, COUNT(*) AS row_count FROM lc.staging_loans
UNION ALL
SELECT 'dim_grade', COUNT(*) FROM lc.dim_grade
UNION ALL
SELECT 'dim_geography', COUNT(*) FROM lc.dim_geography
UNION ALL
SELECT 'dim_borrower', COUNT(*) FROM lc.dim_borrower
UNION ALL
SELECT 'fact_loan', COUNT(*) FROM lc.fact_loan;
