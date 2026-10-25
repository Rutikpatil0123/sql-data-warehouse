 -- DROP database silver;

-- Create database if it doesn't exist
-- CREATE DATABASE IF NOT EXISTS silver;
USE silver;


-- 1. Silver Customer Info
CREATE TABLE IF NOT EXISTS silver.cmr_cust_info (
    cst_id INT,
    cst_key VARCHAR(50),
    cst_firstname VARCHAR(50),
    cst_lastname VARCHAR(50),
    cst_marital_status VARCHAR(50),
    cst_gndr VARCHAR(50),
    cst_create_data DATE,
    dwh_created_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 2. Silver Product Info
CREATE TABLE IF NOT EXISTS silver.cmr_prd_info (
    prd_id INT,
    cat_id VARCHAR(50),
    prd_key VARCHAR(50),
    prd_nm VARCHAR(50),
    prd_cost INT,
    prd_line VARCHAR(50),
    prd_start_dt DATE,
    prd_end_dt DATE,
    dwh_created_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 3. Silver Sales Details
CREATE TABLE IF NOT EXISTS silver.cmr_sales_details (
    sls_ord_num VARCHAR(50),
    sls_prd_key VARCHAR(50),
    sls_cust_id INT,
    sls_order_dt DATE,
    sls_ship_dt DATE,
    sls_due_dt DATE,
    sls_sales INT,
    sls_quantity INT,
    sls_price INT,
    dwh_created_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 4. Silver ERP Customer AZ12
CREATE TABLE IF NOT EXISTS silver.erp_cust_az12 (
    cid VARCHAR(50),
    bdate DATE,
    gen VARCHAR(50),
    dwh_created_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 5. Silver ERP Location A101
CREATE TABLE IF NOT EXISTS silver.erp_loc_a101 (
    cid VARCHAR(50),
    cntry VARCHAR(50),
    dwh_created_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 6. Silver ERP Product Category G1V2
CREATE TABLE IF NOT EXISTS silver.erp_px_cat_g1v2 (
    id VARCHAR(50),
    cat VARCHAR(50),
    subcat VARCHAR(50),
    maintenance VARCHAR(50),
    dwh_created_date DATETIME DEFAULT CURRENT_TIMESTAMP
);
