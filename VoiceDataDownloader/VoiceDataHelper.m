//
//  VoiceDataHelper.m
//  VoiceDataDownloader
//
//  Created by Phong Cao on 10/4/16.
//  Copyright © 2016 Microsoft. All rights reserved.
//

#import "VoiceDataHelper.h"
#import "VoiceDataDownloader.h"

@implementation VoiceDataHelper

// Extracts voice data from bin files to the provided output directory
// Sample usage:
//
//      NSArray<NSString *>* binFiles = @[@"./bin/en-gb_female_0.5.bin",
//                                        @"./bin/en-gb_female_1.0.bin",
//                                        @"./bin/en-gb_female_2.0.bin"];
//      [VoiceDataHelper extractBinFiles:binFiles
//                             outputDir:@"./extract"
//
// Note: The 'extract' directory must exist
+ (void)extractBinFiles:(NSArray<NSString *> *)binFiles
              outputDir:(NSString *)outputDir
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:outputDir])
    {
        NSLog(@"Invalid output directory: %@", outputDir);
        return;
    }
    
    // Load utterances
    for (NSString * file in binFiles)
    {
        if (![[NSFileManager defaultManager] fileExistsAtPath:file])
        {
            NSLog(@"File not found: %@", file);
            continue;
        }
        
        NSString * settings = [file substringToIndex:[file rangeOfString:@".bin"].location];
        settings = [settings substringFromIndex:[settings rangeOfString:@"/"
                                                                options:NSBackwardsSearch].location + 1];
        NSFileHandle * fileHandle = [NSFileHandle fileHandleForReadingAtPath:file];
        unsigned long long fileSize = [fileHandle seekToEndOfFile];
        NSUInteger offset = 0;
        [fileHandle seekToFileOffset:offset];
        
        while (offset < fileSize)
        {
            // Read text length
            NSUInteger textLength = 0;
            NSData * textLengthData = [fileHandle readDataOfLength:sizeof(textLength)];
            [textLengthData getBytes:&textLength length: sizeof(textLength)];
            offset += sizeof(textLength);
            
            // Read text
            NSData * textData = [fileHandle readDataOfLength:textLength];
            NSString * text = [[NSString alloc] initWithData:textData
                                                    encoding:NSASCIIStringEncoding];
            offset += textLength;
            
            // Read utterance length
            NSUInteger utteranceLength = 0;
            NSData * utteranceLengthData = [fileHandle readDataOfLength:sizeof(utteranceLength)];
            [utteranceLengthData getBytes:&utteranceLength length: sizeof(utteranceLength)];
            offset += sizeof(utteranceLength);
            
            // Read utterance
            NSData * utterance = [fileHandle readDataOfLength:utteranceLength];
            offset += utteranceLength;
            
            // Format text
            NSString * formattedText = [text lowercaseString];
            formattedText = [[formattedText componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@".,?!'/\\&@#~*()-+:\"<>[]{}="]] componentsJoinedByString:@""];
            formattedText = [formattedText stringByReplacingOccurrencesOfString:@" "
                                                                     withString:@"_"];
            formattedText = [formattedText stringByReplacingOccurrencesOfString:@"/"
                                                                     withString:@"_"];
            
            // Write file
            NSString * fileName = [NSString stringWithFormat:@"%@_%@.wav", settings, formattedText];
            NSString * fullFileName = [outputDir stringByAppendingPathComponent:fileName];
            NSMutableData * wavData = [[NSMutableData alloc] initWithData:[VoiceDataDownloader addWavHeader:utterance]];
            [wavData writeToFile:fullFileName
                      atomically:YES];
        }
        
        [fileHandle closeFile];
    }
}

@end
