#!/bin/bash
# ##############################################################
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Author: Piotr Frątczak piotr4f@gmail.com
# Filename: mysql_convert_to_utf8-v1.sh
# Date changed: 2024-04-05
# Version: 1
# Description of changes:
# Initial version 1.0
################################################################
# bash settings:                                               #
################################################################
set -o pipefail
set -o nounset # "nounset" is equivalent to set -u and makes bash exit on usage of an unset variable.
set -e
###########################################
# global variables
sqlfile="/var/tmp/convert_database_to_utf8_procedure.sql"
# functions
# below sql procedure thanks to https://stackoverflow.com/users/1612273/arnoud
# https://stackoverflow.com/questions/18445969/how-to-change-collation-of-all-rows-from-latin1-swedish-ci-to-utf8-unicode-ci
# which is based on https://stackoverflow.com/questions/12718596/mysql-loop-through-tables/12718767#12718767
function create_sql_file(){
cat > "${sqlfile}" << "EOF"
delimiter //
DROP PROCEDURE IF EXISTS convert_database_to_utf8 //
CREATE PROCEDURE convert_database_to_utf8()
BEGIN
    DECLARE table_name VARCHAR(255);
    DECLARE done INT DEFAULT FALSE;
    DECLARE cur CURSOR FOR
        SELECT t.table_name FROM information_schema.tables t WHERE t.table_schema = DATABASE() AND t.table_type='BASE TABLE';
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    OPEN cur;
        SET foreign_key_checks = 0;
        tables_loop: LOOP
            FETCH cur INTO table_name;
            IF done THEN
                LEAVE tables_loop;
            END IF;
            SET @sql = CONCAT("ALTER TABLE ", table_name, " CONVERT TO CHARACTER SET utf8 COLLATE utf8_unicode_ci");
            PREPARE stmt FROM @sql;
            EXECUTE stmt;
            DROP PREPARE stmt;
        END LOOP;
        SET foreign_key_checks = 1;
    CLOSE cur;
END //
delimiter ;
EOF
}
function check_server_utf8(){
local utf8_md5_static='bc78e492e155543ad9ae9d49b8e9054e'
local utf8_md5=`mysql -Bse'select md5(concat(@@character_set_server,@@collation_server));'`
if [ ${utf8_md5_static} = ${utf8_md5} ]
    then
        echo "Server UTF8 - proceed with further steps"
        return 0
    else
        echo "Server not UTF8 - abort further action!"
        return 1
    fi
}

function convert_db_level(){
local db_list=`mysql -Bse "SELECT SCHEMA_NAME from  information_schema.SCHEMATA where  SCHEMA_NAME NOT IN ('information_schema','mysql','performance_schema') AND (DEFAULT_CHARACTER_SET_NAME!='utf8' AND DEFAULT_COLLATION_NAME!='utf8_unicode_ci');"`
echo "database level conversion"
for dbname in ${db_list}
    do mysql -e"ALTER DATABASE "${dbname}" CHARACTER SET = utf8 COLLATE = utf8_unicode_ci;"
done
}

function convert_tbl_level(){
echo "table level conversion"
local tbl_list=`mysql -Bse "select CONCAT(TABLE_SCHEMA,\".\",TABLE_NAME) FROM information_schema.TABLES where TABLE_SCHEMA NOT IN ('information_schema','mysql','performance_schema') and (TABLE_TYPE='BASE TABLE' and TABLE_COLLATION!='utf8_unicode_ci');"`
echo "tbl level"
for tblname in ${tbl_list}
    do mysql -e"ALTER TABLE "${tblname}" CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
done
}

function convert_col_level(){
echo "column level conversion"
local db_list=`mysql -Bse "SELECT SCHEMA_NAME from  information_schema.SCHEMATA where  SCHEMA_NAME NOT IN ('information_schema','mysql','performance_schema') AND (DEFAULT_CHARACTER_SET_NAME='utf8' AND DEFAULT_COLLATION_NAME='utf8_unicode_ci');"`
echo "column level"
for dbname in ${db_list}
    do mysql -AD "${dbname}" < "${sqlfile}"&&mysql -AD "${dbname}" -e"CALL convert_database_to_utf8();"
done
}

###########################
echo `date`
check_server_utf8
if [[ $? -eq 1 ]]; then
    echo "some_command failed"
fi
echo `date`
convert_db_level
echo `date`
convert_tbl_level
echo `date`
create_sql_file
echo `date`
convert_col_level
echo `date`
#########################
