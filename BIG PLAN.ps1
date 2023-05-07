#TODO:
# -1) se necessário corrigir datas à mão
# exiftool.exe -r -overwrite_original -ext jpg '-DateTimeOriginal="1981:05:09 12:00:00"'  .exiftool.exe -r -overwrite_original -ext jpg '-DateTimeOriginal="1981:05:09 12:00:00"'  .
    

Function ConvertTo-Boolean {
    param($Variable)
    If ($Variable -eq "y") {
        $True
    } else {
        $False
    }
}

Function Extract-String {
    Param(
        [Parameter(Mandatory=$true)][string]$string
        , [Parameter(Mandatory=$true)][char]$character
        , [Parameter(Mandatory=$false)][ValidateSet("Right","Left")][string]$range
        , [Parameter(Mandatory=$false)][int]$afternumber
        , [Parameter(Mandatory=$false)][int]$tonumber
    )
    Process
    {
        [string]$return = ""

        if ($range -eq "Right")
        {
            $return = $string.Split("$character")[($string.Length - $string.Replace("$character","").Length)]
        }
        elseif ($range -eq "Left")
        {
            $return = $string.Split("$character")[0]
        }
        elseif ($tonumber -ne 0)
        {
            for ($i = $afternumber; $i -le ($afternumber + $tonumber); $i++)
            {
                $return += $string.Split("$character")[$i]
            }
        }
        else
        {
            $return = $string.Split("$character")[$afternumber]
        }

        return $return
    }
}

Function Move-Folder-Android {
    Param(
          [Parameter(Mandatory=$true)][string]$rfolder
        , [Parameter(Mandatory=$true)][string]$rfolder_sub
        , [Parameter(Mandatory=$false)][string]$intermediary_path
    )

    $rfolder_sub_w_treated_spaces = $rfolder_sub | % {$_ -replace ' ','\ '}

    $Emtpy_or_non_existent = $true
    if (test-path $intermediary_path/$rfolder_sub) {
        $directoryInfo = Get-ChildItem $intermediary_path/$rfolder_sub | Measure-Object
        if ($directoryInfo.count -ne 0){ $Emtpy_or_non_existent = $false }
    } 
    if( $false -eq $Emtpy_or_non_existent ) {
        echo "'$intermediary_path/$rfolder_sub' folder is not empty!"
        echo "comparing what lacks and just copy that? ..."
        pause
        # https://android.stackexchange.com/questions/40459/how-to-pull-only-newer-files-with-adb-pull-android-sdk-utility
        $android_file = "android.csv"

        $global:LASTEXITCODE = 0
        Invoke-Expression "& adb shell stat -c `"%n,%s`" `"$rfolder/$rfolder_sub_w_treated_spaces/*`" > $android_file"

        if($LASTEXITCODE){
            echo "Couldn't run adb stat at `"$rfolder/$rfolder_sub_w_treated_spaces/*`" "
            Invoke-Expression "& EchoArgs shell stat -c `"%n,%s`" `"$rfolder/$rfolder_sub_w_treated_spaces/*`""
            Remove-Item $android_file
            return
        }

        # remove full path from filename
        $lines=(Get-Content $android_file) | foreach{ Extract-String -string $_ -character "/" -range Right}  
        $lines > $android_file

        $local_file = "local.csv"
        Get-ChildItem -Path $intermediary_path/$rfolder_sub | ForEach {
            [PSCustomObject]@{
                Name = $_.Name
                Size = $_.length
            }
        } | ConvertTo-Csv -NoTypeInformation | % {$_ -replace '"',''} | Out-File $local_file
        # remove header
        (Get-Content $local_file | Select-Object -Skip 1) | Set-Content $local_file
                    
        # what is new (file name + size)
        filter leftside{
            param(
                    [Parameter(Position=0, Mandatory=$true,ValueFromPipeline = $true)]
                    [ValidateNotNullOrEmpty()]
                    [PSCustomObject]
                    $obj
                )

                $obj|?{$_.sideindicator -eq '<='}
        }
        $files_to_copy = compare-object (get-content $android_file) (get-content $local_file) | leftside
        $lines = ($files_to_copy) | foreach-object{ Extract-String -string $_ -character "," -range Left}
        $lines = ($lines) | foreach-object{ Extract-String -string $_ -character "=" -range Right} 

        # just copy what is new
        ForEach ($file in $($lines -split "`r`n")){
            try {
                Invoke-Expression "& adb pull `"$rfolder/$rfolder_sub/$file`" `"$intermediary_path/$rfolder_sub`""
            } catch {
                echo "failed when running following adb command:"
                Invoke-Expression "& EchoArgs pull `"$rfolder/$rfolder_sub/$file`" `"$intermediary_path/$rfolder_sub`""
                return
            }
        }

        # Verify copy was done correctly:
        Get-ChildItem -Path $intermediary_path/$rfolder_sub | ForEach {
            [PSCustomObject]@{
                Name = $_.Name
                Size = $_.length
            }
        } | ConvertTo-Csv -NoTypeInformation | % {$_ -replace '"',''} | Out-File $local_file
        # remove header
        (Get-Content $local_file | Select-Object -Skip 1) | Set-Content $local_file

        $files_to_copy = compare-object (get-content $android_file) (get-content $local_file) | leftside

        if( $files_to_copy ){
            echo "ERROR: some problem happened, as we still have stuff to be copied!"
            return
        }

        Remove-Item $android_file
        Remove-Item $local_file

        # return
    } else { # folder empty
        try {
            Invoke-Expression "& adb pull -a `"$rfolder/$rfolder_sub`" `"$intermediary_path`""
        } catch {
            echo "failed when running following adb command:"
            Invoke-Expression "& EchoArgs pull -a `"$rfolder/$rfolder_sub`" `"$intermediary_path`""
            return
        }
    }

    echo "Removing all stuff from `"$rfolder/$rfolder_sub_w_treated_spaces`" now ..."
    pause
    try {
        echo "Pacience please; this may take a while ..."
        Invoke-Expression "& adb -d shell rm -rf `"$rfolder/$rfolder_sub_w_treated_spaces`""
    } catch {
        echo "failed when running remove adb command"
        return
    }
}

$base_path="$pwd\.." #"C:\Users\Pedro\Desktop\PEDRO\P DISCO"

# add bin to path
#$env:Path += ';' + $pwd # bin 
$ENV:PATH=”$ENV:PATH;$pwd\..\bin”

$intermediary_path = $base_path + "\por arranjar"

$output_path = $base_path + "\MULTIMEDIA ARRANJADA"
echo "Directoria de saída: $output_path"

$from_mobile = Read-Host "Are you importing from mobile phone? (y/N)"
$from_mobile = ConvertTo-Boolean -Variable $from_mobile

if ($from_mobile ) {
    $is_android = Read-Host "Are you importing from Android? (y/N)"
    $is_android = ConvertTo-Boolean -Variable $is_android

    if ($is_android ) {
        $intermediary_path = $base_path + "\por arranjar - android"

        try {
            $global:LASTEXITCODE = 0
            Invoke-Expression "& adb root"
            if($LASTEXITCODE){
                echo "Failure trying to connect to your android. On your mobile, you need to:"
                echo " 1) click version build several times" 
                echo " 2) activate programmer options" 
                echo " 3) activate debug (depuração) USB"
                echo " 4) run this + allow at mobile screen"
                return
            }
        } catch {
            echo "Failure trying to connect to your android. On your mobile, you need to:"
            echo " 1) click version build several times" 
            echo " 2) activate programmer options" 
            echo " 3) activate debug (depuração) USB"
            echo " 4) run this + allow at mobile screen"
            return
        }

        if (test-path $intermediary_path) {
        } else { #folder doesn't exist
            echo "'$intermediary_path' folder doesn't exist! Create it?"
            pause
            New-Item -Path "$intermediary_path\.." -Name "por arranjar - android" -ItemType "directory"
            # TODO
            return
        }

        Move-Folder-Android -rfolder "/sdcard/DCIM" -rfolder_sub "Camera" -intermediary_path $intermediary_path
        Move-Folder-Android -rfolder "/sdcard/Android/media/com.whatsapp/WhatsApp/Media" -rfolder_sub "WhatsApp Images" -intermediary_path $intermediary_path
        Move-Folder-Android -rfolder "/sdcard/Android/media/com.whatsapp/WhatsApp/Media" -rfolder_sub "WhatsApp Video" -intermediary_path $intermediary_path

        echo " Antes de continuar é melhor apagar coisas que vieram do WhatsApp ..."
        
    } else {
        $intermediary_path = $base_path + "\por arranjar - iphone"
		
		if (test-path $intermediary_path) {
            # no probl
        } else { #folder doesn't exist
            echo "'$intermediary_path' folder doesn't exist! Create it?"
            pause
            New-Item -Path "$intermediary_path\.." -Name "por arranjar - iphone" -ItemType "directory"
            # TODO
            return
        }
		
        # TODO: Remove filter
		& "$PSScriptRoot\mptcopy.ps1" -phoneName 'Apple iPhone' -sourceFolder '\Internal Storage\DCIM' -targetFolder $intermediary_path -filter '(.jpg)|(.jpeg)|(.png)|(.gif)|(.avi)|(.mov)|(.mp4)|(.HEIC)|(.HEIF)'
        # TODO: workaround windows crash when accessing iphone:
        # ex: [Window Title] Error Moving File or Folder [Content] The requested value cannot be determined. [OK]
        # when fail to connect to iphone: unplug, wait 1min, plug . try to avoid restart PC
    }
}

# 0) Confirma que pasta é onde deveriamos estar
cd $intermediary_path
$curDir = Get-Location
echo "Tens a certeza que queres organizar a pasta $curDir ?"
pause


# 0) corrige datas de criação/taken mais recentes q de modificação
#& "fix creation dates to not be newer than other dates.ps1"
# 0) corrige datas no futuro
# 0) questiona (warning) de datas demasiado no passado
# 1) mostra todas as datas de uma dada foto ordenadas temporalmente
#exiftool -a -G0:1 -time:all
#exiftool -a -G0:1 -time:FileModifyDate -filename IMG_7953.PNG
# jExifToolGUI
#exiftool -p "$filename has date $dateTimeOriginal" -f <dir_where_to_Search>
# 2) utilizador escolhe
# 3) regista numa DB:
#    o) extensão do ficheiro
#    a) estilo do nome do ficheiro
#    b) camara (tlm) usada: marca + modelo
#    c) onde é q a data é a correcta de usar
# 4) Mover fotos para pasta ano/mes/dia
$extensions="-ext avi -ext mov -ext mp4 -ext jpg -ext jpeg -ext png -ext thm -ext HEIC -ext AAE -ext webp"
echo "Extensões a trabalhar: $extensions"

echo "Let's now organize the multimedia?"
pause

$global:LASTEXITCODE = 0
Invoke-Expression "& `"exiftool.exe`" -r -P $extensions -v0 -d `"$output_path\%Y\%m-%B\%d\%%c\%%f.%%e`" `"-filename<oldest_date`" ."
#Invoke-Expression "& `"exiftool.exe`" -r -P $extensions -v0 -d `"$output_path\%Y\%m-%B\%d\%%c\%%f.%%e`" `"-testname<oldest_date`" ." # for DEBUG purposes
if($LASTEXITCODE){
    echo "ERROR: Couldn't run exiftool correctly"
    Invoke-Expression "& EchoArgs `"exiftool.exe`" -r -P $extensions -v0 -d `"$output_path\%Y\%m-%B\%d\%%c\%%f.%%e`" `"-filename<oldest_date`" ."
    return
}

# 5) nas próximas fotos fazer auto/ p as já definidas

# 6) fazer igual para video

# Apagar ficheiros .nomedia (veem do WhatsApp)
$nomedia_files = gci $intermediary_path -file -recurse -include ".nomedia"
$nomedia_files | Foreach-Object { Remove-Item $_ }
# Apagar pasta vazias
$dirs = gci $intermediary_path -directory -recurse | Where { (gci $_.fullName).count -eq 0 } | select -expandproperty FullName
$dirs | Foreach-Object { Remove-Item $_ }
# Apagar 2º nível de pastas vazias (pastas que continham pastas vazias)
$dirs = gci $intermediary_path -directory -recurse | Where { (gci $_.fullName).count -eq 0 } | select -expandproperty FullName
$dirs | Foreach-Object { Remove-Item $_ }

# TODO: run dupeguru and remove duplicates