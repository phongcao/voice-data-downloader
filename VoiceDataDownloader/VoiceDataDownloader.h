//
//  VoiceDataDownloader.h
//  VoiceDataDownloader
//
//  Created by Phong Cao on 10/3/16.
//  Copyright © 2016 Microsoft. All rights reserved.
//

#import <Foundation/Foundation.h>

// Callbacks
typedef void (^TextToSpeechAuthenticationCallback)(NSInteger statusCode, NSError * _Nullable error);

// VoiceDataDownloader interface
@interface VoiceDataDownloader : NSObject

// Properties
@property (nonatomic, nonnull, readonly)    NSString * subscriptionKey;
@property (nonatomic, readonly)             BOOL downloadInProgress;

// Class initializer
- (nullable instancetype)initWithSubscriptionKey:(nonnull NSString *)subscriptionKey;

- (void)authenticate:(nullable TextToSpeechAuthenticationCallback)callback;

// Download the voice data of the provided texts and settings
- (void)downloadVoiceData:(nonnull NSMutableArray<NSMutableArray<NSString *> *> *)texts
         languageSettings:(nonnull NSMutableArray<NSString *> *)languageSettings
            voiceSettings:(nonnull NSMutableArray<NSString *> *)voiceSettings
     speakingRateSettings:(nonnull NSMutableArray<NSString *> *)speakingRateSettings
                outputDir:(nonnull NSString *)outputDir;

@end
