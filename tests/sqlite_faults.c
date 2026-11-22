// Test-only SQLite boundary used to exercise an ambiguous COMMIT failure.
#include <sqlite3.h>
#include <stdlib.h>
#include <string.h>
int MKSTestSQLiteExec(sqlite3 *db,const char *sql,int (*callback)(void *,int,char **,char **),void *context,char **error) {
    if(getenv("MKS_TEST_COMMIT_FAILURE") && !strcmp(sql,"COMMIT")) {
        sqlite3_exec(db,"ROLLBACK",NULL,NULL,NULL);
        return SQLITE_IOERR;
    }
    return sqlite3_exec(db,sql,callback,context,error);
}
