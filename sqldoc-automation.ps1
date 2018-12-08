#######################################################################################################################
## 
## name:        
##      sqldoc-automation.ps1
##
##      powershell script to run Redgate SQL Doc on a database and move the resulting Data Dictionary file to a fileshare
##
##      discussion here:  https://www.kkarnsdba.com/2018/12/08/automatic-documentation-redgate-sql-doc-and-powershell/
##
## syntax:
##      .\sqldoc-automation.ps1
##
## dependencies:
##      windows task or sql server job to run this every day 
##      loads of parameters in a Settings.xml file
##      three sets of credentials (database, local user, fileshare)
##      redgate client service running and run at least once with same credentials running the job
##      redgate client reg key updated HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Red Gate\Client\ActivationPlugin: Transport=WCF
##
## updated:
##      -- Monday, December 3, 2018 3:05 PM - converted from a similar script
##
## todo:
##

## Command line arguments #############################################################################################

## parse command line argument to get the Settings.xml file to use
## sqldoc-automation.ps1 -settings OtherSettings.xml

Param 
    ( 
    [Parameter(Mandatory=$false, Position=0)] [AllowEmptyString()] [string] $settings = "Settings.xml" 
    )

## Functions ##########################################################################################################

##
## LogWrite - write messages to log file 
##

Function LogWrite
{
   Param ([string]$logstring)
   Add-content $Logfile -value $logstring 
}

##########################################################################################################
##
## ExtractPassword - Get a password from the encrypted credentials file 
##
Function ExtractPassword
{
    Param
    (
         [Parameter(Mandatory=$true, Position=0)]   [string] $tryCredentialsFile,
         [Parameter(Mandatory=$true, Position=1)]   [string] $tryServerUsername,
         [Parameter(Mandatory=$true, Position=2)] [AllowEmptyString()]  [string] $tryServerPassword
    )

##
## Get the destination password from the encrypted credentials file 
## 
## https://blogs.technet.microsoft.com/robcost/2008/05/01/powershell-tip-storing-and-using-password-credentials/
## note the pre-requisite (as explained in the blog)
##     credentials.txt   
## which comes from:  
##     read-host -assecurestring | convertfrom-securestring | out-file credentials-xyz.txt
##

if(![System.IO.File]::Exists($tryCredentialsFile))
    {
    echo ("Error. Halted. Missing encrypted credentials file.")
    LogWrite ("Error. Halted. Missing encrypted credentials file.")
    throw ("Error. Halted. Missing encrypted credentials file.")
    }

$passwordSecureString = get-content $tryCredentialsFile | convertto-securestring
$credentialsObject = new-object -typename System.Management.Automation.PSCredential -argumentlist $tryServerUsername,$passwordSecureString
LogWrite ("credentials            :  " + $credentialsObject)
LogWrite ("decrypted username     :  " + $credentialsObject.GetNetworkCredential().UserName)
LogWrite ("decrypted password     :  " + "<redacted>")          
$tryServerPassword = $credentialsObject.GetNetworkCredential().password

return $tryServerPassword

}


## Main Code ##########################################################################################################

try {
##                      
## set local code path and initialize settings file 
##
$myDir = Split-Path -Parent $MyInvocation.MyCommand.Path

## setup the logfile
$LogDir = $myDir + "\logs"
if(-not ([IO.Directory]::Exists($LogDir))) {New-Item -ItemType directory -Path $LogDir}
$Logfile = ($LogDir + "\sqldoc-automation-" + $(get-date -f yyyy-MM-dd-HHmmss) + ".log")
echo "results are logged to:  "$Logfile 
LogWrite ("Started at:  " + $(get-date -f yyyy-MM-dd-HHmmss))
$date1 = Get-Date

LogWrite ("opening Settings.xml file:  " + ($myDir + "\" + $settings) )
if (Test-Path ("$myDir\" + $settings)) 
    {
    [xml]$ConfigFile = Get-Content ("$myDir\" + $settings)
    }
else {
    echo ("Error. Halted. Couldn't find Settings.xml file.")
    LogWrite ("Error. Halted. Couldn't find Settings.xml file.")
    throw ("Error. Halted. Couldn't find Settings.xml file.")
    }

##
## Get variables from the settings.xml file 
##


$sourceDatabaseServer           = $ConfigFile.sqldoc_automation.sourceDatabaseServer            
$sourceDatabaseName             = $ConfigFile.sqldoc_automation.sourceDatabaseName              
$sourceDatabaseUser             = $ConfigFile.sqldoc_automation.sourceDatabaseUser              
$sourceDatabaseInstance         = $ConfigFile.sqldoc_automation.sourceDatabaseInstance          
$sourceDatabaseCredentialsFile  = $ConfigFile.sqldoc_automation.sourceDatabaseCredentialsFile   

$sqldocProjectDir               = $ConfigFile.sqldoc_automation.sqldocProjectDir                
$sqldocProjectFile              = $ConfigFile.sqldoc_automation.sqldocProjectFile               

$sqldocOutputDir                = $ConfigFile.sqldoc_automation.sqldocOutputDir                 
$sqldocOutputFile               = $ConfigFile.sqldoc_automation.sqldocOutputFile                ## note: is volitile, (1) is either pdf or docx, (2) this is the name that *sqldoc* gives to the file, we need to pre-delete, post-rename, and post-move this file  
$sqldocOutputType               = $ConfigFile.sqldoc_automation.sqldocOutputType                ## note: redgate parameter: switch to either {PDF or DOCX} upper case 

$destinationPath                = $ConfigFile.sqldoc_automation.destinationPath                 
$destinationFile                = $ConfigFile.sqldoc_automation.destinationFile                 

$destinationNeedsMapping        = $ConfigFile.sqldoc_automation.destinationNeedsMapping         
$destinationDriveLetter         = $ConfigFile.sqldoc_automation.destinationDriveLetter          
$destinationShareName           = $ConfigFile.sqldoc_automation.destinationShareName            
$destinationUsername            = $ConfigFile.sqldoc_automation.destinationUsername             
$destinationCredentialsFile     = $ConfigFile.sqldoc_automation.destinationCredentialsFile      

LogWrite ("sourceDatabaseServer          :  " + $sourceDatabaseServer         )
LogWrite ("sourceDatabaseName            :  " + $sourceDatabaseName           )
LogWrite ("sourceDatabaseUser            :  " + $sourceDatabaseUser           )
LogWrite ("sourceDatabaseInstance        :  " + $sourceDatabaseInstance       )
LogWrite ("sourceDatabaseCredentialsFile :  " + $sourceDatabaseCredentialsFile)
LogWrite ("sqldocProjectDir              :  " + $sqldocProjectDir             )
LogWrite ("sqldocProjectFile             :  " + $sqldocProjectFile            )
LogWrite ("sqldocOutputDir               :  " + $sqldocOutputDir              )
LogWrite ("sqldocOutputFile              :  " + $sqldocOutputFile             )
LogWrite ("sqldocOutputType              :  " + $sqldocOutputType             )
LogWrite ("destinationPath               :  " + $destinationPath              )
LogWrite ("destinationFile               :  " + $destinationFile              )
LogWrite ("destinationNeedsMapping       :  " + $destinationNeedsMapping      )
LogWrite ("destinationDriveLetter        :  " + $destinationDriveLetter       )
LogWrite ("destinationShareName          :  " + $destinationShareName         )
LogWrite ("destinationUsername           :  " + $destinationUsername          )
LogWrite ("destinationCredentialsFile    :  " + $destinationCredentialsFile   )


##
## extract password for source database 
##

$tryCredentialsFile = $MyDir+ "\" + $sourceDatabaseCredentialsFile
$tryServerUsername  = $sourceDatabaseUser
$tryServerPassword  = $destinationPassword
$sourceDatabasePassword = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword


##
## sqldoc won't replace a file, so remove the previous sqldoc output document
##

if(-not ([IO.Directory]::Exists($sqldocOutputDir))) 
    {
    echo ("Error. Halted. Couldn't find sqldoc Output directory on this server.")
    LogWrite ("Error. Halted. Couldn't find sqldoc Output directory on this server.")
    throw ("Error. Halted. Couldn't find sqldoc Output directory on this server.")
    }

LogWrite ("purging last sqldoc output file:  " + $($sqldocOutputDir + $sqldocOutputFile) )
if (Test-Path ($sqldocOutputDir + $sqldocOutputFile)) 
    {
    Remove-Item -Path ($sqldocOutputDir + $sqldocOutputFile) -Force
    }
else {
    LogWrite ("no previous sqldoc output file to purge.")
    }

##
## use a "here string" aka "splat operator", insert the parameters into the sqldoc command string
##
## "C:\Program Files (x86)\Red Gate\SQL Doc 4\sqldoc" /project:C:\path-to-sqldoc-project-test\INSTANCE_Documentation.sqldoc /server:instance /username:BATMAN /password:opensesame /database:DBNAME /filetype:PDF /exclude_timestamp
##                                                             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^         ^^^^^^^^           ^^^^^^           ^^^^^^^^^^           ^^^^^^           ^^^                           
##                                                             $spd                           $spf                                  $sdi               $sdu             $sdp                 $sdn             $sot
##
## $sds            $sourceDatabaseServer           = $ConfigFile.sqldoc_automation.sourceDatabaseServer            
## $sdn            $sourceDatabaseName             = $ConfigFile.sqldoc_automation.sourceDatabaseName              
## $sdu            $sourceDatabaseUser             = $ConfigFile.sqldoc_automation.sourceDatabaseUser              
## $sdi            $sourceDatabaseInstance         = $ConfigFile.sqldoc_automation.sourceDatabaseInstance          
## $sdp            $sourceDatabasePassword         = from ExtractPassword()
##              
## $spd            $sqldocProjectDir               = $ConfigFile.sqldoc_automation.sqldocProjectDir                
## $spf            $sqldocProjectFile              = $ConfigFile.sqldoc_automation.sqldocProjectFile               
## 
## $sot            $sqldocOutputType               = $ConfigFile.sqldoc_automation.sqldocOutputType                
## 

$command = @"
& "C:\Program Files (x86)\Red Gate\SQL Doc 4\sqldoc" /project:{0}{1} /server:{2} /username:{3} /password:{4} /database:{5} /filetype:{6} /exclude_timestamp
"@ -f $sqldocProjectDir, $sqldocProjectFile, $sourceDatabaseInstance, $sourceDatabaseUser, $sourceDatabasePassword, $sourceDatabaseName, $sqldocOutputType

echo "--------------------------------------"
$command
echo "--------------------------------------"
LogWrite ("command               :  " + $command)

Invoke-Expression -Command:$command -OutVariable out | Tee-Object -Variable out
LogWrite ("output                :  " + $out)


##
## if needed, map X: drive to the destination folder
##
## net use X: "\\DESTSERVER\d$" "/user:ADSDOMAIN\adsusername" opensesame 
##         ^^  ^^^^^^^^^^^^^^^^        ^^^^^^^^^^^^^^^^^^^^^  ^^^^^^^^^^ 
##       $ddl  $dsn                    $dun                   $dpw            
##
if ($destinationNeedsMapping -eq "Y")   
    {
    ## step 1.) extract password for destination sharename #################
    $tryCredentialsFile = $MyDir+ "\" + $destinationCredentialsFile
    $tryServerUsername  = $destinationUsername
    $tryServerPassword  = $destinationPassword
    $destinationPassword = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword


    ## step 2.) unmap drive #################
$command1 = @"
net use {0} /delete /y
"@ -f $destinationDriveLetter

    echo "--------------------------------------"
    $command1
    echo "--------------------------------------"
    LogWrite ("command1              :  " + $command1)

    Invoke-Expression -Command:$command1 -OutVariable out | Tee-Object -Variable out
    LogWrite ("output                :  " + $out)


    ## step 3.) remap drive #################
$command2 = @"
net use {0} "{1}" "/user:{2}" {3} 
"@ -f $destinationDriveLetter, $destinationShareName, $destinationUsername, $destinationPassword            

    echo "--------------------------------------"
    $command2
    echo "--------------------------------------"
    LogWrite ("command2              :  " + $command2)

    Invoke-Expression -Command:$command2 -OutVariable out | Tee-Object -Variable out
    LogWrite ("output                :  " + $out)
    }
else {
    LogWrite ("according to the settings.xml, no drive mapping needed.  destinationNeedsMapping = " + $destinationNeedsMapping)
    }

##
## next, move the sqldoc output document to the destination path
##

LogWrite ("moving sqldoc output file to destination path:  " + $($destinationPath + $destinationFile)+ $(get-date -f yyyy-MM-dd-HHmmss) + "." + $sqldocOutputType.ToLower() )
if ( (Test-Path ($sqldocOutputDir + $sqldocOutputFile)) -and (Test-Path ($destinationPath))) {
    Copy-Item -Path ($sqldocOutputDir + $sqldocOutputFile) -Destination ($destinationPath + $destinationFile + $(get-date -f yyyy-MM-dd-HHmmss) + "." + $sqldocOutputType.ToLower())
    }
else {
    echo ("Error. Halted. Couldn't find sqldoc output file or destination directory on this server.")
    LogWrite ("Error. Halted. Couldn't find sqldoc output file or destination directory on this server.")
    throw ("Error. Halted. Couldn't find sqldoc output file or destination directory on this server..")
    }


##
## need to cleanup output files after 14 days, add a README file to warn others.
##
$docRetention = (Get-Date).AddDays(-14)
LogWrite ("purging SQL Doc files older than   :  " + $($docRetention) )
Get-ChildItem -Path $destinationPath -Filter "*docx*" | Where-Object { !$_.PSIsContainer -and $_.CreationTime -lt $docRetention } | Remove-Item -Force
Get-ChildItem -Path $destinationPath -Filter "*pdf*" | Where-Object { !$_.PSIsContainer -and $_.CreationTime -lt $docRetention } | Remove-Item -Force

#throw ("Halted.  This is the end.  Who knew.")

}
Catch {
    ##
    ## log any error
    ##    
    LogWrite $Error[0]
}
Finally {

    ##
    ## go back to the software directory where we started
    ##
    set-location $myDir

    LogWrite ("finished at:  " + $(get-date -f yyyy-MM-dd-HHmmss))
}