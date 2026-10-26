-- Create the warehouse database and layer schemas if they do not exist.
CREATE DATABASE IF NOT EXISTS warehouse_db;

USE warehouse_db;

CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS gold;
