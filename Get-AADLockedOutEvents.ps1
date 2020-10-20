<#

.SYNOPSIS
    Get-AADLockedoutEvents PowerShell script.

.DESCRIPTION
    Get-AADLockedOutEvents.ps1 is a PowerShell script retrieves and checks Locked users events, checks locked users, since  how long, and when they will be unlocked.

.NOTE:
    - This PowerShell requires to install, import AzureADPreview module, and Connect to AzureAD as a Global Admin before run it. You can use the following commands to do so:
        Install-Module AzureADPreview
        Import-Module AzureADPreview
        Connect-AzureAD


.AUTHOR:
    Mohammad Zmaili

.PARAMETER
    ThresholdDays
    Specifies the period of the last login.
    Note: The default value is 90 days if this parameter is not configured.

.PARAMETER
    LockoutDuration
    Allows you to specify the lockout duration (in seconds), where this parameter will be used to verify the locked users
    Note: Default value is 60 seconds.


.EXAMPLE
    .\Get-AADLockedUsers.ps1
      Verifies the lockout events for the last 90 days, and verifies the locked users considering the lockout duration is 60 seconds.

.EXAMPLE
    .\Get-AADLockedUsers.ps1 -LockoutDuration 3600
      Verifies the lockout events for the last 90 days, and verifies the locked users considering the lockout duration is 3600 seconds (30 minuts).

.EXAMPLE
    .\Get-AADLockedUsers.ps1 -ThresholdDays 30 -LockoutDuration 3600
      Verifies the lockout events for the last 30 days, and verifies the locked users considering the lockout duration is 3600 seconds (30 minuts).
        
#>


[cmdletbinding()]
param(
        [Parameter(Mandatory=$false)]
        [Int]$ThresholdDays =90,
        
        [Parameter(Mandatory=$false)]
        [Int]$LockoutDuration =60
    )

$VerifyFrom = [datetime](get-date).AddDays(- $ThresholdDays)
$VerifyFrom = $VerifyFrom.ToString("yyyy-MM-dd")
$rep =@()
$LockedUsersEvents=0
$LockedUsersCount=0
$filter = "status/errorCode ne 0 and createdDateTime gt "+$VerifyFrom
$LockoutEvents = Get-AzureADAuditSignInLogs -Filter $filter

foreach ($signin in $LockoutEvents){
    if ($signin.Status.FailureReason -eq "The account is locked, you've tried to sign in too many times with an incorrect user ID or password."){
        $UnlockAfter=0
        $LockedSince=0
        $LastSuccessSignin ="N/A"
        $LockedUsersEvents += 1
        $lockTimeandDuration = (($signin.CreatedDateTime).tostring() -split "\.")[0]
        $lockTimeandDuration = [datetime]$lockTimeandDuration
        $lockedTime=$lockTimeandDuration
        $lockTimeandDuration = $lockTimeandDuration.AddSeconds($LockoutDuration)

        #get last successful signin
        $filter = "status/errorCode eq 0 and userPrincipalName eq '"+$signin.UserPrincipalName+"'"
        $LastSuccessSignin = Get-AzureADAuditSignInLogs -Filter $filter -top 1
        $LastSuccessSignin = (($LastSuccessSignin.CreatedDateTime).tostring() -split "\.")[0]
        $LastSuccessSignin = [datetime]$LastSuccessSignin

        if (((get-date).ToUniversalTime()) -gt $lockTimeandDuration){
            $IsLocked = $false
        }else{

            if ($LastSuccessSignin -gt $lockedTime){
                $IsLocked = $false
            }else{
                $IsLocked = $true
                $LockedUsersCount+=1
            
                $LockedSince = (New-TimeSpan -Start $lockedTime -End ((get-date).ToUniversalTime())).TotalMinutes
                $LockedSince = ($LockedSince.tostring() -split "\.")[0]

                $UnlockAfter = (New-TimeSpan -Start ((get-date).ToUniversalTime())-End $lockTimeandDuration).TotalMinutes
                $UnlockAfter = ($UnlockAfter.tostring() -split "\.")[0]
            }
        }
        
        $repobj = New-Object PSObject
        $repobj | Add-Member NoteProperty -Name "Is Locked" -Value $IsLocked
        $repobj | Add-Member NoteProperty -Name "Locked Since (Minuts)" -Value $LockedSince
        $repobj | Add-Member NoteProperty -Name "UnLock After (Minuts)" -Value $UnlockAfter
        $repobj | Add-Member NoteProperty -Name "Event Time (UTC)" -Value $signin.CreatedDateTime
        $repobj | Add-Member NoteProperty -Name "Last Success Signin (UTC)" -Value $LastSuccessSignin
        $repobj | Add-Member NoteProperty -Name "User Name" -Value $signin.UserDisplayName
        $repobj | Add-Member NoteProperty -Name "User UPN" -Value $signin.UserPrincipalName
        $repobj | Add-Member NoteProperty -Name "Client App" -Value $signin.ClientAppUsed
        $repobj | Add-Member NoteProperty -Name "Application" -Value $signin.AppDisplayName
        $repobj | Add-Member NoteProperty -Name "IP Address" -Value $signin.IpAddress
        $repobj | Add-Member NoteProperty -Name "Error Code" -Value $signin.Status.ErrorCode
        $repobj | Add-Member NoteProperty -Name "Failure Reason" -Value $signin.Status.FailureReason
        $repobj | Add-Member NoteProperty -Name "Additional Details" -Value $signin.Status.AdditionalDetails
        $repobj
        $rep += $repobj
    }
}

Write-Host "Number of LockOut Events:" $LockedUsersEvents
Write-Host "Number of Locked User Events:" $LockedUsersCount
Write-Host "Lockout events verified since:" $VerifyFrom

$Date=("{0:s}" -f (get-date)).Split("T")[0] -replace "-", ""
$Time=("{0:s}" -f (get-date)).Split("T")[1] -replace ":", ""
$filerep = "LockoutUsersEvents_" + $Date + $Time + ".csv"
$rep | Export-Csv -path $filerep -NoTypeInformation


