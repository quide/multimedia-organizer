# Windows Powershell Script to move a set of files (based on a filter) from a folder
# on a MTP device (e.g. iPhone and Android phone) to a folder on a computer, using the Windows Shell.
# By Daiyan Yingyu, 19 March 2018, and changed by Pedro Reis in 2023 based on the (non-working) script found here:
#   https://www.pstips.net/access-file-system-against-mtp-connection.html
# as referenced here:
#   https://powershell.org/forums/topic/powershell-mtp-connections/
#
# This Powershell script is provided 'as-is', without any express or implied warranty.
# In no event will the author be held liable for any damages arising from the use of this script.
#
# Again, please note that used 'as-is' this script will MOVE files from you phone:
# the files will be DELETED from the source (the phone) and MOVED to the computer.
#
# If you want to copy files instead, you can replace the MoveHere function call with "CopyHere" instead.
# But once again, the author can take no responsibility for the use, or misuse, of this script.</em>
#
param([string]$phoneName,[string]$sourceFolder,[string]$targetFolder,[string]$filter='(.*)')
 
function Get-ShellProxy
{
    if( -not $global:ShellProxy)
    {
        $global:ShellProxy = new-object -com Shell.Application
    }
    $global:ShellProxy
}
 
function Get-Phone
{
    param($phoneName)
    $shell = Get-ShellProxy
    # 17 (0x11) = ssfDRIVES from the ShellSpecialFolderConstants (https://msdn.microsoft.com/en-us/library/windows/desktop/bb774096(v=vs.85).aspx)
    # => "My Computer" — the virtual folder that contains everything on the local computer: storage devices, printers, and Control Panel.
    # This folder can also contain mapped network drives.
    $shellItem = $shell.NameSpace(17).self
    $phone = $shellItem.GetFolder.items() | where { $_.name -eq $phoneName }
    # $PhoneFolder = ($shell.NameSpace("shell:MyComputerFolder").Items() | where Type -eq 'Mobile Phone').GetFolder
    return $phone
}
 
function Get-SubFolder
{
    param($parent,[string]$path)
    $pathParts = @( $path.Split([system.io.path]::DirectorySeparatorChar) )
    $current = $parent
    foreach ($pathPart in $pathParts)
    {
        if ($pathPart)
        {
            $current = $current.GetFolder.items() | where { $_.Name -eq $pathPart }
        }
    }
    return $current
}
 
$phoneFolderPath = $sourceFolder
$destinationFolderPath = $targetFolder
# If destination path doesn't exist, create it only if we have some items to move
if (-not (test-path $destinationFolderPath) )        {
    $created = new-item -itemtype directory -path $destinationFolderPath
}
 
$phone = Get-Phone -phoneName $phoneName
$folder = Get-SubFolder -parent $phone -path $phoneFolderPath

if( $folder -eq $null ){ 
    echo "INFO: NO PHONE FOLDERS TO MOVE"
} else {
    $subfolders = $folder.GetFolder.items()
    foreach ($subfolder in $subfolders) {    
        #if( $subfolder.name -like "2020*" )
        if( $subfolder.name -like "*" ) # pass anything
        {
            # As this is being used for iPhone, just get everything (multimedia files)
            $items = @( $subfolder.GetFolder.items() )
            #$items = @( $subfolder.GetFolder.items() | where { $_.Name -match $filter } )

            # To avoid same filename-for-different-multimedia issues, add additional sub-folders to the destination path, such as one based on date
            $destinationSubFolderPath = $destinationFolderPath + "\" + $subfolder.name

            if($items) {
                $totalItems = $items.count
                if($totalItems -gt 0)    {
                    # If destination path doesn't exist, create it (only if we have some items to move)
                    if (-not (test-path $destinationSubFolderPath) )        {
                        $created = new-item -itemtype directory -path $destinationSubFolderPath
                    }
 
                    Write-Verbose "Processing Path : $phoneName\$phoneFolderPath"
                    Write-Verbose "Moving to : $destinationSubFolderPath"
 
                    $shell = Get-ShellProxy
                    $destinationFolder = $shell.Namespace($destinationSubFolderPath).self
                    $count = 0;
                    foreach ($item in $items)
                    {
                        $fileName = $item.Name
                        $original_fileName = $fileName
 
                        ++$count
                        $percent = [int](($count * 100) / $totalItems)
                        Write-Progress -Activity "Processing Files in $phoneName\$phoneFolderPath\$($subfolder.name)" `
                            -status "Moving File ${count} / ${totalItems} (${percent}%)" `
                            -CurrentOperation $fileName `
                            -PercentComplete $percent
 
                        # Check the target file doesn't exist:
                        $targetFilePath = join-path -path $destinationSubFolderPath -childPath $fileName
                        if (test-path -path $targetFilePath)
                        {
                            # echo "WARNING: Destination file exists - file not moved:`n`t$targetFilePath"
                            # TODO: check size of files and if equal remove from mobile; if diff: copy with renaming the file to *_to_check

                            #$destinationFolder.GetFolder.MoveHere($item, (8)) # rename if needed
                            #$destinationFolder.GetFolder.MoveHere($item, 0x08) # rename if needed
                            # (0) Default. No options specified.
                            # (4) Do not display a progress dialog box.
                            # (8) Rename the target file if a file exists at the target location with the same name.
                            # (16) Click "Yes to All" in any dialog box displayed.
                            # &H0& - Displays a progress dialog box that shows the name of each file being copied.
                            # &H4& - Copies files without displaying a dialog box.
                            # &H8& - Automatically creates a new folder name if a folder with that same name already exists.
                            # &H10& - Automatically responds "Yes to All" to any dialog box that appears. For example, if you attempt to copy over existing files, a dialog box appears, asking whether you are sure you want to copy over each file. Selecting this option is identical to clicking Yes to All within that dialog box.
                        
                            # find unique filename
                            $filename_count = 1
                            while (test-path -path $targetFilePath){
                               $baseName  = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                               $extension = [System.IO.Path]::GetExtension($fileName)
                               $fileName = "{0}-{1}{2}" -f $baseName, $filename_count++, $extension
                               $targetFilePath = join-path -path $destinationSubFolderPath -childPath $fileName
                            }

                            # copy to temp folder (because stupid MoveHere() doesn't allow rename and Move-Item not moving from COM folders)
                            $destinationSubFolderPath_temp = $destinationFolderPath + "\temp"
                            if (-not (test-path $destinationSubFolderPath_temp) )        {
                                $created = new-item -itemtype directory -path $destinationSubFolderPath_temp
                            }
                            Write-Verbose "Moving to : $destinationSubFolderPath_temp"
                            $destinationFolder_temp = $shell.Namespace($destinationSubFolderPath_temp).self
                            $destinationFolder_temp.GetFolder.MoveHere($item)

                            # rename + move from temp folder to final folder
                            Move-Item -Path $destinationSubFolderPath_temp\$original_fileName -Destination $targetFilePath

                            #$item_path = $item.path
                            #Move-Item -Path $item.path -Destination $targetFilePath
                            #Move-Item $item -Destination $targetFilePath
                            echo "WARNING: Destination file exists - file renamed for the moving:`n`t$targetFilePath"
                        }
                        else
                        {
                            $destinationFolder.GetFolder.MoveHere($item)
                            #$destinationFolder.GetFolder.CopyHere($item)
                            if (test-path -path $targetFilePath)
                            {
                                # Optionally do something with the file, such as modify the name (e.g. removed phone-added prefix, etc.)
                            }
                            else
                            {
                                write-error "Failed to move file to destination:`n`t$targetFilePath"
                            }
                        }
                    }
                }
            }
        }
    }
}