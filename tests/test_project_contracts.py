import csv
import re
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
DATASETS = ROOT / "datasets"

CSV_HEADERS = {
    "cust_info.csv": [
        "cst_id",
        "cst_key",
        "cst_firstname",
        "cst_lastname",
        "cst_marital_status",
        "cst_gndr",
        "cst_create_date",
    ],
    "prd_info.csv": [
        "prd_id",
        "prd_key",
        "prd_nm",
        "prd_cost",
        "prd_line",
        "prd_start_dt",
        "prd_end_dt",
    ],
    "sales_details.csv": [
        "sls_ord_num",
        "sls_prd_key",
        "sls_cust_id",
        "sls_order_dt",
        "sls_ship_dt",
        "sls_due_dt",
        "sls_sales",
        "sls_quantity",
        "sls_price",
    ],
    "CUST_AZ12.csv": ["CID", "BDATE", "GEN"],
    "LOC_A101.csv": ["CID", "CNTRY"],
    "PX_CAT_G1V2.csv": ["ID", "CAT", "SUBCAT", "MAINTENANCE"],
}

BRONZE_TABLES = {
    "cmr_cust_info",
    "cmr_prd_info",
    "cmr_sales_details",
    "erp_cust_az12",
    "erp_loc_a101",
    "erp_px_cat_g1v2",
}

SILVER_TABLES = {
    "cmr_cust_info",
    "cmr_prd_info",
    "cmr_sales_details",
    "erp_cust_az12",
    "erp_loc_a101",
    "erp_px_cat_g1v2",
}

GOLD_VIEWS = {"dim_customers", "dim_products", "fact_sales"}

EXPECTED_TABLES = {
    "bronze": {
        "cmr_cust_info": [
            ("cst_id", "INT"),
            ("cst_key", "VARCHAR(50)"),
            ("cst_firstname", "VARCHAR(50)"),
            ("cst_lastname", "VARCHAR(50)"),
            ("cst_marital_status", "VARCHAR(5)"),
            ("cst_gndr", "VARCHAR(5)"),
            ("cst_create_data", "DATE"),
        ],
        "cmr_prd_info": [
            ("prd_id", "INT"),
            ("prd_key", "VARCHAR(50)"),
            ("prd_nm", "VARCHAR(50)"),
            ("prd_cost", "INT"),
            ("prd_line", "VARCHAR(5)"),
            ("prd_start_dt", "DATETIME"),
            ("prd_end_dt", "DATETIME"),
        ],
        "cmr_sales_details": [
            ("sls_ord_num", "VARCHAR(50)"),
            ("sls_prd_key", "VARCHAR(50)"),
            ("sls_cust_id", "INT"),
            ("sls_order_dt", "INT"),
            ("sls_ship_dt", "INT"),
            ("sls_due_dt", "INT"),
            ("sls_sales", "INT"),
            ("sls_quantity", "INT"),
            ("sls_price", "INT"),
        ],
        "erp_cust_az12": [
            ("cid", "VARCHAR(50)"),
            ("bdate", "DATE"),
            ("gen", "VARCHAR(10)"),
        ],
        "erp_loc_a101": [
            ("cid", "VARCHAR(50)"),
            ("cntry", "VARCHAR(50)"),
        ],
        "erp_px_cat_g1v2": [
            ("id", "VARCHAR(50)"),
            ("cat", "VARCHAR(50)"),
            ("subcat", "VARCHAR(50)"),
            ("maintenance", "VARCHAR(50)"),
        ],
    },
    "silver": {
        "cmr_cust_info": [
            ("cst_id", "INT"),
            ("cst_key", "VARCHAR(50)"),
            ("cst_firstname", "VARCHAR(50)"),
            ("cst_lastname", "VARCHAR(50)"),
            ("cst_marital_status", "VARCHAR(50)"),
            ("cst_gndr", "VARCHAR(50)"),
            ("cst_create_data", "DATE"),
            ("dwh_created_date", "DATETIME"),
        ],
        "cmr_prd_info": [
            ("prd_id", "INT"),
            ("cat_id", "VARCHAR(50)"),
            ("prd_key", "VARCHAR(50)"),
            ("prd_nm", "VARCHAR(50)"),
            ("prd_cost", "INT"),
            ("prd_line", "VARCHAR(50)"),
            ("prd_start_dt", "DATE"),
            ("prd_end_dt", "DATE"),
            ("dwh_created_date", "DATETIME"),
        ],
        "cmr_sales_details": [
            ("sls_ord_num", "VARCHAR(50)"),
            ("sls_prd_key", "VARCHAR(50)"),
            ("sls_cust_id", "INT"),
            ("sls_order_dt", "DATE"),
            ("sls_ship_dt", "DATE"),
            ("sls_due_dt", "DATE"),
            ("sls_sales", "DECIMAL(12,2)"),
            ("sls_quantity", "INT"),
            ("sls_price", "DECIMAL(12,2)"),
            ("dwh_created_date", "DATETIME"),
        ],
        "erp_cust_az12": [
            ("cid", "VARCHAR(50)"),
            ("bdate", "DATE"),
            ("gen", "VARCHAR(50)"),
            ("dwh_created_date", "DATETIME"),
        ],
        "erp_loc_a101": [
            ("cid", "VARCHAR(50)"),
            ("cntry", "VARCHAR(50)"),
            ("dwh_created_date", "DATETIME"),
        ],
        "erp_px_cat_g1v2": [
            ("id", "VARCHAR(50)"),
            ("cat", "VARCHAR(50)"),
            ("subcat", "VARCHAR(50)"),
            ("maintenance", "VARCHAR(50)"),
            ("dwh_created_date", "DATETIME"),
        ],
    },
}


def parse_tables(sql_text, schema):
    table_pattern = re.compile(
        rf"CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+{schema}\.(\w+)\s*"
        r"\((.*?)\n\);",
        re.IGNORECASE | re.DOTALL,
    )
    column_pattern = re.compile(
        r"^\s*(\w+)\s+([A-Z]+(?:\s*\([^)]*\))?)",
        re.IGNORECASE,
    )
    tables = {}
    for table_match in table_pattern.finditer(sql_text):
        table_name, body = table_match.groups()
        columns = []
        for line in body.splitlines():
            column_match = column_pattern.match(line)
            if column_match:
                column_name, sql_type = column_match.groups()
                columns.append(
                    (column_name, re.sub(r"\s+", "", sql_type).upper())
                )
        tables[table_name] = columns
    return tables


def parse_view_select_columns(sql_text, view_name):
    view_match = re.search(
        rf"CREATE\s+OR\s+REPLACE\s+VIEW\s+gold\.{view_name}\s+AS\s*"
        r"SELECT(.*?)\sFROM\s",
        sql_text,
        re.IGNORECASE | re.DOTALL,
    )
    if not view_match:
        return []

    select_clause = view_match.group(1)
    expressions = []
    start = 0
    depth = 0
    for index, character in enumerate(select_clause):
        if character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
        elif character == "," and depth == 0:
            expressions.append(select_clause[start:index].strip())
            start = index + 1
    expressions.append(select_clause[start:].strip())

    columns = []
    for expression in expressions:
        alias_match = re.search(r"\bAS\s+(\w+)\s*$", expression, re.IGNORECASE)
        if alias_match:
            columns.append(alias_match.group(1))
        else:
            columns.append(expression.rsplit(".", 1)[-1].strip(" `"))
    return columns


class DatasetContractTests(unittest.TestCase):
    def test_required_csv_files_have_expected_headers_and_rows(self):
        for file_name, expected_header in CSV_HEADERS.items():
            with self.subTest(file=file_name):
                path = DATASETS / file_name
                self.assertTrue(path.is_file(), f"Missing dataset: {path}")
                with path.open(newline="", encoding="utf-8-sig") as source:
                    reader = csv.reader(source)
                    self.assertEqual(next(reader), expected_header)
                    row_count = 0
                    for row in reader:
                        self.assertEqual(
                            len(row),
                            len(expected_header),
                            f"Malformed row {row_count + 2} in {file_name}",
                        )
                        row_count += 1
                self.assertGreater(row_count, 0, f"{file_name} has no data rows")


class SqlContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bronze_ddl = (SCRIPTS / "bronze/ddl_bronze.sql").read_text()
        cls.silver_ddl = (SCRIPTS / "silver/ddl_silver.sql").read_text()
        cls.bronze_loader = (SCRIPTS / "bronze/proc_load_bronze.sql").read_text()
        cls.silver_loader = (SCRIPTS / "silver/proc_load_silver.sql").read_text()
        cls.gold_ddl = (SCRIPTS / "gold/ddl_gold.sql").read_text()

    def test_initialization_creates_every_layer_schema(self):
        sql = (SCRIPTS / "init_database.sql").read_text()
        for schema in ("bronze", "silver", "gold"):
            with self.subTest(schema=schema):
                self.assertRegex(
                    sql,
                    rf"CREATE\s+SCHEMA\s+IF\s+NOT\s+EXISTS\s+{schema}\b",
                )

    def test_bronze_and_silver_table_contracts(self):
        bronze_tables = parse_tables(self.bronze_ddl, "bronze")
        silver_tables = parse_tables(self.silver_ddl, "silver")
        self.assertEqual(set(bronze_tables), BRONZE_TABLES)
        self.assertEqual(set(silver_tables), SILVER_TABLES)
        self.assertEqual(bronze_tables, EXPECTED_TABLES["bronze"])
        self.assertEqual(silver_tables, EXPECTED_TABLES["silver"])

    def test_bronze_loader_covers_all_source_files_and_tables(self):
        load_statements = re.findall(
            r"LOAD\s+DATA\s+LOCAL\s+INFILE\s+'([^']+)'\s+"
            r"INTO\s+TABLE\s+bronze\.(\w+)",
            self.bronze_loader,
            re.IGNORECASE,
        )
        self.assertEqual(
            {(Path(path).name, table) for path, table in load_statements},
            {
                ("cust_info.csv", "cmr_cust_info"),
                ("prd_info.csv", "cmr_prd_info"),
                ("sales_details.csv", "cmr_sales_details"),
                ("CUST_AZ12.csv", "erp_cust_az12"),
                ("LOC_A101.csv", "erp_loc_a101"),
                ("PX_CAT_G1V2.csv", "erp_px_cat_g1v2"),
            },
        )
        for file_name in CSV_HEADERS:
            with self.subTest(file=file_name):
                self.assertTrue((DATASETS / file_name).is_file())

        truncated_tables = set(
            re.findall(
                r"TRUNCATE\s+TABLE\s+bronze\.(\w+)",
                self.bronze_loader,
                re.IGNORECASE,
            )
        )
        self.assertEqual(truncated_tables, BRONZE_TABLES)

    def test_silver_loader_refreshes_each_silver_table(self):
        truncated_tables = set(
            re.findall(
                r"TRUNCATE\s+TABLE\s+silver\.(\w+)",
                self.silver_loader,
                re.IGNORECASE,
            )
        )
        inserted_tables = set(
            re.findall(
                r"INSERT\s+INTO\s+silver\.(\w+)",
                self.silver_loader,
                re.IGNORECASE,
            )
        )
        self.assertEqual(truncated_tables, SILVER_TABLES)
        self.assertEqual(inserted_tables, SILVER_TABLES)
        self.assertIn("CREATE PROCEDURE silver.load_silver_layer", self.silver_loader)
        self.assertIn("normalized_price", self.silver_loader)
        self.assertIn("sls_quantity > 0", self.silver_loader)

    def test_gold_views_expose_expected_columns_and_joins(self):
        expected_columns = {
            "dim_customers": {
                "customer_key",
                "customer_id",
                "customer_number",
                "first_name",
                "last_name",
                "country",
                "marital_status",
                "gender",
                "birthdate",
                "create_date",
            },
            "dim_products": {
                "product_key",
                "product_id",
                "product_number",
                "product_name",
                "category_id",
                "category",
                "subcategory",
                "maintenance",
                "cost",
                "product_line",
                "start_date",
                "prd_end_dt",
            },
            "fact_sales": {
                "order_number",
                "product_key",
                "customer_key",
                "order_date",
                "ship_date",
                "due_date",
                "sales_amount",
                "quantity",
                "price",
            },
        }
        view_names = set(
            re.findall(
                r"CREATE\s+OR\s+REPLACE\s+VIEW\s+gold\.(\w+)",
                self.gold_ddl,
                re.IGNORECASE,
            )
        )
        self.assertEqual(view_names, GOLD_VIEWS)
        for view_name, expected in expected_columns.items():
            with self.subTest(view=view_name):
                self.assertEqual(
                    set(parse_view_select_columns(self.gold_ddl, view_name)),
                    expected,
                )

        self.assertRegex(
            self.gold_ddl,
            r"(?i)\bON\s+sd\.sls_prd_key\s*=\s*pr\.product_number",
        )
        self.assertRegex(
            self.gold_ddl,
            r"(?i)\bON\s+sd\.sls_cust_id\s*=\s*cu\.customer_id",
        )


class DockerContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.launcher_path = SCRIPTS / "docker/start_warehouse.sh"
        cls.launcher = cls.launcher_path.read_text()

    def test_launcher_runs_pipeline_in_dependency_order(self):
        commands = [
            'run_sql_file "$PROJECT_DIR/scripts/init_database.sql"',
            'run_sql_file "$PROJECT_DIR/scripts/bronze/ddl_bronze.sql"',
            'run_sql_file "$PROJECT_DIR/scripts/silver/ddl_silver.sql"',
            'run_sql_file "$PROJECT_DIR/scripts/bronze/proc_load_bronze.sql"',
            'run_sql_file "$PROJECT_DIR/scripts/silver/proc_load_silver.sql"',
            "CALL silver.load_silver_layer();",
            'run_sql_file "$PROJECT_DIR/scripts/gold/ddl_gold.sql"',
        ]
        positions = [self.launcher.index(command) for command in commands]
        self.assertEqual(positions, sorted(positions))

    def test_launcher_persists_database_and_mounts_datasets_read_only(self):
        self.assertIn('VOLUME_NAME="${MYSQL_VOLUME_NAME:-', self.launcher)
        self.assertIn('"$VOLUME_NAME:/var/lib/mysql"', self.launcher)
        self.assertIn('"$DATA_DIR:/datasets:ro"', self.launcher)
        self.assertIn("--local-infile=1", self.launcher)

    @unittest.skipUnless(shutil.which("bash"), "bash is required for syntax check")
    def test_launcher_has_valid_bash_syntax(self):
        result = subprocess.run(
            ["bash", "-n", str(self.launcher_path)],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
