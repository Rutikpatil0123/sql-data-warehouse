--- This script drops database warehoue_db if exitst and then create new db
	

drop database if exitst warehouse_db;

create database warehouse_db;

use warehouse_db;


--- create schema for bronze, silver and gold layer

create schema bronze;

create schema sliver;

create schema gold;
