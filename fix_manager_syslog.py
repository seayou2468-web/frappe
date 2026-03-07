import re

with open('IdeviceManager.h', 'r') as f:
    h_content = f.read()

if 'startSyslogCaptureWithCallback' not in h_content:
    h_content = h_content.replace('// RSD Support',
        '// RSD Support\n- (void)startSyslogCaptureWithCallback:(void (^)(NSString *line))callback;\n- (void)stopSyslogCapture;')
    with open('IdeviceManager.h', 'w') as f:
        f.write(h_content)

with open('IdeviceManager.m', 'r') as f:
    m_content = f.read()

# Add syslog property
m_content = m_content.replace('@property (nonatomic, strong) NSTimer *heartbeatTimer;',
                             '@property (nonatomic, strong) NSTimer *heartbeatTimer;\n@property (nonatomic, assign) struct SyslogRelayClientHandle *syslogClient;\n@property (nonatomic, assign) BOOL syslogActive;')

m_content = m_content.replace('@synthesize ddiMounted = _ddiMounted;',
                             '@synthesize ddiMounted = _ddiMounted;\n@synthesize syslogClient = _syslogClient;\n@synthesize syslogActive = _syslogActive;')

syslog_methods = r"""
- (void)startSyslogCaptureWithCallback:(void (^)(NSString *line))callback {
    [_lock lock];
    if (self.status != IdeviceStatusConnected || !self.provider) {
        [_lock unlock];
        return;
    }
    if (self.syslogActive) { [_lock unlock]; return; }
    struct IdeviceProviderHandle *p = self.provider;
    self.syslogActive = YES;
    [_lock unlock];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct SyslogRelayClientHandle *client = NULL;
        struct IdeviceFfiError *err = syslog_relay_connect_tcp(p, &client);
        if (err || !client) {
            if (err) idevice_error_free(err);
            [self stopSyslogCapture];
            return;
        }

        [self->_lock lock];
        self.syslogClient = client;
        [self->_lock unlock];

        while (true) {
            [self->_lock lock];
            BOOL active = self.syslogActive;
            struct SyslogRelayClientHandle *c = self.syslogClient;
            [self->_lock unlock];

            if (!active || !c) break;

            char *line = NULL;
            err = syslog_relay_next(c, &line);
            if (err) {
                idevice_error_free(err);
                break;
            }
            if (line) {
                NSString *nsLine = [NSString stringWithUTF8String:line];
                if (callback) dispatch_async(dispatch_get_main_queue(), ^{ callback(nsLine); });
                rsd_free_string(line);
            }
        }
        [self stopSyslogCapture];
    });
}

- (void)stopSyslogCapture {
    [_lock lock];
    self.syslogActive = NO;
    if (self.syslogClient) {
        syslog_relay_client_free(self.syslogClient);
        self.syslogClient = NULL;
    }
    [_lock unlock];
}
"""

if 'startSyslogCaptureWithCallback' not in m_content:
    m_content = m_content.replace('@end\n', syslog_methods + '\n@end\n')
    # Update disconnect to stop syslog
    m_content = m_content.replace('[_lock unlock];\n    dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"IdeviceStatusChanged" object:nil]; });',
                                 '[self stopSyslogCapture];\n    [_lock unlock];\n    dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"IdeviceStatusChanged" object:nil]; });')
    with open('IdeviceManager.m', 'w') as f:
        f.write(m_content)
