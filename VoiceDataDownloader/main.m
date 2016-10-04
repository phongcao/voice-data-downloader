//
//  main.m
//  VoiceDataDownloader
//
//  Created by Phong Cao on 10/04/16.
//  Copyright © 2016 Microsoft. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DHxlsReader.h"
#import "VoiceDataDownloader.h"
#import "VoiceDataHelper.h"

// Sign up for subscription key at https://www.microsoft.com/cognitive-services
#define TEXT_TO_SPEECH_KEY      "Insert your subscription key here"

int main(int argc, const char * argv[])
{
    @autoreleasepool
    {
        // Check if there is any input file
        if (argc <= 2)
        {
            NSLog(@"Usage: TextToSpeechDownloader <filename.xls> <output dir>");
            return 0;
        }
        
        // Check if the input file can be opened
        NSString * path = [NSString stringWithUTF8String:argv[1]];
        DHxlsReader * reader = [DHxlsReader xlsReaderWithPath:path];
        if (!reader)
        {
            NSLog(@"Error: can't open %@ file", path);
            return 0;
        }
        
        // Reading settings and texts
        NSUInteger numSheets = [reader numberOfSheets];
        NSMutableArray<NSString *>* languageSettings = [[NSMutableArray<NSString *> alloc] init];
        NSMutableArray<NSString *>* voiceSettings = [[NSMutableArray<NSString *> alloc] init];
        NSMutableArray<NSString *>* speakingRateSettings = [[NSMutableArray<NSString *> alloc] init];
        NSMutableArray<NSMutableArray<NSString *>*>* texts = [[NSMutableArray<NSMutableArray<NSString *>*> alloc] init];
        
        for (int i = 0; i < numSheets; i++)
        {
            // Reading settings
            NSArray * setting = [[reader sheetNameAtIndex:i] componentsSeparatedByString:@"_"];
            
            // Check if the setting name is valid
            if ([setting count] != 3)
            {
                NSLog(@"Invalid setting name: %@", [reader sheetNameAtIndex:i]);
                continue;
            }
            
            // Reading language setting
            [languageSettings addObject:setting[0]];
            
            // Reading voice setting
            [voiceSettings addObject:setting[1]];
            
            // Reading speaking rate setting
            [speakingRateSettings addObject:setting[2]];
            
            // Reading texts
            [reader startIterator:i];
            texts[i] = [[NSMutableArray<NSString *> alloc] init];
            
            while (YES)
            {
                DHcell * cell = [reader nextCell];
                if (cell.type == cellBlank)
                {
                    break;
                }
                
                // Reading text
                [texts[i] addObject:[cell str]];
            }
        }
        
        // Initialize voice data downloader
        VoiceDataDownloader * downloader = [[VoiceDataDownloader alloc] initWithSubscriptionKey:@TEXT_TO_SPEECH_KEY];
        
        // Authenticate
        __block BOOL authenticated = NO;
        __block BOOL success = YES;
        [downloader authenticate:^(NSInteger statusCode, NSError * _Nullable error)
        {
            // Success
            if (statusCode != 200)
            {
                NSLog(@"Authentication error code: %ld", statusCode);
                success = NO;
            }
            
            authenticated = YES;
        }];
        
        // Wait for authentication
        while (!authenticated)
        {
            usleep(1000);
        }
        
        // Download text to speech data
        if (success)
        {
            [downloader downloadVoiceData:texts
                         languageSettings:languageSettings
                            voiceSettings:voiceSettings
                     speakingRateSettings:speakingRateSettings
                                outputDir:[NSString stringWithUTF8String:argv[2]]];
        }
        
        // Wait until downloader has completed
        while (downloader.downloadInProgress)
        {
            usleep(1000);
        }
    }
    
    return 0;
}
