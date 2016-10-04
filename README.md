# Voice Data Downloader
A utility that downloads the voice data for strings in an xls file and compacted into a single binary file. It uses [Bing Text To Speech API](https://www.microsoft.com/cognitive-services/en-us/Speech-api/documentation/API-Reference-REST/BingVoiceOutput) to produce synthesized speech from text.

## Configuration
You need to update your subscription key in **main.m** file. If you don't have one, please sign up for it at [Microsoft Cognitive Services website](https://www.microsoft.com/cognitive-services).

## Settings
Voice Data Downloader supports language, voice and speaking rate settings. These parameters are configurable via the sheet name of the xls file:

```
[language]_[voice]_[speaking rate]
```

For example, if you want both US male and US female voice data, you need to create two following sheets in the xls file:

```
|en-us_male_1.0|en-us_female_1.0|
```

Each sheet can contain same or different strings depending on what you need.

### Language
The supported languages are:
* en-us
* en-gb

### Voice
The supported voices are:
* female
* male

### Speaking rate
This value may be expressed in one of two ways:
* A relative value, expressed as a number that acts as a multiplier of the default. For example, a value of 1 results in no change in the rate. A value of .5 results in a halving of the rate. A value of 3 results in a tripling of the rate.
* An enumeration value, from among the following: x-slow, slow, medium, fast, x-fast, or default. 

## How to use
The command line syntax is:

```
VoiceDataDownloader <filename.xls> <output dir>
```

There are two subdirectories in the output directory. The **wav** directory contains all WAV files and the **bin** directory contains all binary files.

## Binary files (.bin)
Bin file contains the compacted voice data for strings in the sheet. If there are 100 strings in the sheet, the output is one bin file instead of 100 WAV files. This not only helps organize resources in a much cleaner way but also reduces the size since the WAV header has been stripped before adding to bin file.
In order to load the bin files and extract voice data, you can use the **VoiceDataHelper** class.
