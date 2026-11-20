#import "MKSHTTPServer.h"
#import "MKSOperations.h"
#import "../common/MKSHTTP.h"
#include <sys/socket.h>
#include <sys/stat.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <poll.h>

static ssize_t boundedRead(int fd,void *buffer,size_t size,CFAbsoluteTime until) {
    while(1) {
        double remaining=until-CFAbsoluteTimeGetCurrent();
        if(remaining<=0) return -1;
        struct pollfd descriptor={fd,POLLIN,0};
        int status=poll(&descriptor,1,(int)(remaining*1000)+1);
        if(status<0 && errno==EINTR) continue;
        if(status<=0) return -1;
        ssize_t n=read(fd,buffer,size);
        if(n<0 && errno==EINTR) continue;
        return n;
    }
}

@interface MKSHTTPJobs : NSObject
@property(copy) NSString *path;
@property(strong) NSMutableArray *jobs;
@property(strong) dispatch_queue_t worker;
- (instancetype)initWithDirectory:(NSString *)directory;
- (NSDictionary *)submit:(NSString *)action key:(NSString *)key status:(int *)status start:(NSString **)start;
- (void)start:(NSString *)jobID;
- (NSDictionary *)job:(NSString *)jobID;
@end
@implementation MKSHTTPJobs
- (BOOL)save {
    NSData *data=[NSJSONSerialization dataWithJSONObject:self.jobs options:0 error:NULL];
    if(!data || ![data writeToFile:self.path options:NSDataWritingAtomic error:NULL]) return NO;
    return chmod(self.path.fileSystemRepresentation,0600)==0;
}
- (instancetype)initWithDirectory:(NSString *)directory {
    if((self=[super init])) {
        self.path=[directory stringByAppendingPathComponent:@"jobs.json"];
        self.worker=dispatch_queue_create("com.mks.http.operations",DISPATCH_QUEUE_SERIAL);
        struct stat st;
        BOOL exists=lstat(self.path.fileSystemRepresentation,&st)==0;
        if(exists && (!S_ISREG(st.st_mode) || st.st_size>1048576)) return nil;
        NSData *data=[NSData dataWithContentsOfFile:self.path];
        if(exists && !data) return nil;
        id loaded=data?[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:NULL]:nil;
        if(data && ![loaded isKindOfClass:NSArray.class]) return nil;
        self.jobs=loaded?:[NSMutableArray new];
        if(self.jobs.count>100) return nil;
        for(NSMutableDictionary *job in self.jobs) {
            if(![job isKindOfClass:NSMutableDictionary.class] || ![job[@"jobId"] isKindOfClass:NSString.class] ||
                ![job[@"key"] isKindOfClass:NSString.class] ||
                ![@[@"spoof",@"restore",@"keychain/clean"] containsObject:job[@"action"]] ||
                ![@[@"queued",@"running",@"succeeded",@"failed",@"interrupted"] containsObject:job[@"state"]]) return nil;
            if([@[@"queued",@"running"] containsObject:job[@"state"]]) {
                job[@"state"]=@"interrupted";
                job[@"result"]=@{@"ok":@NO,@"outcomeUnknown":@YES,@"error":@"daemon_restarted"};
            }
        }
        if(![self save]) return nil;
    }
    return self;
}
- (NSDictionary *)publicJob:(NSDictionary *)job {
    NSMutableDictionary *result=[job mutableCopy];[result removeObjectForKey:@"key"];return result;
}
- (NSDictionary *)job:(NSString *)jobID {
    @synchronized(self) {
        for(NSDictionary *job in self.jobs) if([job[@"jobId"] isEqual:jobID]) return [self publicJob:job];
        return nil;
    }
}
- (NSDictionary *)submit:(NSString *)action key:(NSString *)key status:(int *)status start:(NSString **)start {
    @synchronized(self) {
        for(NSDictionary *job in self.jobs) if([job[@"key"] isEqual:key]) {
            *status=[job[@"action"] isEqual:action]?202:409;
            return *status==202?[self publicJob:job]:@{@"error":@"idempotency_conflict"};
        }
        NSArray *previous=[self.jobs copy];
        if(self.jobs.count>=100) {
            NSUInteger index=[self.jobs indexOfObjectPassingTest:^BOOL(NSDictionary *job,NSUInteger idx,BOOL *stop) {
                (void)idx;(void)stop;return ![@[@"queued",@"running"] containsObject:job[@"state"]];
            }];
            if(index==NSNotFound) { *status=503;return @{@"error":@"queue_full"}; }
            [self.jobs removeObjectAtIndex:index];
        }
        NSMutableDictionary *job=[@{@"jobId":NSUUID.UUID.UUIDString,@"key":key,@"action":action,
            @"state":@"queued",@"createdAt":@([NSDate.date timeIntervalSince1970])} mutableCopy];
        [self.jobs addObject:job];
        if(![self save]) { self.jobs=[previous mutableCopy];*status=503;return @{@"error":@"job_save_failed"}; }
        *status=202;*start=job[@"jobId"];return [self publicJob:job];
    }
}
- (void)start:(NSString *)jobID {
    // Called only after HTTP response write; delay leaves the reply time to drain
    // before SpringBoard is terminated. Persistent idempotency handles lost replies.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),self.worker,^{
        @autoreleasepool {
            NSMutableDictionary *selected=nil;
            @synchronized(self) {
                for(NSMutableDictionary *job in self.jobs) if([job[@"jobId"] isEqual:jobID]) selected=job;
                if(!selected || ![selected[@"state"] isEqual:@"queued"]) return;
                selected[@"state"]=@"running";
                if(![self save]) { selected[@"state"]=@"failed";selected[@"result"]=@{@"ok":@NO,@"error":@"job_save_failed"};return; }
            }
            NSDictionary *result=MKSPerformOperation(selected[@"action"]);
            @synchronized(self) {
                selected[@"result"]=result;
                selected[@"state"]=[result[@"ok"] boolValue]?@"succeeded":@"failed";
                selected[@"finishedAt"]=@([NSDate.date timeIntervalSince1970]);
                if(![self save]) {
                    selected[@"state"]=@"interrupted";
                    selected[@"result"]=@{@"ok":@NO,@"outcomeUnknown":@YES,@"error":@"result_save_failed"};
                }
            }
        }
    });
}
@end

static BOOL equalToken(NSString *a,NSString *b) {
    NSData *left=[a dataUsingEncoding:NSUTF8StringEncoding],*right=[b dataUsingEncoding:NSUTF8StringEncoding];
    if(left.length!=right.length) return NO;
    const uint8_t *x=left.bytes,*y=right.bytes;uint8_t difference=0;
    for(NSUInteger i=0;i<left.length;i++) difference|=x[i]^y[i];
    return difference==0;
}
static void reply(int fd,int status,NSDictionary *body) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:body options:NSJSONWritingSortedKeys error:NULL];
    NSString *header=[NSString stringWithFormat:@"HTTP/1.1 %d %@\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: %lu\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n",status,status<400?@"OK":@"Error",(unsigned long)data.length];
    NSMutableData *response=[[header dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];[response appendData:data];
    size_t sent=0;
    while(sent<response.length) {
        ssize_t n=write(fd,(const uint8_t *)response.bytes+sent,response.length-sent);
        if(n<0 && errno==EINTR) continue;
        if(n<=0) break;
        sent+=(size_t)n;
    }
}
static void serveHTTP(int fd,NSString *token,MKSHTTPJobs *jobs) {
    struct timeval timeout={3,0};int yes=1;
    setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
    setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    NSMutableData *buffer=[NSMutableData new];NSData *delimiter=[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    CFAbsoluteTime requestDeadline=CFAbsoluteTimeGetCurrent()+5;
    NSRange boundary={NSNotFound,0};
    while(buffer.length<=8192) {
        char chunk[1024];ssize_t n=boundedRead(fd,chunk,sizeof(chunk),requestDeadline);
        if(n<0 && errno==EINTR) continue;
        if(n<=0) { reply(fd,400,@{@"error":@"incomplete_request"});return; }
        [buffer appendBytes:chunk length:(NSUInteger)n];
        boundary=[buffer rangeOfData:delimiter options:0 range:NSMakeRange(0,buffer.length)];
        if(boundary.location!=NSNotFound) break;
    }
    if(boundary.location==NSNotFound || boundary.location>8192) { reply(fd,413,@{@"error":@"headers_too_large"});return; }
    NSString *header=[[NSString alloc] initWithData:[buffer subdataWithRange:NSMakeRange(0,boundary.location)] encoding:NSASCIIStringEncoding];
    NSArray *lines=[header componentsSeparatedByString:@"\r\n"];
    NSArray *first=[lines.firstObject componentsSeparatedByString:@" "];
    if(first.count!=3 || ![@[@"HTTP/1.1",@"HTTP/1.0"] containsObject:first[2]]) { reply(fd,400,@{@"error":@"bad_request_line"});return; }
    NSMutableDictionary *headers=[NSMutableDictionary new];
    for(NSUInteger i=1;i<lines.count;i++) {
        NSString *line=lines[i];NSRange colon=[line rangeOfString:@":"];
        if(colon.location==NSNotFound || colon.location==0) { reply(fd,400,@{@"error":@"bad_header"});return; }
        NSString *key=[[line substringToIndex:colon.location] lowercaseString];
        NSCharacterSet *valid=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789-"];
        if([key rangeOfCharacterFromSet:valid.invertedSet].location!=NSNotFound || headers[key]) { reply(fd,400,@{@"error":@"duplicate_or_bad_header"});return; }
        headers[key]=[[line substringFromIndex:colon.location+1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    }
    if(headers[@"origin"] || headers[@"referer"]) { reply(fd,403,@{@"error":@"browser_origin_rejected"});return; }
    if(!equalToken(headers[@"authorization"] ?: @"",[@"Bearer " stringByAppendingString:token])) { reply(fd,401,@{@"error":@"unauthorized"});return; }
    if(headers[@"transfer-encoding"] || headers[@"expect"]) { reply(fd,400,@{@"error":@"unsupported_framing"});return; }
    NSString *lengthText=headers[@"content-length"] ?: @"0";
    if(!lengthText.length || lengthText.length>8 || [lengthText rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location!=NSNotFound) { reply(fd,400,@{@"error":@"bad_content_length"});return; }
    NSUInteger length=lengthText.integerValue;
    if(length>4096) { reply(fd,413,@{@"error":@"body_too_large"});return; }
    NSUInteger bodyAt=boundary.location+4;
    while(buffer.length<bodyAt+length) {
        char chunk[1024];ssize_t n=boundedRead(fd,chunk,MIN(sizeof(chunk),bodyAt+length-buffer.length),requestDeadline);
        if(n<0 && errno==EINTR) continue;
        if(n<=0) { reply(fd,400,@{@"error":@"incomplete_body"});return; }
        [buffer appendBytes:chunk length:(NSUInteger)n];
    }
    if(buffer.length!=bodyAt+length) { reply(fd,400,@{@"error":@"pipelining_not_supported"});return; }
    NSString *method=first[0],*path=first[1];
    NSString *device=MKSHTTPDeviceID();
    if(!device.length) { reply(fd,503,@{@"error":@"device_id_not_configured"});return; }
    NSString *prefix=[NSString stringWithFormat:@"/v1/devices/%@/",device];
    if(![path hasPrefix:prefix]) { reply(fd,404,@{@"error":@"device_not_found"});return; }
    path=[@"/v1/" stringByAppendingString:[path substringFromIndex:prefix.length]];
    if([method isEqual:@"GET"] && [path isEqual:@"/v1/status"] && !length) { reply(fd,200,MKSOperationStatus());return; }
    if([method isEqual:@"GET"] && [path hasPrefix:@"/v1/jobs/"] && !length) {
        NSDictionary *job=[jobs job:[path substringFromIndex:9]];
        reply(fd,job?200:404,job ?: @{@"error":@"job_not_found"});return;
    }
    NSDictionary *actions=@{@"/v1/spoof":@"spoof",@"/v1/restore":@"restore",@"/v1/keychain/clean":@"keychain/clean"};
    NSString *action=actions[path];
    if(!action) { reply(fd,404,@{@"error":@"not_found"});return; }
    if(![method isEqual:@"POST"]) { reply(fd,405,@{@"error":@"use_post"});return; }
    NSString *key=headers[@"idempotency-key"];
    NSCharacterSet *keyChars=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_:." ];
    if(!key.length || key.length>128 || [key rangeOfCharacterFromSet:keyChars.invertedSet].location!=NSNotFound) { reply(fd,400,@{@"error":@"idempotency_key_required"});return; }
    if(![[[headers[@"content-type"] componentsSeparatedByString:@";"].firstObject lowercaseString] isEqual:@"application/json"]) { reply(fd,415,@{@"error":@"json_required"});return; }
    id body=length?[NSJSONSerialization JSONObjectWithData:[buffer subdataWithRange:NSMakeRange(bodyAt,length)] options:0 error:NULL]:nil;
    if(![body isKindOfClass:NSDictionary.class]) { reply(fd,400,@{@"error":@"json_object_required"});return; }
    if([action isEqual:@"keychain/clean"]) {
        if([body count]!=1 || !body[@"confirm"] || CFGetTypeID((__bridge CFTypeRef)body[@"confirm"])!=CFBooleanGetTypeID() || ![body[@"confirm"] boolValue]) { reply(fd,400,@{@"error":@"confirm_true_required"});return; }
    } else if([body count]) { reply(fd,400,@{@"error":@"unexpected_fields"});return; }
    int status=0;NSString *start=nil;
    NSDictionary *response=[jobs submit:action key:key status:&status start:&start];
    reply(fd,status,response);
    if(start) [jobs start:start];
}
int MKSHTTPListen(NSString *directory,NSString *token,uint16_t port,BOOL loopback) {
    if(token.length<32) return -1;
    MKSHTTPJobs *jobs=[[MKSHTTPJobs alloc] initWithDirectory:directory];if(!jobs) return -1;
    int server=socket(AF_INET,SOCK_STREAM,0);if(server<0) return -1;
    int yes=1;setsockopt(server,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof(yes));
    struct sockaddr_in address={0};address.sin_family=AF_INET;address.sin_port=htons(port);
    address.sin_addr.s_addr=htonl(loopback?INADDR_LOOPBACK:INADDR_ANY);
    if(bind(server,(struct sockaddr *)&address,sizeof(address))!=0 || listen(server,8)!=0) { close(server);return -1; }
#ifdef MKS_HTTP_TEST
    socklen_t size=sizeof(address);getsockname(server,(struct sockaddr *)&address,&size);
    printf("PORT=%u\n",ntohs(address.sin_port));fflush(stdout);
#endif
    dispatch_semaphore_t slots=dispatch_semaphore_create(8);
    while(1) {
        int client=accept(server,NULL,NULL);
        if(client<0) { if(errno==EINTR) continue;break; }
        if(dispatch_semaphore_wait(slots,DISPATCH_TIME_NOW)!=0) { close(client);continue; }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
            @autoreleasepool { serveHTTP(client,token,jobs); }
            close(client);dispatch_semaphore_signal(slots);
        });
    }
    close(server);return 0;
}
int MKSHTTPConfigureDeviceID(const char *deviceID) {
    if(geteuid()!=0 || !deviceID) return 1;
    NSString *value=[@(deviceID) uppercaseString];
    NSString *pattern=@"^([0-9A-F]{8}-[0-9A-F]{16}|[0-9A-F]{40})$";
    if([value rangeOfString:pattern options:NSRegularExpressionSearch].location==NSNotFound) return 2;
    NSData *data=[value dataUsingEncoding:NSUTF8StringEncoding];
    if(![data writeToFile:MKS_HTTP_DEVICE_PATH options:NSDataWritingAtomic error:NULL]) return 3;
    if(chown(MKS_HTTP_DEVICE_PATH.fileSystemRepresentation,0,501)!=0 || chmod(MKS_HTTP_DEVICE_PATH.fileSystemRepresentation,0640)!=0) return 4;
    return 0;
}
void MKSHTTPStartServer(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        @autoreleasepool {
            NSString *directory=[MKS_HTTP_TOKEN_PATH stringByDeletingLastPathComponent];
            struct stat st;
            if(lstat(directory.fileSystemRepresentation,&st)!=0 || !S_ISDIR(st.st_mode) || st.st_uid!=0 || (st.st_mode&0027)) { NSLog(@"MKS HTTP: state directory unavailable");return; }
            NSString *token=MKSHTTPToken();
            if(!token) {
                uint8_t bytes[32];arc4random_buf(bytes,sizeof(bytes));NSMutableString *new=[NSMutableString new];
                for(NSUInteger i=0;i<sizeof(bytes);i++) [new appendFormat:@"%02x",bytes[i]];
                int fd=open(MKS_HTTP_TOKEN_PATH.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0640);
                if(fd<0) return;
                NSData *data=[new dataUsingEncoding:NSUTF8StringEncoding];
                BOOL ok=write(fd,data.bytes,data.length)==(ssize_t)data.length && fchown(fd,0,501)==0 && fsync(fd)==0;
                close(fd);if(!ok) { unlink(MKS_HTTP_TOKEN_PATH.fileSystemRepresentation);return; }token=new;
            }
            if(MKSHTTPListen(directory,token,MKS_HTTP_PORT,NO)<0) NSLog(@"MKS HTTP: listener unavailable");
        }
    });
}
