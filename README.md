# multimedia-organizer
move multimedia from android and apple mobile phones and organize by date folders

## temporary struture
* BIG PLAN.ps1 - main executable
* mptcopy.ps1 - function to execute move of file from mobile to PC using MPT protocol (currently used for iPhone)
* exiftool.exe - opensource tool version 12.29 , the one tested for our case (although should work with newer)
* .ExifTool_config - configuration file for exiftool, prepared to retrieve the oldest date found per file
