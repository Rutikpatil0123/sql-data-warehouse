import csv
import os
import secrets
import shutil
import subprocess
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
DATASETS = ROOT / "datasets"
ENABLED = os.environ.get("RUN_MYSQL_INTEGRATION") == "1"
MYSQL_IMAGE = os.environ.get("MYSQL_IMAGE", "mysql:8.4")


def csv_rows(file_name):
    with (DATASETS / file_name).open(newline="", encoding="utf-8-sig") as source:
        return list(csv.DictReader(source))


def docker_command(arguments, *, input_text=None, check=True):
    result = subprocess.run(
        ["docker", *arguments],
        input=input_text,
        capture_output=True,
        text=True,
        check=False,
    )
    if check and result.returncode:
        raise RuntimeError(
            f"Docker command failed ({result.returncode}): "
            f"{' '.join(arguments)}\n{result.stdout}\n{result.stderr}"
        )
    return result


@unittest.skipUnless(
    ENABLED,
    "Set RUN_MYSQL_INTEGRATION=1 to run disposable MySQL integration tests",
)
class MysqlPipelineIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("docker"):
            raise RuntimeError("Docker is required for MySQL integration tests")

        cls.container_name = f"sql-warehouse-test-{secrets.token_hex(6)}"
        cls.mysql_password = secrets.token_urlsafe(24)
        cls.container_started = False

        try:
            docker_command(["info"])
            docker_command(
                [
                    "run",
                    "--detach",
                    "--rm",
                    "--name",
                    cls.container_name,
                    "--env",
                    f"MYSQL_ROOT_PASSWORD={cls.mysql_password}",
                    "--volume",
                    f"{DATASETS}:/datasets:ro",
                    MYSQL_IMAGE,
                    "--local-infile=1",
                ]
            )
            cls.container_started = True
            cls._wait_until_mysql_ready()
            cls._run_sql_file(SCRIPTS / "init_database.sql")
            cls._run_sql_file(SCRIPTS / "bronze/ddl_bronze.sql")
            cls._run_sql_file(SCRIPTS / "silver/ddl_silver.sql")
            cls._run_sql_file(SCRIPTS / "bronze/proc_load_bronze.sql")
            cls._run_sql_file(SCRIPTS / "silver/proc_load_silver.sql")
            cls._run_sql("CALL silver.load_silver_layer();")
            cls._run_sql_file(SCRIPTS / "gold/ddl_gold.sql")
        except Exception:
            cls._remove_container()
            raise

    @classmethod
    def tearDownClass(cls):
        cls._remove_container()

    @classmethod
    def _remove_container(cls):
        if getattr(cls, "container_started", False):
            docker_command(
                ["rm", "--force", cls.container_name],
                check=False,
            )
            cls.container_started = False

    @classmethod
    def _mysql(cls, sql):
        result = docker_command(
            [
                "exec",
                "--interactive",
                "--env",
                f"MYSQL_PWD={cls.mysql_password}",
                cls.container_name,
                "mysql",
                "--user=root",
                "--local-infile=1",
                "--default-character-set=utf8mb4",
                "--batch",
                "--skip-column-names",
            ],
            input_text=sql,
        )
        return result.stdout.strip().splitlines()

    @classmethod
    def _run_sql(cls, sql):
        cls._mysql(sql)

    @classmethod
    def _run_sql_file(cls, path):
        cls._mysql(path.read_text())

    @classmethod
    def _wait_until_mysql_ready(cls):
        for _ in range(60):
            result = docker_command(
                [
                    "exec",
                    "--env",
                    f"MYSQL_PWD={cls.mysql_password}",
                    cls.container_name,
                    "mysqladmin",
                    "--user=root",
                    "--silent",
                    "ping",
                ],
                check=False,
            )
            if result.returncode == 0:
                return

            state = docker_command(
                [
                    "inspect",
                    "--format",
                    "{{.State.Status}}",
                    cls.container_name,
                ],
                check=False,
            )
            if state.returncode or state.stdout.strip() != "running":
                logs = docker_command(
                    ["logs", "--tail", "80", cls.container_name],
                    check=False,
                )
                raise RuntimeError(
                    f"MySQL container stopped before becoming ready:\n"
                    f"{logs.stdout}\n{logs.stderr}"
                )
            time.sleep(2)

        logs = docker_command(
            ["logs", "--tail", "80", cls.container_name],
            check=False,
        )
        raise RuntimeError(
            f"MySQL did not become ready:\n{logs.stdout}\n{logs.stderr}"
        )

    @staticmethod
    def _count_distinct_customer_ids():
        return len(
            {
                int(row["cst_id"])
                for row in csv_rows("cust_info.csv")
                if row["cst_id"]
            }
        )

    def test_pipeline_loads_expected_rows_into_each_layer(self):
        source_counts = {
            "bronze.cmr_cust_info": len(csv_rows("cust_info.csv")),
            "bronze.cmr_prd_info": len(csv_rows("prd_info.csv")),
            "bronze.cmr_sales_details": len(csv_rows("sales_details.csv")),
            "bronze.erp_cust_az12": len(csv_rows("CUST_AZ12.csv")),
            "bronze.erp_loc_a101": len(csv_rows("LOC_A101.csv")),
            "bronze.erp_px_cat_g1v2": len(csv_rows("PX_CAT_G1V2.csv")),
        }
        customer_count = self._count_distinct_customer_ids()
        expected_counts = {
            **source_counts,
            "silver.cmr_cust_info": customer_count,
            "silver.cmr_prd_info": source_counts["bronze.cmr_prd_info"],
            "silver.cmr_sales_details": source_counts["bronze.cmr_sales_details"],
            "silver.erp_cust_az12": source_counts["bronze.erp_cust_az12"],
            "silver.erp_loc_a101": source_counts["bronze.erp_loc_a101"],
            "silver.erp_px_cat_g1v2": source_counts["bronze.erp_px_cat_g1v2"],
            "gold.dim_customers": customer_count,
            "gold.dim_products": None,
            "gold.fact_sales": source_counts["bronze.cmr_sales_details"],
        }

        actual_lines = self._mysql(
            "SELECT 'bronze.cmr_cust_info', COUNT(*) FROM bronze.cmr_cust_info "
            "UNION ALL SELECT 'bronze.cmr_prd_info', COUNT(*) FROM bronze.cmr_prd_info "
            "UNION ALL SELECT 'bronze.cmr_sales_details', COUNT(*) FROM bronze.cmr_sales_details "
            "UNION ALL SELECT 'bronze.erp_cust_az12', COUNT(*) FROM bronze.erp_cust_az12 "
            "UNION ALL SELECT 'bronze.erp_loc_a101', COUNT(*) FROM bronze.erp_loc_a101 "
            "UNION ALL SELECT 'bronze.erp_px_cat_g1v2', COUNT(*) FROM bronze.erp_px_cat_g1v2 "
            "UNION ALL SELECT 'silver.cmr_cust_info', COUNT(*) FROM silver.cmr_cust_info "
            "UNION ALL SELECT 'silver.cmr_prd_info', COUNT(*) FROM silver.cmr_prd_info "
            "UNION ALL SELECT 'silver.cmr_sales_details', COUNT(*) FROM silver.cmr_sales_details "
            "UNION ALL SELECT 'silver.erp_cust_az12', COUNT(*) FROM silver.erp_cust_az12 "
            "UNION ALL SELECT 'silver.erp_loc_a101', COUNT(*) FROM silver.erp_loc_a101 "
            "UNION ALL SELECT 'silver.erp_px_cat_g1v2', COUNT(*) FROM silver.erp_px_cat_g1v2 "
            "UNION ALL SELECT 'gold.dim_customers', COUNT(*) FROM gold.dim_customers "
            "UNION ALL SELECT 'gold.dim_products', COUNT(*) FROM gold.dim_products "
            "UNION ALL SELECT 'gold.fact_sales', COUNT(*) FROM gold.fact_sales;"
        )
        actual_counts = {
            name: int(count)
            for name, count in (line.split("\t") for line in actual_lines)
        }
        expected_counts["gold.dim_products"] = int(
            self._mysql(
                "SELECT COUNT(*) FROM silver.cmr_prd_info WHERE prd_end_dt IS NULL;"
            )[0]
        )
        self.assertEqual(actual_counts, expected_counts)

    def test_gold_views_resolve_all_fact_dimension_keys(self):
        result = self._mysql(
            "SELECT "
            "(SELECT COUNT(*) FROM gold.fact_sales WHERE product_key IS NULL), "
            "(SELECT COUNT(*) FROM gold.fact_sales WHERE customer_key IS NULL), "
            "(SELECT COUNT(*) FROM gold.dim_customers), "
            "(SELECT COUNT(*) FROM gold.dim_products), "
            "(SELECT COUNT(*) FROM gold.fact_sales);"
        )
        unmatched_products, unmatched_customers, customers, products, sales = map(
            int, result[0].split("\t")
        )
        self.assertEqual(unmatched_products, 0)
        self.assertEqual(unmatched_customers, 0)
        self.assertGreater(customers, 0)
        self.assertGreater(products, 0)
        self.assertGreater(sales, 0)

    def test_silver_data_quality_rules_hold_on_loaded_data(self):
        result = self._mysql(
            "SELECT "
            "(SELECT COUNT(*) FROM silver.cmr_sales_details "
            "WHERE sls_sales IS NULL OR sls_price IS NULL), "
            "(SELECT COUNT(*) FROM silver.cmr_sales_details "
            "WHERE sls_sales <> sls_quantity * sls_price), "
            "(SELECT COUNT(*) FROM silver.erp_cust_az12 WHERE bdate > CURDATE()), "
            "(SELECT COUNT(*) FROM ("
            "SELECT cst_id FROM silver.cmr_cust_info "
            "GROUP BY cst_id HAVING COUNT(*) > 1"
            ") duplicate_customers);"
        )
        missing_sales_values, inconsistent_sales, future_birth_dates, duplicate_customers = (
            map(int, result[0].split("\t"))
        )
        self.assertEqual(missing_sales_values, 0)
        self.assertEqual(inconsistent_sales, 0)
        self.assertEqual(future_birth_dates, 0)
        self.assertEqual(duplicate_customers, 0)


if __name__ == "__main__":
    unittest.main()
