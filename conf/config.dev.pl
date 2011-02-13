# Replace Path with local system path
# Replace Dbname with database name, host with database host, user with database user
# See Schema.txt for database information

use vars qw($appbase $connec $dbname $dbhost $dbuser $dbpswd $adpter);

$appbase = <PATH>;
$connec = "DBI:mysql";
$dbname = <DBNAME>;
$dbhost = <DBHOST>;
$dbuser = <DBUSER>;
$dbpswd = "";
$adpter = "$connec:$dbname:$dbhost";