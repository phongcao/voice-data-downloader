//
//  VoiceDataDownloader.m
//  VoiceDataDownloader
//
//  Created by Phong Cao on 10/3/16.
//  Copyright © 2016 Microsoft. All rights reserved.
//

#import "VoiceDataDownloader.h"

#define TEXT_TO_SPEECH_URL                              "https://speech.platform.bing.com/synthesize"
#define TEXT_TO_SPEECH_AUTH_URL                         "https://api.cognitive.microsoft.com/sts/v1.0/issueToken"
#define TEXT_TO_SPEECH_REQUEST_TIMEOUT                  30

#define BING_VOICE_OUTPUT_SILENCE_DETECTION_MARKER      "<break time='1s'/>"                  // Marker used to split data into small chunks
#define BING_VOICE_OUTPUT_CONCENCATION_MARKER           "<break time='0s'/>"                  // Marker used to concencate data
#define BING_VOICE_OUTPUT_SPEAKING_RATE_FORMAT          "<prosody rate='%@'>%@</prosody>"     // Speaking rate format
#define BING_VOICE_OUTPUT_ZERO_BYTES_IN_ONE_SECOND      27000                                 // Number of zero bytes in one second used for silence detection
#define BING_VOICE_OUTPUT_ZERO_BYTES_FOR_PADDING        20000                                 // Number of zero bytes used for padding at the end of wav file
#define BING_VOICE_OUTPUT_MAX_CHARACTERS                850                                   // Max characters that Bing Voice Output API supports
#define kRIFFWAVE_HEADER_SIZE                           44                                    // RIFF/WAVE Header size

// VoiceDataDownloader (Internal) interface
@interface VoiceDataDownloader (Internal)

// Format text so that it can be used as key in the cache
- (nonnull NSString *)formatText:(nonnull NSString *)text;

// Split batch data into an array of single data
- (NSArray<NSData *> *)splitBatchData:(NSData *)data;

// Get filename with settings
- (NSString *)getFileName:(NSString *)text
                 settings:(NSString *)settings;

// Generate url request for specific language and voice settings
- (NSMutableURLRequest *)getMutableURLRequest:(NSString *)text
                                     language:(NSString *)language
                                        voice:(NSString *)voice;

@end

// VoiceDataDownloader implementation
@implementation VoiceDataDownloader
{
@private
    // Stores the API token retrieved from the text to speech server
    NSString * _token;
}

// Add wav header
+ (NSMutableData *)addWavHeader:(NSData *) wavNoheader
{
    int headerSize = 44;
    long totalAudioLen = [wavNoheader length];
    long totalDataLen = [wavNoheader length] + headerSize-8;
    long longSampleRate = 16000.0;
    int channels = 1;
    long byteRate = 8 * 32000.0 * channels / 8;
    
    Byte *header = (Byte*)malloc(44);
    header[0] = 'R';  // RIFF/WAVE header
    header[1] = 'I';
    header[2] = 'F';
    header[3] = 'F';
    header[4] = (Byte) (totalDataLen & 0xff);
    header[5] = (Byte) ((totalDataLen >> 8) & 0xff);
    header[6] = (Byte) ((totalDataLen >> 16) & 0xff);
    header[7] = (Byte) ((totalDataLen >> 24) & 0xff);
    header[8] = 'W';
    header[9] = 'A';
    header[10] = 'V';
    header[11] = 'E';
    header[12] = 'f';  // 'fmt ' chunk
    header[13] = 'm';
    header[14] = 't';
    header[15] = ' ';
    header[16] = 16;  // 4 bytes: size of 'fmt ' chunk
    header[17] = 0;
    header[18] = 0;
    header[19] = 0;
    header[20] = 1;  // format = 1
    header[21] = 0;
    header[22] = (Byte) channels;
    header[23] = 0;
    header[24] = (Byte) (longSampleRate & 0xff);
    header[25] = (Byte) ((longSampleRate >> 8) & 0xff);
    header[26] = (Byte) ((longSampleRate >> 16) & 0xff);
    header[27] = (Byte) ((longSampleRate >> 24) & 0xff);
    header[28] = (Byte) (byteRate & 0xff);
    header[29] = (Byte) ((byteRate >> 8) & 0xff);
    header[30] = (Byte) ((byteRate >> 16) & 0xff);
    header[31] = (Byte) ((byteRate >> 24) & 0xff);
    header[32] = (Byte) (2 * 8 / 8);  // block align
    header[33] = 0;
    header[34] = 16;  // bits per sample
    header[35] = 0;
    header[36] = 'd';
    header[37] = 'a';
    header[38] = 't';
    header[39] = 'a';
    header[40] = (Byte) (totalAudioLen & 0xff);
    header[41] = (Byte) ((totalAudioLen >> 8) & 0xff);
    header[42] = (Byte) ((totalAudioLen >> 16) & 0xff);
    header[43] = (Byte) ((totalAudioLen >> 24) & 0xff);
    
    NSMutableData * newWavData = [NSMutableData dataWithBytes:header
                                                       length:44];
    
    [newWavData appendBytes:[wavNoheader bytes]
                     length:[wavNoheader length]];
    
    return newWavData;
}

// Class initializer
- (nullable instancetype)initWithSubscriptionKey:(nonnull NSString *)subscriptionKey
{
    // Initialize superclass
    self = [super init];
    
    // Handle errors
    if (!self)
    {
        return nil;
    }
    
    _subscriptionKey = subscriptionKey;
    _token = nil;
    _downloadInProgress = NO;
    
    // Done
    return self;
}

- (void)authenticate:(TextToSpeechAuthenticationCallback)callback
{
    // Construct the URL request
    NSMutableURLRequest * mutableURLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@TEXT_TO_SPEECH_AUTH_URL]];
    [mutableURLRequest setHTTPMethod:@"POST"];
    
    // Add the request headers
    [mutableURLRequest setValue:_subscriptionKey
             forHTTPHeaderField:@"Ocp-Apim-Subscription-Key"];
    
    // Send the URL request
    NSURLSessionDataTask * task = [[NSURLSession sharedSession] dataTaskWithRequest:mutableURLRequest
                                                                  completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error)
                                   {
                                       NSHTTPURLResponse * httpResponse = (NSHTTPURLResponse *)response;
                                       NSInteger statusCode = [httpResponse statusCode];
                                       if (statusCode == 200)
                                       {
                                           _token = [[NSString alloc] initWithData:data
                                                                          encoding:NSASCIIStringEncoding];
                                       }
                                       
                                       callback(statusCode, error);
                                   }];
    [task resume];
}

// Download the voice data of the provided texts and settings
- (void)downloadVoiceData:(NSMutableArray<NSMutableArray<NSString *> *> *) texts
         languageSettings:(NSMutableArray<NSString *> *) languageSettings
            voiceSettings:(NSMutableArray<NSString *> *)voiceSettings
     speakingRateSettings:(NSMutableArray<NSString *> *) speakingRateSettings
                outputDir:(NSString *)outputDir
{
    if (!_token)
    {
        NSLog(@"Authentication is required!");
        return;
    }
    
    _downloadInProgress = YES;
    
    // Zero bytes array used for padding at the end of wav file
    NSMutableData * zeroBytesArrayForPadding = [[NSMutableData alloc] initWithLength:BING_VOICE_OUTPUT_ZERO_BYTES_FOR_PADDING];
    
    NSMutableArray<NSURLSessionDataTask *>* downloadTasks = [[NSMutableArray<NSURLSessionDataTask *> alloc] init];
    NSMutableArray<NSMutableArray<NSData *>*>* completedData = [[NSMutableArray<NSMutableArray<NSData *>*> alloc] init];
    
    for (int i = 0; i < [languageSettings count]; i++)
    {
        // Initialize the text batch elements basing on the max characters of Bing Voice Output API
        
        // Allocate the text batch
        NSMutableArray<NSMutableArray<NSString *>*>* textBatch = [[NSMutableArray<NSMutableArray<NSString *>*> alloc] init];
        completedData[i] = [[NSMutableArray<NSData *> alloc] init];
        
        // Calculate the marker length
        NSUInteger markerLength = [@BING_VOICE_OUTPUT_SILENCE_DETECTION_MARKER length];
        NSString * speakingRateValue = speakingRateSettings[i];
        
        // Adding the speaking rate paramater if it's not default
        if (![speakingRateValue isEqualToString:@"1"])
        {
            markerLength += [@BING_VOICE_OUTPUT_SPEAKING_RATE_FORMAT length] + [speakingRateValue length];
        }
        
        int j = 0;
        
        // Iterate each text
        while (j < [texts[i] count])
        {
            // Create an array to store text
            NSMutableArray<NSString *>* textSingleBatch = [[NSMutableArray<NSString *> alloc] init];
            int length = 0;
            
            // Check if the size of array is over the max characters
            while ((j < [texts[i] count]) && ((length + [[self formatText:[texts[i] objectAtIndex:j]] length] + markerLength) < BING_VOICE_OUTPUT_MAX_CHARACTERS))
            {
                NSString * text = [texts[i] objectAtIndex:j++];
                NSString * formattedText = [self formatText:text];
                [textSingleBatch addObject:formattedText];
                length += [formattedText length] + markerLength;
            }
            
            // Add array to the text batch
            if ([textSingleBatch count])
            {
                [textBatch addObject:textSingleBatch];
            }
        }
        
        // Caching data from the text batch
        for (NSMutableArray<NSString *>* textSingleBatch in textBatch)
        {
            // Create the concencated text from all single texts that need to be cached
            NSMutableString * concencatedText = [[NSMutableString alloc] init];
            
            for (NSString * text in textSingleBatch)
            {
                NSString * formattedText = [self formatText:text];
                
                // Adding the speaking rate paramater if it's not default
                if (![speakingRateValue isEqualToString:@"1"])
                {
                    formattedText = [NSString stringWithFormat:@BING_VOICE_OUTPUT_SPEAKING_RATE_FORMAT, speakingRateValue, formattedText];
                }
                
                [concencatedText appendString:formattedText];
                
                // Append the marker used to split later
                [concencatedText appendString:@BING_VOICE_OUTPUT_SILENCE_DETECTION_MARKER];
            }
            
            NSURLSessionDataTask * task = [[NSURLSession sharedSession] dataTaskWithRequest:[self getMutableURLRequest:concencatedText
                                                                                                              language:languageSettings[i]
                                                                                                                 voice:voiceSettings[i]]
                                                                          completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error)
                                           {
                                               // Get the HTTPURLResponse
                                               NSHTTPURLResponse * httpResponse = (NSHTTPURLResponse *)response;
                                               NSInteger statusCode = [httpResponse statusCode];
                                               
                                               if (!error && data.length)
                                               {
                                                   // Successfully
                                                   if (statusCode == 200)
                                                   {
                                                       // Split the batch data into an array of single data
                                                       NSArray<NSData *>* splitData = [self splitBatchData:data];
                                                       
                                                       if ([splitData count] == [textSingleBatch count])
                                                       {
                                                           [completedData[i] addObjectsFromArray:splitData];
                                                           
                                                           // Display status
                                                           for (NSString * text in textSingleBatch)
                                                           {
                                                               NSLog(@"Downloaded '%@'", [self getFileName:text
                                                                                                  settings:[NSString stringWithFormat:@"%@_%@_%@", languageSettings[i], voiceSettings[i], speakingRateSettings[i]]]);
                                                           }
                                                       }
                                                   }
                                                   else
                                                   {
                                                       NSLog(@"Request error: %ld", statusCode);
                                                   }
                                               }
                                               
                                               // Remove the completed task
                                               [downloadTasks removeObjectAtIndex:0];
                                               
                                               // Start the next task
                                               if ([downloadTasks count])
                                               {
                                                   [[downloadTasks firstObject] resume];
                                               }
                                           }];
            
            // Add task to the download queue
            [downloadTasks addObject:task];
        }
    }
    
    if ([downloadTasks count])
    {
        [[downloadTasks firstObject] resume];
    }
    
    // Waiting for all downloading tasks to be completed...
    while ([downloadTasks count]);
    
    // Write text to speech data to files
    
    NSString * outputBinDir = [NSString stringWithFormat:@"%@/bin", outputDir];
    NSString * outputWavDir = [NSString stringWithFormat:@"%@/wav", outputDir];
    
    // Remove old dirs
    [[NSFileManager defaultManager] removeItemAtPath:outputBinDir
                                               error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:outputWavDir
                                               error:nil];
    
    // Create new dirs
    [[NSFileManager defaultManager] createDirectoryAtPath:outputBinDir
                              withIntermediateDirectories:NO
                                               attributes:nil
                                                    error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:outputWavDir
                              withIntermediateDirectories:NO
                                               attributes:nil
                                                    error:nil];
    
    for (int i = 0; i < [languageSettings count]; i++)
    {
        NSMutableData * fileData = [[NSMutableData alloc] init];
        
        for (int j = 0; j < [texts[i] count]; j++)
        {
            // Write text length
            NSUInteger textLength = [texts[i][j] length];
            [fileData appendData:[NSData dataWithBytes:&textLength
                                                length:sizeof(textLength)]];
            
            // Write text
            [fileData appendData:[texts[i][j] dataUsingEncoding:NSASCIIStringEncoding]];
            
            // Write data length
            NSUInteger dataLength = [completedData[i][j] length];
            [fileData appendData:[NSData dataWithBytes:&dataLength
                                                length:sizeof(dataLength)]];
            
            // Concencate data
            [fileData appendData:completedData[i][j]];
            
            // Write data to wav file
            NSMutableData * wavData = [[NSMutableData alloc] initWithData:completedData[i][j]];
            wavData = [NSMutableData dataWithData:[VoiceDataDownloader addWavHeader:wavData]];
            [wavData appendData:zeroBytesArrayForPadding];
            [wavData writeToFile:[NSString stringWithFormat:@"%@/%@", outputWavDir, [self getFileName:texts[i][j]
                                                                                             settings:[NSString stringWithFormat:@"%@_%@_%@", languageSettings[i], voiceSettings[i], speakingRateSettings[i]]]]
                      atomically:YES];
        }
        
        // Write data to bin file
        [fileData writeToFile:[NSString stringWithFormat:@"%@/%@_%@_%@.bin", outputBinDir, languageSettings[i], voiceSettings[i], speakingRateSettings[i]]
                   atomically:YES];
    }
    
    _downloadInProgress = NO;
}

@end

// VoiceDataDownloader (Internal) implementation
@implementation VoiceDataDownloader (Internal)

// Format text so that it can be used as key in the cache
- (NSString *)formatText:(NSString *)text
{
    NSCharacterSet * punctuations = [NSCharacterSet characterSetWithCharactersInString:@".,?!"];
    NSCharacterSet * specialCharacters = [NSCharacterSet characterSetWithCharactersInString:@"!"];
    NSString * formattedText = text;
    
    // Remove the last punctuation
    if ([[formattedText substringFromIndex:[formattedText length] - 1] rangeOfCharacterFromSet:punctuations].location != NSNotFound)
    {
        formattedText = [formattedText substringToIndex:[formattedText length] - 1];
    }
    
    // Remove the special characters that can cause confusion to marker detection
    formattedText = [[formattedText componentsSeparatedByCharactersInSet:specialCharacters] componentsJoinedByString:@""];
    
    // The TTS parser doesn’t like the ampersand so we must replace of & -> ‘and’
    formattedText = [formattedText stringByReplacingOccurrencesOfString:@"&"
                                                             withString:@"and"];
    
    return formattedText;
}

// Get filename with settings
- (NSString *)getFileName:(NSString *)text
                 settings:(NSString *)settings
{
    NSCharacterSet * specialCharacters = [NSCharacterSet characterSetWithCharactersInString:@".,?!'/\\&@#~*()-+:\"<>[]{}="];
    
    NSString * formattedText = [text lowercaseString];
    formattedText = [[formattedText componentsSeparatedByCharactersInSet:specialCharacters] componentsJoinedByString:@""];
    formattedText = [formattedText stringByReplacingOccurrencesOfString:@" "
                                                             withString:@"_"];
    formattedText = [formattedText stringByReplacingOccurrencesOfString:@"/"
                                                             withString:@"_"];
    
    NSString * fileName = [NSString stringWithFormat:@"%@_%@.wav", settings, formattedText];
    
    return fileName;
}

// Generate url request for specific language and voice settings
- (NSMutableURLRequest *)getMutableURLRequest:(NSString *)text
                                     language:(NSString *)language
                                        voice:(NSString *)voice
{
    // Construct the URL request
    NSMutableURLRequest * mutableURLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@TEXT_TO_SPEECH_URL]
                                                                      cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                                  timeoutInterval:TEXT_TO_SPEECH_REQUEST_TIMEOUT];
    [mutableURLRequest setHTTPMethod:@"POST"];
    
    // Construct the request
    NSString * request = [[NSString alloc] initWithFormat:@"<speak version='1.0' xml:lang='en-US'><voice xml:lang='%@' xml:gender='%@' name='Microsoft Server Speech Text to Speech Voice (en-US, ZiraRUS)'>%@</voice></speak>", language, voice, text];

    // Convert the request to data
    NSData * requestData = [request dataUsingEncoding:NSASCIIStringEncoding];
    
    // Add the request data
    [mutableURLRequest setHTTPBody:requestData];
    
    // Add the request headers
    [mutableURLRequest setValue:[[NSString alloc] initWithFormat:@"Bearer %@", _token]
             forHTTPHeaderField:@"Authorization"];
    
    [mutableURLRequest setValue:@"text/plain; charset=utf-8"
             forHTTPHeaderField:@"Content-Type"];
    
    [mutableURLRequest setValue:@"riff-16khz-16bit-mono-pcm"
             forHTTPHeaderField:@"X-Microsoft-OutputFormat"];
    
    [mutableURLRequest setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[requestData length]]
             forHTTPHeaderField:@"Content-Length"];
    
    return mutableURLRequest;
}

// Split batch data into an array of single data
- (NSArray<NSData *>*)splitBatchData:(NSData *)data
{
    // Zero bytes array used for silence detection
    NSMutableData * zeroBytesArrayForSilenceDetection = [[NSMutableData alloc] initWithLength:BING_VOICE_OUTPUT_ZERO_BYTES_IN_ONE_SECOND];
    
    NSMutableArray<NSData *>* results = [[NSMutableArray<NSData *> alloc] init];
    NSMutableData * mutableData = [NSMutableData dataWithData:[data subdataWithRange:NSMakeRange(kRIFFWAVE_HEADER_SIZE, [data length] - kRIFFWAVE_HEADER_SIZE)]];
    NSRange range = [mutableData rangeOfData:zeroBytesArrayForSilenceDetection
                                     options:0
                                       range:NSMakeRange(0, [mutableData length])];
    
    NSUInteger startPos = 0;
    
    while (range.location != NSNotFound)
    {
        NSRange entryRange = NSMakeRange(startPos, range.location - startPos);
        NSData * entryData = [mutableData subdataWithRange:entryRange];
        [results addObject:entryData];
        startPos = range.location + range.length;
        
        // 16 bit aligned
        if (startPos % 2)
        {
            startPos++;
        }
        
        range = [mutableData rangeOfData:zeroBytesArrayForSilenceDetection
                                 options:0
                                   range:NSMakeRange(startPos, [mutableData length] - startPos)];
    }
    
    return results;
}

@end
