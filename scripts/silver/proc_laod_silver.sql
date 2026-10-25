DELIMITER //

CREATE PROCEDURE silver.load_silver_layer()
BEGIN
    DECLARE start_time DATETIME(6);
    DECLARE end_time DATETIME(6);
    DECLARE step_start DATETIME(6);
    DECLARE duration_sec DECIMAL(10, 3);

    SET start_time = NOW(6);
    
    SELECT '==================================================' AS Log_Message;
    SELECT CONCAT('Starting Full Silver Layer Load at ', start_time) AS Log_Message;
    SELECT '==================================================' AS Log_Message;

    -- -------------------------------------------------------------------------
    -- 1. Load silver.cmr_cust_info
    -- -------------------------------------------------------------------------
    SET step_start = NOW(6);
    SELECT '--- Loading silver.cmr_cust_info ---' AS Log_Message;

    TRUNCATE TABLE silver.cmr_cust_info;
    
    INSERT INTO silver.cmr_cust_info (
        cst_id, 
        cst_key, 
        cst_firstname, 
        cst_lastname, 
        cst_marital_status, 
        cst_gndr, 
        cst_create_data
    )
    SELECT 
        cst_id, 
        cst_key,
        TRIM(cst_firstname) AS cst_firstname,
        TRIM(cst_lastname) AS cst_lastname,
        CASE 
            WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
            WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
            ELSE 'n/a'
        END AS cst_marital_status,
        CASE
            WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
            WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
            ELSE 'n/a'
        END AS cst_gndr,
        cst_create_data
    FROM (
        SELECT 
            cst_id, 
            cst_key,
            cst_firstname,
            cst_lastname,
            cst_marital_status,
            cst_gndr,
            cst_create_data,
            ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_data DESC) AS flag_last
        FROM bronze.cmr_cust_info 
        WHERE cst_id IS NOT NULL
    ) t
    WHERE t.flag_last = 1;

    SELECT CONCAT('Completed silver.cmr_cust_info in ', TIMESTAMPDIFF(MICROSECOND, step_start, NOW(6)) / 1000000.0, ' seconds') AS Log_Message;


    -- -------------------------------------------------------------------------
    -- 2. Load silver.cmr_prd_info
    -- -------------------------------------------------------------------------
    SET step_start = NOW(6);
    SELECT '--- Loading silver.cmr_prd_info ---' AS Log_Message;

    TRUNCATE TABLE silver.cmr_prd_info;

    INSERT INTO silver.cmr_prd_info (
        prd_id,
        cat_id,
        prd_key,
        prd_nm,
        prd_cost,
        prd_line,
        prd_start_dt,
        prd_end_dt
    )
    SELECT
        prd_id,
        REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,
        SUBSTRING(prd_key, 7, LENGTH(prd_key)) AS prd_key,
        prd_nm,
        COALESCE(prd_cost, 0) AS prd_cost,
        CASE 
            WHEN UPPER(TRIM(prd_line)) = 'M' THEN 'Mountain'
            WHEN UPPER(TRIM(prd_line)) = 'R' THEN 'Road'
            WHEN UPPER(TRIM(prd_line)) = 'S' THEN 'Other Sales'
            WHEN UPPER(TRIM(prd_line)) = 'T' THEN 'Touring'
            ELSE 'n/a'
        END AS prd_line,
        CAST(prd_start_dt AS DATE) AS prd_start_dt,
        CAST(
            LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt) - INTERVAL 1 DAY 
            AS DATE
        ) AS prd_end_dt
    FROM bronze.cmr_prd_info;

    SELECT CONCAT('Completed silver.cmr_prd_info in ', TIMESTAMPDIFF(MICROSECOND, step_start, NOW(6)) / 1000000.0, ' seconds') AS Log_Message;


    -- -------------------------------------------------------------------------
    -- 3. Load silver.cmr_sales_details
    -- -------------------------------------------------------------------------
    SET step_start = NOW(6);
    SELECT '--- Loading silver.cmr_sales_details ---' AS Log_Message;

    TRUNCATE TABLE silver.cmr_sales_details;

    INSERT INTO silver.cmr_sales_details (
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,
        sls_order_dt,
        sls_ship_dt,
        sls_due_dt,
        sls_sales,
        sls_quantity,
        sls_price
    )
    SELECT
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,
        CASE
            WHEN sls_order_dt IS NULL OR sls_order_dt = 0 OR CHAR_LENGTH(CAST(sls_order_dt AS CHAR)) != 8 THEN NULL
            ELSE STR_TO_DATE(CAST(sls_order_dt AS CHAR), '%Y%m%d')
        END AS sls_order_dt,
        CASE
            WHEN sls_ship_dt IS NULL OR sls_ship_dt = 0 OR CHAR_LENGTH(CAST(sls_ship_dt AS CHAR)) != 8 THEN NULL
            ELSE STR_TO_DATE(CAST(sls_ship_dt AS CHAR), '%Y%m%d')
        END AS sls_ship_dt,
        CASE
            WHEN sls_due_dt IS NULL OR sls_due_dt = 0 OR CHAR_LENGTH(CAST(sls_due_dt AS CHAR)) != 8 THEN NULL
            ELSE STR_TO_DATE(CAST(sls_due_dt AS CHAR), '%Y%m%d')
        END AS sls_due_dt,
        CASE
            WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != (sls_quantity * ABS(sls_price))
                THEN sls_quantity * ABS(sls_price)
            ELSE sls_sales
        END AS sls_sales,
        sls_quantity,
        CASE
            WHEN sls_price IS NULL OR sls_price <= 0
                THEN sls_sales / NULLIF(sls_quantity, 0)
            ELSE sls_price
        END AS sls_price
    FROM bronze.cmr_sales_details;

    SELECT CONCAT('Completed silver.cmr_sales_details in ', TIMESTAMPDIFF(MICROSECOND, step_start, NOW(6)) / 1000000.0, ' seconds') AS Log_Message;


    -- -------------------------------------------------------------------------
    -- 4. Load silver.erp_cust_az12
    -- -------------------------------------------------------------------------
    SET step_start = NOW(6);
    SELECT '--- Loading silver.erp_cust_az12 ---' AS Log_Message;

    TRUNCATE TABLE silver.erp_cust_az12;

    INSERT INTO silver.erp_cust_az12 (cid, bdate, gen)
    SELECT 
        CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LENGTH(cid))
             ELSE cid
        END AS cid,
        CASE WHEN bdate > CURDATE() THEN NULL
             ELSE bdate
        END AS bdate,
        CASE WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
             WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
             ELSE 'n/a'
        END AS gen
    FROM bronze.erp_cust_az12;

    SELECT CONCAT('Completed silver.erp_cust_az12 in ', TIMESTAMPDIFF(MICROSECOND, step_start, NOW(6)) / 1000000.0, ' seconds') AS Log_Message;


    -- -------------------------------------------------------------------------
    -- 5. Load silver.erp_loc_a101
    -- -------------------------------------------------------------------------
    SET step_start = NOW(6);
    SELECT '--- Loading silver.erp_loc_a101 ---' AS Log_Message;

    TRUNCATE TABLE silver.erp_loc_a101;

    INSERT INTO silver.erp_loc_a101 (cid, cntry)
    SELECT
        REPLACE(cid, '-', '') AS cid,
        CASE
            WHEN TRIM(cntry) = 'DE' THEN 'Germany'
            WHEN TRIM(cntry) IN ('US', 'USA') THEN 'United States'
            WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'n/a'
            ELSE TRIM(cntry)
        END AS cntry
    FROM bronze.erp_loc_a101;

    SELECT CONCAT('Completed silver.erp_loc_a101 in ', TIMESTAMPDIFF(MICROSECOND, step_start, NOW(6)) / 1000000.0, ' seconds') AS Log_Message;


    -- -------------------------------------------------------------------------
    -- 6. Load silver.erp_px_cat_g1v2
    -- -------------------------------------------------------------------------
    SET step_start = NOW(6);
    SELECT '--- Loading silver.erp_px_cat_g1v2 ---' AS Log_Message;

    TRUNCATE TABLE silver.erp_px_cat_g1v2;

    INSERT INTO silver.erp_px_cat_g1v2 (id, cat, subcat, maintenance)
    SELECT id, cat, subcat, maintenance 
    FROM bronze.erp_px_cat_g1v2;

    SELECT CONCAT('Completed silver.erp_px_cat_g1v2 in ', TIMESTAMPDIFF(MICROSECOND, step_start, NOW(6)) / 1000000.0, ' seconds') AS Log_Message;


    -- -------------------------------------------------------------------------
    -- Summary Execution Time
    -- -------------------------------------------------------------------------
    SET end_time = NOW(6);
    SET duration_sec = TIMESTAMPDIFF(MICROSECOND, start_time, end_time) / 1000000.0;

    SELECT '==================================================' AS Log_Message;
    SELECT CONCAT('Full Silver Layer Pipeline Finished at ', end_time) AS Log_Message;
    SELECT CONCAT('Total Pipeline Duration: ', duration_sec, ' seconds') AS Log_Message;
    SELECT '==================================================' AS Log_Message;

END //

DELIMITER ;
