//
// Copyright 2013 - 2015 Anton Tananaev (anton.tananaev@gmail.com)
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "TCTrackingController.h"
#import "TCStatusViewController.h"
#import "TraccarClient-Swift.h"

int64_t kRetryDelay = 30 * 1000;

@interface TCTrackingController () <PositionProviderDelegate, NetworkManagerDelegate>

@property (nonatomic) BOOL online;
@property (nonatomic) BOOL waiting;
@property (nonatomic) BOOL stopped;

@property (nonatomic, strong) PositionProvider *positionProvider;
@property (nonatomic, strong) DatabaseHelper *databaseHelper;
@property (nonatomic, strong) NetworkManager *networkManager;
@property (nonatomic, strong) NSUserDefaults *userDefaults;

@property (nonatomic, strong) NSString *address;
@property (nonatomic, assign) long port;
@property (nonatomic, assign) BOOL secure;

- (void)write:(Position *)position;
- (void)read;
- (void)delete:(Position *)position;
- (void)send:(Position *)position;
- (void)retry;

@end

@implementation TCTrackingController

- (instancetype)init {
    self = [super init];
    if (self) {
        self.positionProvider = [[PositionProvider alloc] init];
        self.databaseHelper = [[DatabaseHelper alloc] init];
        self.networkManager = [[NetworkManager alloc] init];
        
        self.positionProvider.delegate = self;
        self.networkManager.delegate = self;
        
        self.online = self.networkManager.online;
        
        self.userDefaults = [NSUserDefaults standardUserDefaults];
        self.address = [self.userDefaults stringForKey:@"server_address_preference"];
        self.port = [self.userDefaults integerForKey:@"server_port_preference"];
        self.secure = [self.userDefaults integerForKey:@"secure_preference"];
    }
    return self;
}

- (void)start {
    self.stopped = NO;
    if (self.online) {
        [self read];
    }
    [self.positionProvider startUpdates];
    [self.networkManager start];
}

- (void)stop {
    [self.networkManager stop];
    [self.positionProvider stopUpdates];
    self.stopped = YES;
}

- (void)didUpdateWithPosition:(Position *)position {
    [TCStatusViewController addMessage:NSLocalizedString(@"Location update", @"")];
    [self write:position];
}

- (void)didUpdateNetworkWithOnline:(BOOL)online {
    [TCStatusViewController addMessage:NSLocalizedString(@"Connectivity change", @"")];
    if (!self.online && online) {
        [self read];
    }
    self.online = online;
}

//
// State transition examples:
//
// write -> read -> send -> delete -> read
//
// read -> send -> retry -> read -> send
//

- (void)write:(Position *)position {
    if (self.online && self.waiting) {
        [self read];
        self.waiting = NO;
    }
}

- (void)read {
    Position *position = [self.databaseHelper selectPosition];
    if (position) {
        if ([position.deviceId isEqualToString:[self.userDefaults stringForKey:@"device_id_preference"]]) {
            [self send:position];
        } else {
            [self delete:position];
        }
    } else {
        self.waiting = YES;
    }
}

- (void)delete:(Position *)position {
    [self.databaseHelper deleteWithPosition:position];
    [self read];
}

- (void)send:(Position *)position {
    NSURL *request = [ProtocolFormatter formatPostion:position address:self.address port:self.port secure:self.secure];
    [RequestManager sendRequest:request completionHandler:^(BOOL success) {
        if (success) {
            [self delete:position];
        } else {
            [TCStatusViewController addMessage:NSLocalizedString(@"Send failed", @"")];
            [self retry];
        }
    }];
}

- (void)retry {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kRetryDelay * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (!self.stopped && self.online) {
            [self read];
        }
    });
}

@end
