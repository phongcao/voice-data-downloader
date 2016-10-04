//
//  VoiceDataHelper.h
//  VoiceDataDownloader
//
//  Created by Phong Cao on 10/4/16.
//  Copyright © 2016 Microsoft. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface VoiceDataHelper : NSObject

// Extracts voice data from bin files to the provided output directory
+ (void)extractBinFiles:(NSArray<NSString *> *)binFiles
              outputDir:(NSString *)outputDir;

@end
