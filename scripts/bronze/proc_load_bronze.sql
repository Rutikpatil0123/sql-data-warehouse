-- load_bronze.sql
USE bronze;

-- Track overall pipeline start time
SET @pipeline_start = NOW();
SELECT '==================================================' AS '';
SELECT '🚀 STARTING BRONZE LAYER INGESTION PIPELINE...' AS '';
SELECT CONCAT('Timestamp: ', @pipeline_start) AS '';
SELECT '==================================================' AS '';

-- ==========================================
-- 1. TRUNCATE TABLES
-- ==========================================
SET @step_start = NOW();
SELECT '🧹 Truncating bronze tables for clean refresh...' AS '';

TRUNCATE TABLE bronze.cmr_cust_info;
TRUNCATE TABLE bronze.cmr_prd_info;
TRUNCATE TABLE bronze.cmr_sales_details;
TRUNCATE TABLE bronze.erp_cust_az12;
TRUNCATE TABLE bronze.erp_loc_a101;
TRUNCATE TABLE bronze.erp_px_cat_g1v2;

SELECT CONCAT('   -> Truncate completed in ', TIMESTAMPDIFF(SECOND, @step_start, NOW()), ' seconds.') AS '';


-- ==========================================
-- 2. LOAD CUSTOMER INFO
-- ==========================================
SET @step_start = NOW();
SELECT '📥 Loading Customer Info (cust_info.csv)...' AS '';

LOAD DATA INFILE '/var/lib/mysql-files/data/cust_info.csv'
INTO TABLE bronze.cmr_cust_info
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS
(@cst_id, cst_key, cst_firstname, cst_lastname, @cst_marital_status, @cst_gndr, @cst_create_data)
SET 
    cst_id = NULLIF(@cst_id, ''),
    cst_marital_status = NULLIF(TRIM(@cst_marital_status), ''),
    cst_gndr = NULLIF(TRIM(@cst_gndr), ''),
    cst_create_data = NULLIF(TRIM(@cst_create_data), '');

SELECT CONCAT('   -> cmr_cust_info loaded in ', TIMESTAMPDIFF(SECOND, @step_start, NOW()), ' seconds.') AS '';


-- ==========================================
-- 3. LOAD PRODUCT INFO
-- ==========================================
SET @step_start = NOW();
SELECT '📥 Loading Product Info (prd_info.csv)...' AS '';

LOAD DATA INFILE '/var/lib/mysql-files/data/prd_info.csv'
INTO TABLE bronze.cmr_prd_info
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS
(@prd_id, prd_key, prd_nm, @prd_cost, @prd_line, @prd_start_dt, @prd_end_dt)
SET 
    prd_id = NULLIF(@prd_id, ''),
    prd_cost = NULLIF(@prd_cost, ''),
    prd_line = NULLIF(TRIM(@prd_line), ''),
    prd_start_dt = NULLIF(TRIM(@prd_start_dt), ''),
    prd_end_dt = NULLIF(TRIM(@prd_end_dt), '');

SELECT CONCAT('   -> cmr_prd_info loaded in ', TIMESTAMPDIFF(SECOND, @step_start, NOW()), ' seconds.') AS '';


-- ==========================================
-- 4. LOAD SALES DETAILS
-- ==========================================
SET @step_start = NOW();
SELECT '📥 Loading Sales Details (sales_details.csv)...' AS '';

LOAD DATA INFILE '/var/lib/mysql-files/data/sales_details.csv'
INTO TABLE bronze.cmr_sales_details
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS
(sls_ord_num, sls_prd_key, @sls_cust_id, @sls_order_dt, @sls_ship_dt, @sls_due_dt, @sls_sales, @sls_quantity, @sls_price)
SET 
    sls_cust_id = NULLIF(@sls_cust_id, ''),
    sls_order_dt = NULLIF(@sls_order_dt, ''),
    sls_ship_dt = NULLIF(@sls_ship_dt, ''),
    sls_due_dt = NULLIF(@sls_due_dt, ''),
    sls_sales = NULLIF(@sls_sales, ''),
    sls_quantity = NULLIF(@sls_quantity, ''),
    sls_price = NULLIF(@sls_price, '');

SELECT CONCAT('   -> cmr_sales_details loaded in ', TIMESTAMPDIFF(SECOND, @step_start, NOW()), ' seconds.') AS '';


-- ==========================================
-- 5. LOAD ERP CUSTOMER AZ12
-- ==========================================
SET @step_start = NOW();
SELECT '📥 Loading ERP Customer AZ12 (CUST_AZ12.csv)...' AS '';

LOAD DATA INFILE '/var/lib/mysql-files/data/CUST_AZ12.csv'
INTO TABLE bronze.erp_cust_az12
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS
(cid, @bdate, @gen)
SET 
    bdate = NULLIF(TRIM(@bdate), ''),
    gen = NULLIF(TRIM(@gen), '');

SELECT CONCAT('   -> erp_cust_az12 loaded in ', TIMESTAMPDIFF(SECOND, @step_start, NOW()), ' seconds.') AS '';


-- ==========================================
-- 6. LOAD ERP LOCATION A101
-- ==========================================
SET @step_start = NOW();
SELECT '📥 Loading ERP Location A101 (LOC_A101.csv)...' AS '';

LOAD DATA INFILE '/var/lib/mysql-files/data/LOC_A101.csv'
INTO TABLE bronze.erp_loc_a101
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS
(cid, @cntry)
SET 
    cntry = NULLIF(TRIM(@cntry), '');

SELECT CONCAT('   -> erp_loc_a101 loaded in ', TIMESTAMPDIFF(SECOND, @step_start, NOW()), ' seconds.') AS '';


-- ==========================================
-- 7. LOAD ERP PRODUCT CATEGORY G1V2
-- ==========================================
SET @step_start = NOW();
SELECT '📥 Loading ERP Product Category (PX_CAT_G1V2.csv)...' AS '';

LOAD DATA INFILE '/var/lib/mysql-files/data/PX_CAT_G1V2.csv'
INTO TABLE bronze.erp_px_cat_g1v2
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS
(id, @cat, @subcat, @maintenance)
SET 
    cat = NULLIF(TRIM(@cat), ''),
    subcat = NULLIF(TRIM(@subcat), ''),
    maintenance = NULLIF(TRIM(@maintenance), '');

SELECT CONCAT('   -> erp_px_cat_g1v2 loaded in ', TIMESTAMPDIFF(SECOND, @step_start, NOW()), ' seconds.') AS '';


-- ==========================================
-- PIPELINE COMPLETION SUMMARY
-- ==========================================
SELECT '==================================================' AS '';
SELECT '✨ BRONZE LAYER PIPELINE COMPLETED SUCCESSFULLY!' AS '';
SELECT CONCAT('Total Execution Time: ', TIMESTAMPDIFF(SECOND, @pipeline_start, NOW()), ' seconds.') AS '';
SELECT '==================================================' AS '';