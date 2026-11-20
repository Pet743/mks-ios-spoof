#import <Foundation/Foundation.h>

// Operates on the supplied database; the production service supplies fixed paths.
// Tests use a synthetic SQLite database, never the host or device keychain.
FOUNDATION_EXPORT NSDictionary *MKSKeychainClean(NSString *databasePath, NSString *backupDirectory);
